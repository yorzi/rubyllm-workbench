require "test_helper"

class Ai::Knowledge::GroundedAnswerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  class FakeChat < SimpleDelegator
    attr_reader :requests, :instructions, :schema

    def initialize(chat, response:, after_request: nil)
      super(chat)
      @response = response
      @after_request = after_request
      @requests = []
      @request_hooks = []
    end

    def with_instructions(value, **)
      @instructions = value
      self
    end

    def with_schema(value)
      @schema = value
      self
    end

    def with_max_output_tokens(_value)
      self
    end

    def before_request(&block)
      @request_hooks << block
      self
    end

    def ask(prompt)
      @request_hooks.each { |hook| hook.call(model: model_id) }
      @requests << JSON.parse(prompt)
      @after_request&.call
      RubyLLM::Message.new(role: :assistant, content: JSON.generate(@response), tokens: RubyLLM::Tokens.new(input: 30, output: 20))
    end
  end

  setup do
    @project = create_project(name: "Grounded answer tests")
    @collection = @project.knowledge_collections.create!(name: "Source notes")
    @source = @collection.knowledge_items.create!(
      title: "Note model", source_reference: "mini_notes/app/models/note.rb",
      content_text: "class Note < ApplicationRecord\n  validates :title, presence: true\nend"
    )
    Ai::Knowledge::Ingestor.call(@source)
    @model = RubyLLM.models.chat_models.all.find { |model| model.supports?(:structured_output) }
  end

  test "freezes corpus and bounded untrusted evidence before enqueueing" do
    assert_enqueued_with(job: GroundedAnswerJob) { @run = enqueue }
    snapshot = @run.input_snapshot.fetch("grounded_answer")
    evidence = snapshot.fetch("evidence").sole
    assert_equal "lexical-v1", snapshot.dig("retrieval", "algorithm")
    assert_nil snapshot.dig("retrieval", "embedding_model_id")
    assert_equal @source.checksum, evidence.fetch("source_checksum")
    assert_equal @source.content_text, evidence.fetch("text")
    assert_equal "untrusted", evidence.fetch("trust")
    assert_equal @source.knowledge_chunks.sole.id, evidence.fetch("chunk_id")
    assert_equal "char_window_v1", evidence.fetch("chunker")
    assert_equal 2_048, snapshot.dig("generation_options", "max_output_tokens")
    assert_equal 1, @run.attempts.count
  end

  test "checks citations against frozen evidence and records Attempt and Artifact" do
    run = enqueue
    chat = FakeChat.new(run.chat, response: answer)
    Ai::Knowledge::GroundedAnswerExecutor.new(run.id, chat:).call
    assert run.reload.succeeded?, run.error_summary
    assert run.attempts.sole.succeeded?
    assert_equal "answered", run.result_summary.fetch("answer_status")
    assert_equal "valid", run.artifacts.sole.metadata_json.fetch("citation_validation")
    assert_equal 30, run.attempts.sole.input_tokens
    assert_equal 1, chat.requests.size
    assert_includes chat.instructions, "Never"
    assert_equal "grounded_answer", chat.schema.fetch(:name)
    assert_equal @source.content_text, chat.requests.sole.fetch("evidence").sole.fetch("text")
  end

  test "empty retrieval refuses locally without a provider attempt or request" do
    run = enqueue(question: "quasarxyz")
    chat = FakeChat.new(run.chat, response: answer)
    Ai::Knowledge::GroundedAnswerExecutor.new(run.id, chat:).call
    assert run.reload.succeeded?
    assert_equal "insufficient_evidence", run.result_summary.fetch("answer_status")
    assert_equal false, run.result_summary.fetch("model_request")
    assert_empty run.attempts
    assert_empty chat.requests
    assert_nil run.total_cost
    assert_equal "unknown", run.cost_status
  end

  test "unsupported claims and fabricated quotes fail without a valid artifact" do
    [ answer.merge("claims" => [ { "text" => "Uncited claim", "citations" => [] } ]),
      answer.deep_dup.tap { |value| value["claims"][0]["citations"][0]["evidence_id"] = "e99" },
      answer.deep_dup.tap { |value| value["claims"][0]["citations"][0]["quote"] = "fabricated code" },
      answer.merge("status" => "insufficient_evidence", "reason" => "Missing code"),
      answer.merge("extra" => "unsupported") ].each do |output|
      run = enqueue
      Ai::Knowledge::GroundedAnswerExecutor.new(run.id, chat: FakeChat.new(run.chat, response: output)).call
      assert run.reload.failed?
      assert run.attempts.sole.failed?
      assert_includes %w[citation_validation schema_validation], run.result_summary.fetch("failure_kind")
      assert_empty run.artifacts
    end
  end

  test "a model refusal with relevant but insufficient evidence remains an explicit successful outcome" do
    run = enqueue
    output = { "status" => "insufficient_evidence", "claims" => [], "reason" => "This source does not describe deployment." }
    Ai::Knowledge::GroundedAnswerExecutor.new(run.id, chat: FakeChat.new(run.chat, response: output)).call
    assert run.reload.succeeded?
    assert_equal "insufficient_evidence", run.result_summary.fetch("answer_status")
    assert_equal true, run.result_summary.fetch("model_request")
  end

  test "an answered reason remains metadata rather than an additional uncited claim" do
    run = enqueue
    chat = FakeChat.new(run.chat, response: answer.merge("reason" => "Model rationale; unverified."))
    Ai::Knowledge::GroundedAnswerExecutor.new(run.id, chat:).call
    assert run.reload.succeeded?
    assert_equal 1, run.artifacts.sole.content_json.fetch("claims").size
    assert_equal "Model rationale; unverified.", run.artifacts.sole.content_json.fetch("reason")
  end

  test "queued source changes fail before the model request and preserve original evidence" do
    run = enqueue
    original = run.input_snapshot.deep_dup
    @source.update!(content_text: "class Note\nend")
    chat = FakeChat.new(run.chat, response: answer)
    Ai::Knowledge::GroundedAnswerExecutor.new(run.id, chat:).call
    assert run.reload.failed?
    assert_equal "stale_evidence", run.result_summary.fetch("failure_kind")
    assert_equal original, run.input_snapshot
    assert_empty chat.requests
    assert_empty run.artifacts
  end

  test "new sources and re-ingestion invalidate queued corpus revision" do
    [ -> { @collection.knowledge_items.create!(title: "Extra source", content_text: "Other notes").tap { |item| Ai::Knowledge::Ingestor.call(item) } },
      -> { Ai::Knowledge::Ingestor.call(@source) } ].each do |change|
      run = enqueue
      change.call
      Ai::Knowledge::GroundedAnswerExecutor.new(run.id).call
      assert_equal "stale_evidence", run.reload.result_summary.fetch("failure_kind")
    end
  end

  test "inconsistent source offsets cannot be frozen as valid evidence" do
    @source.knowledge_chunks.sole.update!(char_start: 2)
    assert_no_difference [ "Run.count", "Chat.count" ] do
      assert_raises(Ai::Knowledge::EvidenceSnapshot::StaleEvidence) { enqueue }
    end
  end

  test "a duplicate job and a job delivered after queued cancellation never call a model" do
    run = enqueue
    chat = FakeChat.new(run.chat, response: answer)
    executor = Ai::Knowledge::GroundedAnswerExecutor.new(run.id, chat:)
    executor.call
    executor.call
    assert_equal 1, chat.requests.size
    assert_equal 1, run.artifacts.count

    cancelled = enqueue
    cancelled.cancel!
    chat = FakeChat.new(cancelled.chat, response: answer)
    Ai::Knowledge::GroundedAnswerExecutor.new(cancelled.id, chat:).call
    assert_empty chat.requests
    assert cancelled.reload.cancelled?
  end

  test "cancellation during a request fences its late successful result" do
    run = enqueue
    chat = FakeChat.new(run.chat, response: answer, after_request: -> { run.cancel! })
    Ai::Knowledge::GroundedAnswerExecutor.new(run.id, chat:).call
    assert run.reload.cancelled?
    assert run.attempts.sole.cancelled?
    assert_empty run.artifacts
  end

  test "cancellation after claiming and before starting cannot revive a cancelled Attempt" do
    run = enqueue
    chat = FakeChat.new(run.chat, response: answer)
    snapshot_class = Ai::Knowledge::EvidenceSnapshot
    before = snapshot_class.method(:verify_current!)
    snapshot_class.define_singleton_method(:verify_current!) do |snapshot, project:|
      before.call(snapshot, project:)
      Run.find(run.id).cancel!
    end
    Ai::Knowledge::GroundedAnswerExecutor.new(run.id, chat:).call
    assert run.reload.cancelled?
    assert run.attempts.sole.cancelled?
    assert_empty chat.requests
  ensure
    snapshot_class.define_singleton_method(:verify_current!, before)
  end

  test "worker recovery fences late results and never replays a provider call" do
    queued = enqueue
    queued.update_columns(created_at: 1.hour.ago)
    GroundedAnswerRecoveryJob.perform_now
    assert_equal "worker_not_started", queued.reload.result_summary.fetch("failure_kind")

    run = enqueue
    chat = FakeChat.new(run.chat, response: answer, after_request: lambda {
      run.update_columns(started_at: 1.hour.ago)
      GroundedAnswerRecoveryJob.perform_now
    })
    Ai::Knowledge::GroundedAnswerExecutor.new(run.id, chat:).call
    assert run.reload.failed?
    assert run.attempts.sole.failed?
    assert_equal "worker_interrupted", run.result_summary.fetch("failure_kind")
    assert_equal false, run.result_summary.dig("recovery", "automatic_replay")
    assert_empty run.artifacts
    Ai::Knowledge::GroundedAnswerExecutor.new(run.id, chat:).call
    assert_equal 1, chat.requests.size
  end

  test "queue rejection fails the durable Run without leaving a queued Attempt" do
    before = GroundedAnswerJob.method(:perform_later)
    GroundedAnswerJob.define_singleton_method(:perform_later) { |*| raise ActiveJob::EnqueueError, "Queue unavailable" }
    assert_raises(ArgumentError) { enqueue }
    run = @project.runs.sole
    assert run.failed?
    assert run.attempts.sole.failed?
  ensure
    GroundedAnswerJob.define_singleton_method(:perform_later, before)
  end

  test "rolling back an outer transaction also discards its deferred answer job" do
    assert_no_difference [ "Run.count", "Chat.count" ] do
      assert_no_enqueued_jobs(only: GroundedAnswerJob) do
        @collection.transaction do
          enqueue
          raise ActiveRecord::Rollback
        end
      end
    end
  end

  test "an in-flight source edit does not replace the evidence used to validate the result" do
    run = enqueue
    chat = FakeChat.new(run.chat, response: answer, after_request: -> { @source.update!(content_text: "Removed title validation") })
    Ai::Knowledge::GroundedAnswerExecutor.new(run.id, chat:).call
    assert run.reload.succeeded?
    assert_includes run.input_snapshot.dig("grounded_answer", "evidence").sole.fetch("text"), "validates :title, presence: true"
    assert_equal "validates :title, presence: true", run.artifacts.sole.content_json.dig("claims", 0, "citations", 0, "quote")
  end

  test "a changed answer model fails rather than calling an unfrozen target" do
    run = enqueue
    chat = FakeChat.new(run.chat, response: answer)
    chat.define_singleton_method(:model_id) { "different-model" }
    Ai::Knowledge::GroundedAnswerExecutor.new(run.id, chat:).call
    assert run.reload.failed?
    assert_empty chat.requests
    assert_empty run.artifacts
  end

  test "context bounds reject oversized imported chunks" do
    text = "title " * 200
    @source.update!(content_text: text)
    @source.knowledge_chunks.delete_all
    @source.knowledge_chunks.create!(position: 0, content_text: @source.content_text, char_start: 0, char_end: @source.content_text.length)
    assert_raises(ArgumentError) { enqueue }
  end

  test "new persisted chat history fails before requesting an answer" do
    run = enqueue
    run.chat.messages.create!(role: "user", content: "Extra context outside the snapshot")
    chat = FakeChat.new(run.chat, response: answer)
    Ai::Knowledge::GroundedAnswerExecutor.new(run.id, chat:).call
    assert run.reload.failed?
    assert_empty chat.requests
    assert_empty run.artifacts
  end

  test "invalid inputs and a model outside the capability filter do not create records" do
    [ { question: " " }, { question: "x" * 501 }, { model_reference: "openrouter|invented:free" } ].each do |options|
      assert_no_difference [ "Run.count", "Chat.count" ] do
        assert_raises(ArgumentError) { enqueue(**options) }
      end
    end
  end

  private

  def enqueue(question: "title validation", model_reference: "#{@model.provider}|#{@model.id}")
    with_provider_configuration(@model.provider) do
      Ai::Knowledge::GroundedAnswer.enqueue(collection: @collection, question:, model_reference:)
    end
  end

  def answer
    { "status" => "answered", "reason" => "", "claims" => [ {
      "text" => "The title must be present.",
      "citations" => [ { "evidence_id" => "e1", "quote" => "validates :title, presence: true" } ]
    } ] }
  end
end

require "test_helper"

class Ai::Knowledge::NativeEvaluationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @corpus = Workbench::KnowledgeCaseStudy.import!
    @case = @corpus.cases.find { |entry| entry.fetch("key") == "title-validation" }
    @model = RubyLLM.models.chat_models.all.find { |model| model.provider == "openrouter" && model.supports?(:structured_output) }
    @answer_run = saved_answer
  end

  test "native assertions evaluate the saved Artifact without generating or judging again" do
    assert_enqueued_with(job: NativeEvaluationJob) { @evaluation = enqueue }
    Ai::Knowledge::NativeEvaluationExecutor.new(@evaluation.id).call
    assert @evaluation.reload.succeeded?, @evaluation.error_summary
    assert_empty @evaluation.attempts
    assert_empty @evaluation.chat.ruby_llm_usages
    assert_equal @answer_run.id, @evaluation.result_summary.fetch("answer_run_id")
    assert_equal "passed", @evaluation.result_summary.fetch("native_status")
    report = @evaluation.artifacts.sole.content_json
    assert_equal 2, report.dig("trials", 0, "assertion_count")
    assert_equal @answer_run.artifacts.sole.content_json, report.dig("trials", 0, "evidence")
    assert_equal false, @evaluation.result_summary.dig("accounting", "task_replayed")
    assert_equal false, @evaluation.result_summary.dig("accounting", "answer_cost_included")
    assert_equal "unknown", @evaluation.cost_status
    assert_nil @evaluation.total_cost
  end

  test "the native OpenRouter reviewer performs exactly one HTTP call and owns only evaluation usage" do
    received = nil
    request = reviewer_request do |http|
      received = JSON.parse(http.body)
      true
    end
    with_provider_configuration("openrouter") do
      evaluation = enqueue(evaluator_kind: "reviewer", model_reference: "openrouter|#{@model.id}")
      Ai::Knowledge::NativeEvaluationExecutor.new(evaluation.id).call
      assert evaluation.reload.succeeded?, evaluation.error_summary
      assert_equal "passed", evaluation.result_summary.fetch("native_status")
      assert_equal 1, evaluation.attempts.count
      assert_equal 37, evaluation.attempts.sole.input_tokens
      assert_equal 16, evaluation.attempts.sole.output_tokens
      assert_equal 1, evaluation.attempts.sole.ruby_llm_usages.count
      assert_equal [ evaluation.attempts.sole.ruby_llm_usages.sole.id ], evaluation.attempts.sole.ruby_llm_usage_ids_json
      assert_equal "chat", evaluation.attempts.sole.ruby_llm_usages.sole.operation
      assert_empty evaluation.chat.ruby_llm_usages
      assert_empty @answer_run.chat.ruby_llm_usages
      report = evaluation.artifacts.sole.content_json
      assert_equal 37, report.dig("trials", 0, "evaluator_tokens", "input_tokens")
      assert_empty report.dig("trials", 0, "task_tokens")
      assert_equal %w[grounding source_boundary], report.dig("trials", 0, "evaluations").map { |value| value.fetch("name") }
      assert_equal 2_048, received["max_tokens"] || received["max_completion_tokens"]
      assert_nil received["tools"]
      assert_includes received.fetch("messages").last.fetch("content"), @answer_run.artifacts.sole.content_json.fetch("claims").first.fetch("text")
      assert_requested request, times: 1
    end
  end

  test "typed native Judge uses the decision protocol and returns measurements without an arbitrary threshold" do
    model = RubyLLM.models.all.find { |entry| entry.provider == "typesafe" && entry.type == :judgment }
    received = nil
    request = WebMock.stub_request(:post, "https://api.typesafe.ai/v1/systemone").with do |http|
      received = JSON.parse(http.body)
      true
    end.to_return(status: 200, headers: { "content-type" => "application/json" }, body: JSON.generate(
      model: model.id, answers: { supported: { noul: 0.8 }, source_boundary: { noul: 0.9 } },
      usage: { input_tokens: 23, output_tokens: 2 }
    ))
    with_provider_configuration("typesafe") do
      evaluation = enqueue(evaluator_kind: "judge", model_reference: "typesafe|#{model.id}")
      Ai::Knowledge::NativeEvaluationExecutor.new(evaluation.id).call
      assert evaluation.reload.succeeded?, evaluation.error_summary
      assert_equal "measured", evaluation.result_summary.fetch("native_status")
      report = evaluation.artifacts.sole.content_json
      results = report.dig("trials", 0, "evaluations")
      assert_equal %w[measured measured], results.map { |entry| entry.fetch("status") }
      assert_equal [ 0.8, 0.9 ], results.map { |entry| entry.dig("value", "probability") }
      assert_equal "judgment", evaluation.attempts.sole.ruby_llm_usages.sole.operation
      assert_equal 23, evaluation.attempts.sole.input_tokens
      assert_equal %w[source_boundary supported], received.fetch("questions").keys.sort
      assert_equal "noul", received.dig("questions", "supported", "type")
      assert_requested request, times: 1
    end
  end

  test "OpenRouter chat structured output cannot be selected as a typed Judge" do
    with_provider_configuration("openrouter") do
      assert_no_difference [ "Run.count", "Chat.count" ] do
        error = assert_raises(ArgumentError) { enqueue(evaluator_kind: "judge", model_reference: "openrouter|#{@model.id}") }
        assert_includes error.message, "do not implement RubyLLM::Judge"
      end
    end
  end

  test "a case status assertion failure is a completed evaluation and not an execution failure or truth claim" do
    artifact = @answer_run.artifacts.sole
    artifact.update!(content_json: { "status" => "insufficient_evidence", "reason" => "Not enough context.", "claims" => [] })
    evaluation = enqueue
    NativeEvaluationJob.perform_now(evaluation.id)
    assert evaluation.reload.succeeded?
    assert_equal "failed", evaluation.result_summary.fetch("native_status")
    assert_includes evaluation.artifacts.sole.content_json.dig("trials", 0, "assertion_failure"), "differs from the case reference"
  end

  test "missing evidence refusals are evaluated without an answer provider request" do
    @case = @corpus.cases.find { |entry| entry.fetch("key") == "missing-billing" }
    @answer_run = saved_answer(empty: true)
    evaluation = enqueue
    NativeEvaluationJob.perform_now(evaluation.id)
    assert evaluation.reload.succeeded?
    assert_equal "passed", evaluation.result_summary.fetch("native_status")
    assert_empty evaluation.attempts
    assert_empty @answer_run.attempts
  end

  test "native evaluator errors retain a report and failed usage without replay" do
    request = WebMock.stub_request(:post, "https://openrouter.ai/api/v1/chat/completions")
      .to_return(status: 429, headers: { "content-type" => "application/json" }, body: JSON.generate(error: { message: "Capacity unavailable" }))
    with_provider_configuration("openrouter") do
      evaluation = enqueue(evaluator_kind: "reviewer", model_reference: "openrouter|#{@model.id}")
      executor = Ai::Knowledge::NativeEvaluationExecutor.new(evaluation.id)
      executor.call
      executor.call
      assert evaluation.reload.failed?
      assert evaluation.attempts.sole.failed?
      assert_equal "error", evaluation.result_summary.fetch("native_status")
      assert_equal "error", evaluation.artifacts.sole.content_json.dig("trials", 0, "status")
      assert_equal 1, evaluation.attempts.sole.ruby_llm_usages.count
      assert_requested request, times: 1
    end
  end

  test "malformed reviewer criteria are recorded as protocol errors with received usage" do
    request = reviewer_request(verdicts: { grounding: { verdict: "pass", reason: "Only one required criterion was returned." } })
    with_provider_configuration("openrouter") do
      evaluation = enqueue(evaluator_kind: "reviewer", model_reference: "openrouter|#{@model.id}")
      NativeEvaluationJob.perform_now(evaluation.id)
      assert evaluation.reload.failed?
      assert evaluation.attempts.sole.failed?
      assert_equal 37, evaluation.attempts.sole.input_tokens
      assert_equal "error", evaluation.artifacts.sole.content_json.dig("trials", 0, "status")
      assert_requested request, times: 1
    end
  end

  test "missing reviewer token and price data remain unknown in report and ledger" do
    request = reviewer_request(usage: nil)
    with_provider_configuration("openrouter") do
      evaluation = enqueue(evaluator_kind: "reviewer", model_reference: "openrouter|#{@model.id}")
      NativeEvaluationJob.perform_now(evaluation.id)
      assert evaluation.reload.succeeded?, evaluation.error_summary
      assert_nil evaluation.attempts.sole.input_tokens
      assert_equal "unknown", evaluation.attempts.sole.cost_status
      assert_nil evaluation.total_cost
      report = evaluation.artifacts.sole.content_json
      assert_nil report.dig("trials", 0, "evaluator_tokens", "input_tokens")
      # Retain the gem's original numeric mirror for diagnosis. The application
      # ledger and coverage marker prevent treating it as a known bill.
      assert_equal 0.0, report.dig("trials", 0, "evaluator_cost", "total")
      assert_equal "incomplete", evaluation.result_summary.dig("accounting", "usage_coverage")
      assert_requested request, times: 1
    end
  end

  test "frozen output survives subsequent changes or deletion of the original answer" do
    evaluation = enqueue
    original_output = evaluation.input_snapshot.dig("native_evaluation", "answer_output").deep_dup
    @answer_run.destroy!
    @corpus.collection.knowledge_items.first.update!(content_text: "Edited after evaluation was queued")
    NativeEvaluationJob.perform_now(evaluation.id)
    assert evaluation.reload.succeeded?
    assert_equal original_output, evaluation.artifacts.sole.content_json.dig("trials", 0, "evidence")
  end

  test "incorrect pairing and a missing Artifact are rejected before creating evaluation records" do
    assert_no_difference [ "Run.count", "Chat.count" ] do
      assert_raises(ArgumentError) { enqueue(case_key: "note-ownership") }
      assert_raises(ArgumentError) { enqueue(case_key: "unknown") }
      @answer_run.artifacts.destroy_all
      assert_raises(ArgumentError) { enqueue }
    end
  end

  test "an edited frozen case is rejected before any reviewer request" do
    request = reviewer_request
    with_provider_configuration("openrouter") do
      evaluation = enqueue(evaluator_kind: "reviewer", model_reference: "openrouter|#{@model.id}")
      changed = evaluation.input_snapshot.deep_dup
      changed["native_evaluation"]["case"]["expected_status"] = "insufficient_evidence"
      evaluation.update!(input_snapshot_json: changed)
      NativeEvaluationJob.perform_now(evaluation.id)
      assert evaluation.reload.failed?
      assert_includes evaluation.error_summary, "changed after enqueueing"
      assert_empty evaluation.artifacts
      assert_empty evaluation.attempts.sole.ruby_llm_usages
      assert_not_requested request
    end
  end

  test "a duplicate job or queued cancellation cannot make another evaluator request" do
    request = reviewer_request
    with_provider_configuration("openrouter") do
      evaluation = enqueue(evaluator_kind: "reviewer", model_reference: "openrouter|#{@model.id}")
      2.times { NativeEvaluationJob.perform_now(evaluation.id) }
      assert evaluation.reload.succeeded?
      cancelled = enqueue(evaluator_kind: "reviewer", model_reference: "openrouter|#{@model.id}")
      cancelled.cancel!
      NativeEvaluationJob.perform_now(cancelled.id)
      assert cancelled.reload.cancelled?
      assert_empty cancelled.artifacts
      assert_requested request, times: 1
    end
  end

  test "cancellation during the HTTP request fences the report and preserves cancelled usage attribution" do
    evaluation = nil
    request = reviewer_request(on_response: -> { evaluation.cancel! })
    with_provider_configuration("openrouter") do
      evaluation = enqueue(evaluator_kind: "reviewer", model_reference: "openrouter|#{@model.id}")
      NativeEvaluationJob.perform_now(evaluation.id)
      assert evaluation.reload.cancelled?
      assert evaluation.attempts.sole.cancelled?
      assert_empty evaluation.artifacts
      assert_equal 37, evaluation.attempts.sole.input_tokens
      assert_equal [ evaluation.attempts.sole.ruby_llm_usages.sole.id ], evaluation.attempts.sole.ruby_llm_usage_ids_json
      assert_requested request, times: 1
    end
  end

  test "a cancelled Run cannot cross the native request boundary after setup" do
    delegate = RubyLLM.config.instrumenter
    request = reviewer_request
    with_provider_configuration("openrouter") do
      evaluation = enqueue(evaluator_kind: "reviewer", model_reference: "openrouter|#{@model.id}")
      instrumenter = Object.new
      instrumenter.define_singleton_method(:instrument) do |name, payload, &block|
        evaluation.cancel! if name == "chat.ruby_llm"
        delegate.instrument(name, payload, &block)
      end
      RubyLLM.config.instrumenter = instrumenter
      NativeEvaluationJob.perform_now(evaluation.id)
      assert evaluation.reload.cancelled?
      assert evaluation.attempts.sole.cancelled?
      assert_equal 1, evaluation.attempts.count
      assert_empty evaluation.artifacts
      assert_not_requested request
    end
  ensure
    RubyLLM.config.instrumenter = delegate
  end

  test "recovery during a request fences late native results and prohibits replay" do
    evaluation = nil
    request = reviewer_request(on_response: lambda {
      evaluation.update_columns(started_at: 1.hour.ago)
      NativeEvaluationRecoveryJob.perform_now
    })
    with_provider_configuration("openrouter") do
      evaluation = enqueue(evaluator_kind: "reviewer", model_reference: "openrouter|#{@model.id}")
      2.times { NativeEvaluationJob.perform_now(evaluation.id) }
      assert evaluation.reload.failed?
      assert evaluation.attempts.sole.failed?
      assert_equal "worker_interrupted", evaluation.result_summary.fetch("failure_kind")
      assert_equal 1, evaluation.attempts.sole.ruby_llm_usages.count
      assert_equal false, evaluation.result_summary.dig("recovery", "automatic_replay")
      assert_empty evaluation.artifacts
      assert_requested request, times: 1
    end
  end

  test "stale worker recovery terminalizes queued and running evaluation without replay" do
    queued = enqueue
    queued.update_columns(created_at: 1.hour.ago)
    NativeEvaluationRecoveryJob.perform_now
    assert_equal "worker_not_started", queued.reload.result_summary.fetch("failure_kind")
    running = enqueue
    running.claim_queued_execution!(operation: Ai::Knowledge::NativeEvaluation::OPERATION)
    running.update_columns(started_at: 1.hour.ago)
    NativeEvaluationRecoveryJob.perform_now
    assert_equal "worker_interrupted", running.reload.result_summary.fetch("failure_kind")
    assert_equal false, running.result_summary.dig("recovery", "automatic_replay")
    NativeEvaluationJob.perform_now(running.id)
    assert_empty running.artifacts
  end

  test "queue rejection fails the durable Run and deferred jobs respect outer rollback" do
    before = NativeEvaluationJob.method(:perform_later)
    NativeEvaluationJob.define_singleton_method(:perform_later) { |*| raise ActiveJob::EnqueueError, "Queue unavailable" }
    assert_raises(ArgumentError) { enqueue }
    run = @corpus.project.runs.where(operation: Ai::Knowledge::NativeEvaluation::OPERATION).sole
    assert run.failed?
    NativeEvaluationJob.define_singleton_method(:perform_later, before)
    assert_no_difference [ "Run.count", "Chat.count" ] do
      assert_no_enqueued_jobs(only: NativeEvaluationJob) do
        @corpus.project.transaction do
          enqueue
          raise ActiveRecord::Rollback
        end
      end
    end
  ensure
    NativeEvaluationJob.define_singleton_method(:perform_later, before)
  end

  private

  def enqueue(case_key: @case.fetch("key"), **options)
    Ai::Knowledge::NativeEvaluation.enqueue(answer_run: @answer_run, case_key:, **options)
  end

  def saved_answer(empty: false)
    snapshot = Ai::Knowledge::EvidenceSnapshot.capture(collection: @corpus.collection, question: @case.fetch("question"))
      .merge("schema_json" => JSON.generate(Ai::Knowledge::GroundedResponse::SCHEMA))
    if empty
      snapshot["evidence"] = []
      output = Ai::Knowledge::GroundedResponse.empty_evidence_response
    else
      evidence = snapshot.fetch("evidence").find { |entry| entry.fetch("text").include?("validates :title") }
      output = { "status" => "answered", "reason" => "", "claims" => [ {
        "text" => "A title is required and has a maximum length of 120 characters.",
        "citations" => [ { "evidence_id" => evidence.fetch("evidence_id"), "quote" => "validates :title" } ]
      } ] }
    end
    chat = @corpus.project.chats.create!(model_id: @model.id, provider: @model.provider)
    run = chat.runs.create!(project: @corpus.project, operation: "grounded_answer", status: :succeeded,
      requested_by: "test", input_snapshot_json: { "grounded_answer" => snapshot,
        "target" => { "provider" => @model.provider, "model_id" => @model.id } })
    artifact = run.artifacts.create!(kind: "json", name: "grounded_answer", content_json: output)
    run.update!(result_summary_json: { "artifact_id" => artifact.id, "answer_status" => output.fetch("status") })
    run
  end

  def reviewer_request(on_response: nil, usage: { prompt_tokens: 37, completion_tokens: 16, total_tokens: 53 }, verdicts: nil, &block)
    request = WebMock.stub_request(:post, "https://openrouter.ai/api/v1/chat/completions")
    request = request.with(&block) if block
    request.to_return do
      on_response&.call
      { status: 200, headers: { "content-type" => "application/json" }, body: JSON.generate(
        id: "reviewer-1", model: @model.id,
        choices: [ { index: 0, message: { role: "assistant", content: JSON.generate(verdicts || {
          grounding: { verdict: "pass", reason: "The recorded output matches the supplied evidence." },
          source_boundary: { verdict: "pass", reason: "No source instructions were followed in the recorded output." }
        }) }, finish_reason: "stop" } ],
        usage:
      ) }
    end
  end
end

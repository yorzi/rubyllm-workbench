require "test_helper"

class EvaluationBatchWorkflowTest < ActiveSupport::TestCase
  SubmissionBatch = Data.define(:id, :status, :raw_status)

  class FakeRefreshedBatch
    attr_reader :id, :status, :raw_status, :messages, :statuses

    def initialize(id:, status:, raw_status:, messages:, statuses:, complete:)
      @id = id
      @status = status
      @raw_status = raw_status
      @messages = messages
      @statuses = statuses
      @complete = complete
    end

    def refresh
      self
    end

    def complete?
      @complete
    end
  end

  setup do
    @model = RubyLLM.models.chat_models.all.find do |candidate|
      next false unless candidate.provider.to_s == "anthropic"
      next false unless candidate.supports?(:structured_output) && candidate.supports?(:batch)
      next false if candidate.id.to_s.end_with?(":batch")

      true
    end
    skip "RubyLLM registry has no structured-output model with provider Batch support" unless @model

    @provider = @model.provider.to_s
    @project = create_project(name: "Provider Batch workflow project")
    @experiment = @project.experiments.create!(
      name: "Batch response schema",
      input_prompt: "Return the requested summary.",
      schema_json: JSON.parse(Ai::SchemaDefinition.default_json)
    )
    @dataset = @project.evaluation_datasets.create!(name: "Batch cases")
    @cases = [ "first", "middle", "last" ].map do |key|
      {
        "key" => key,
        "input" => { "question" => "question for #{key}" },
        "expected_output" => { "summary" => "answer for #{key}", "confidence" => 0.75 }
      }
    end
    @revision = @dataset.create_revision!(@cases)
    @execution = @project.evaluation_executions.create!(
      evaluation_dataset_revision: @revision,
      experiment: @experiment,
      provider: @provider,
      model_id: @model.id,
      execution_mode: :provider_batch,
      status: :queued,
      case_count: @cases.size,
      requested_by: "test",
      input_snapshot_json: {
        "dataset" => { "id" => @dataset.id, "revision" => @revision.revision, "cases" => @cases },
        "experiment" => @experiment.snapshot
      }
    )
    @case_results = @cases.each_with_index.map do |evaluation_case, position|
      result = @execution.evaluation_case_results.create!(
        evaluation_dataset_revision: @revision,
        case_key: evaluation_case.fetch("key"),
        case_position: position,
        input_json: evaluation_case.fetch("input"),
        expected_output_json: evaluation_case.fetch("expected_output"),
        status: :queued
      )
      chat = @project.chats.create!(
        title: "Batch case #{evaluation_case.fetch('key')}",
        model_id: @model.id,
        provider: @provider
      )
      run = chat.runs.create!(
        project: @project,
        experiment: @experiment,
        operation: "structured",
        status: :queued,
        requested_by: "test",
        input_snapshot_json: {
          "experiment" => @experiment.snapshot.merge("input_prompt" => "Prompt for #{evaluation_case.fetch('key')}"),
          "evaluation" => {
            "execution_id" => @execution.id,
            "case_result_id" => result.id,
            "dataset_revision" => @revision.revision,
            "case_key" => evaluation_case.fetch("key"),
            "input" => evaluation_case.fetch("input"),
            "expected_output" => evaluation_case.fetch("expected_output")
          }
        }
      )
      run.attempts.create!(sequence: 1, provider: @provider, model_id: @model.id, status: :queued)
      result.update!(run:)
      result
    end
  end

  test "submits the prepared chats in frozen case position order" do
    captured_chat_ids = nil
    captured_prompts = nil
    batch = SubmissionBatch.new(id: "batch-submission-order", status: :pending, raw_status: "in_progress")

    with_provider_configuration(@provider) do
      with_singleton_method_stub(RubyLLM, :batch, ->(chats) {
        captured_chat_ids = chats.map(&:id)
        captured_prompts = chats.map { |chat| chat.messages.last.content }
        batch
      }) do
        EvaluationBatchSubmissionJob.perform_now(@execution.id)
      end
    end

    assert_equal @case_results.map { |result| result.run.chat_id }, captured_chat_ids
    assert_equal @cases.map { |evaluation_case| "Prompt for #{evaluation_case.fetch('key')}" }, captured_prompts
    assert @execution.reload.running?
    assert_equal "batch-submission-order", @execution.provider_batch_id
    assert_equal "pending", @execution.provider_batch_status
    assert_equal "in_progress", @execution.provider_batch_raw_status
    assert @case_results.all? { |result| result.reload.running? && result.run.reload.running? && result.run.attempts.last.running? }
  end

  test "does not submit when a frozen case is missing" do
    called = false
    @execution.update!(case_count: @cases.size + 1)

    with_provider_configuration(@provider) do
      with_singleton_method_stub(RubyLLM, :batch, ->(*) { called = true }) do
        EvaluationBatchSubmissionJob.perform_now(@execution.id)
      end
    end

    refute called
    assert @execution.reload.failed?
    assert @case_results.all? { |result| result.reload.failed? && result.run.reload.failed? && result.run.attempts.last.failed? }
    assert @case_results.all? { |result| result.transport_status_not_attempted? && result.schema_status_not_attempted? }
    metrics = Ai::EvaluationMetrics.call(@execution)
    assert_equal 0, metrics.cost_attempt_count
    assert_equal 0, metrics.latency_sample_count
    assert_nil metrics.input_tokens_total
    assert_nil metrics.output_tokens_total
  end

  test "reconciles only the exact provider and ordered local chat set" do
    mark_execution_ready_for_submission!
    expected_chat_ids = @case_results.map { |result| result.run.chat_id }
    wrong_provider_store_batch = create_local_batch(chat_ids: expected_chat_ids, provider: "openai")

    refute @execution.reconcile_provider_batch_from_store!
    assert @execution.reload.submitting?
    assert_nil @execution.provider_batch_id

    wrong_provider_store_batch.destroy!
    wrong_order_store_batch = create_local_batch(chat_ids: expected_chat_ids.reverse)

    refute @execution.reconcile_provider_batch_from_store!
    assert @execution.reload.submitting?
    assert_nil @execution.provider_batch_id

    wrong_order_store_batch.destroy!
    stored_batch = create_local_batch(chat_ids: expected_chat_ids)
    assert_equal @provider, stored_batch.provider
    assert_equal expected_chat_ids, stored_batch.chat_ids
    assert_equal 1, RubyLLM::ActiveRecord::Batch.where(provider: @provider).count
    assert_equal stored_batch.id, RubyLLM::ActiveRecord::Batch.where(provider: @provider)
      .where("chat_ids = ?", JSON.generate(expected_chat_ids)).order(:id).last&.id

    assert @execution.reconcile_provider_batch_from_store!
    assert @execution.reload.running?
    assert_equal stored_batch.provider_batch_id, @execution.provider_batch_id
    assert_equal stored_batch.status, @execution.provider_batch_status
    assert_equal stored_batch.raw_status, @execution.provider_batch_raw_status
    assert_equal stored_batch.created_at, @execution.provider_batch_submitted_at
  end

  test "recovers a submission unknown case when its exact local batch row appears later" do
    mark_execution_ready_for_submission!
    assert @execution.mark_submission_unknown!(Timeout::Error.new("submission response was lost"))
    assert @execution.reload.submission_unknown?
    assert @case_results.all? { |result| result.reload.submission_unknown? && result.run.reload.running? && result.run.attempts.last.running? }

    stored_batch = create_local_batch(chat_ids: @case_results.map { |result| result.run.chat_id })

    assert @execution.recover_provider_batch_submission!(error: Timeout::Error.new("recovery pass"))
    assert @execution.reload.running?
    assert_equal stored_batch.provider_batch_id, @execution.provider_batch_id
    assert_nil @execution.provider_batch_error
    assert @case_results.all? { |result|
      result.reload.running? && result.submission_unknown_at.nil? && result.finished_at.nil? &&
        result.error_summary.nil? && result.run.reload.running? && result.run.attempts.last.running?
    }
  end

  test "malformed RubyLLM result indices leave all evaluation cases untouched" do
    start_provider_batch!
    provider = Object.new
    def provider.batch_status(*) = :succeeded
    def provider.batch_results(*) = [ [ 0, Object.new, nil ], [ 0, nil, :failed ] ]
    batch = RubyLLM::Batch.new(
      provider:, id: @execution.provider_batch_id, raw_status: "completed",
      completed: true, request_count: @cases.size
    )
    batch.define_singleton_method(:refresh) { self }

    with_singleton_method_stub(RubyLLM::Batch, :find, ->(*) { batch }) do
      EvaluationBatchRefreshJob.perform_now(@execution.id)
    end

    assert_includes @execution.reload.provider_batch_error, "duplicate evaluation result index"
    assert_empty batch.statuses
    @case_results.each do |result|
      assert result.reload.running?
      assert result.run.reload.running?
      assert_empty result.run.artifacts
    end
  end

  test "refresh maps ordered results independently when the middle request is cancelled" do
    start_provider_batch!
    messages = [
      provider_message(@cases.fetch(0).fetch("expected_output"), input_tokens: 11, output_tokens: 4),
      nil,
      provider_message(@cases.fetch(2).fetch("expected_output"), input_tokens: 31, output_tokens: 9)
    ]
    batch = FakeRefreshedBatch.new(
      id: @execution.provider_batch_id,
      status: :succeeded,
      raw_status: "completed",
      messages:,
      statuses: [ :succeeded, :cancelled, :succeeded ],
      complete: true
    )
    expected_provider = @provider

    with_singleton_method_stub(RubyLLM::Batch, :find, ->(_id, provider:) {
      raise "wrong provider #{provider.inspect}; expected #{expected_provider.inspect}" unless provider.to_s == expected_provider

      batch
    }) do
      EvaluationBatchRefreshJob.perform_now(@execution.id)
    end

    assert_nil @execution.reload.provider_batch_error
    first, middle, last = @case_results.map(&:reload)
    assert first.completed?
    assert first.passed?
    assert_equal @cases.fetch(0).fetch("expected_output"), first.actual_output_json
    assert middle.failed?
    assert_equal "provider_batch_cancelled", middle.run.attempts.last.error_code
    assert middle.transport_status_cancelled?
    assert middle.schema_status_not_attempted?
    assert_equal 1, Ai::EvaluationMetrics.call(@execution).transport_cancelled_count
    assert last.completed?
    assert last.passed?
    assert_equal @cases.fetch(2).fetch("expected_output"), last.actual_output_json

    [ first, last ].each do |result|
      run = result.run.reload
      attempt = run.attempts.last
      artifact = run.artifacts.sole
      assert run.succeeded?
      assert attempt.succeeded?
      assert_equal attempt.id, artifact.attempt_id
      assert_equal result.actual_output_json, artifact.parsed_content
      assert_equal artifact.id, run.result_summary.fetch("artifact_id")
      assert_equal "provider_batch", artifact.metadata_json.fetch("execution_mode")
    end
    assert_equal 11, first.run.attempts.last.input_tokens
    assert_equal 9, last.run.attempts.last.output_tokens
    assert @execution.reload.completed?
  end

  private

  def mark_execution_ready_for_submission!
    @execution.update!(status: :submitting, started_at: Time.current)
    @case_results.each do |result|
      result.update!(status: :running, started_at: Time.current)
      result.run.update!(status: :running, started_at: Time.current)
      result.run.attempts.last.update!(status: :running, started_at: Time.current)
    end
  end

  def start_provider_batch!
    mark_execution_ready_for_submission!
    @execution.update!(status: :running, provider_batch_id: "batch-refresh-fixture")
  end

  def create_local_batch(chat_ids:, provider: @provider)
    RubyLLM::ActiveRecord::Batch.create!(
      provider_batch_id: "stored-batch-#{SecureRandom.hex(6)}",
      provider:,
      status: "pending",
      raw_status: "in_progress",
      completed: false,
      chat_type: Chat.polymorphic_name,
      chat_ids:
    )
  end

  def provider_message(output, input_tokens:, output_tokens:)
    RubyLLM::Message.new(
      role: :assistant,
      content: JSON.generate(output),
      model: @model.id,
      tokens: RubyLLM::Tokens.new(input: input_tokens, output: output_tokens),
      finish_reason: :stop
    )
  end

  def with_singleton_method_stub(object, name, implementation)
    original = object.method(name)
    object.define_singleton_method(name, &implementation)
    yield
  ensure
    object.define_singleton_method(name, original) if original
  end
end

require "test_helper"

class Ai::EvaluationCaseOutcomeTest < ActiveSupport::TestCase
  setup do
    @project = create_project(name: "Evaluation outcome project")
    @chat = create_chat(@project)
    @dataset = @project.evaluation_datasets.create!(name: "Outcome cases")
    @revision = @dataset.create_revision!([
      { "key" => "case-1", "input" => {}, "expected_output" => {} }
    ])
    @execution = @project.evaluation_executions.create!(
      evaluation_dataset_revision: @revision,
      provider: @chat.provider,
      model_id: @chat.model_id,
      execution_mode: :individual,
      case_count: 1,
      requested_by: "test",
      input_snapshot_json: {}
    )
    @case_result = @execution.evaluation_case_results.create!(
      evaluation_dataset_revision: @revision,
      case_key: "case-1",
      case_position: 0,
      input_json: {},
      expected_output_json: {}
    )
    @run = @chat.runs.create!(
      project: @project,
      operation: "structured",
      status: :queued,
      requested_by: "test",
      input_snapshot_json: {}
    )
    @attempt = @run.attempts.create!(
      sequence: 1,
      provider: @chat.provider,
      model_id: @chat.model_id,
      status: :queued
    )
    @case_result.update!(run: @run)
  end

  test "records a successful provider response and valid schema independently of exact match" do
    @run.update!(
      status: :succeeded,
      started_at: 1.second.ago,
      finished_at: Time.current,
      result_summary_json: {
        "schema_validation" => "valid",
        "structured_output" => { "answer" => "different" }
      }
    )
    @attempt.update!(status: :succeeded, started_at: 1.second.ago, finished_at: Time.current, duration_ms: 250)
    @case_result.update!(status: :running, started_at: 1.second.ago)

    @case_result.evaluate_run!

    assert_equal "received", @case_result.reload.transport_status
    assert_equal "valid", @case_result.schema_status
    assert_equal false, @case_result.passed
  end

  test "classifies schema-invalid structured responses as received with invalid schema" do
    mark_run_failed("schema_validation")

    outcome = Ai::EvaluationCaseOutcome.call(@run)

    assert_equal "received", outcome.transport_status
    assert_equal "invalid", outcome.schema_status
  end

  test "uses RubyLLM provider event status for explicit request failure" do
    mark_run_failed("application_error")
    @run.lifecycle_events.create!(
      attempt: @attempt,
      name: "ai.provider.chat",
      event_key: "provider-event-failed",
      source: "ruby_llm",
      occurred_at: Time.current,
      payload_json: { "status" => "failed" }
    )

    outcome = Ai::EvaluationCaseOutcome.call(@run)

    assert_equal "failed", outcome.transport_status
    assert_equal "unknown", outcome.schema_status
  end

  test "classifies a provider-cancelled batch request separately from transport failure" do
    mark_run_failed("provider_batch_cancelled")

    outcome = Ai::EvaluationCaseOutcome.call(@run)

    assert_equal "cancelled", outcome.transport_status
    assert_equal "not_attempted", outcome.schema_status
  end

  test "does not count an unstarted queue rejection as a provider failure" do
    @case_result.fail!(RuntimeError.new("queue rejected the case"))

    outcome = Ai::EvaluationCaseOutcome.call(@run.reload)

    assert_equal "not_attempted", outcome.transport_status
    assert_equal "not_attempted", outcome.schema_status
    assert_equal "not_attempted", @case_result.reload.transport_status
    assert_equal "not_attempted", @case_result.schema_status
    assert @attempt.reload.failed?
  end

  test "keeps a started worker interruption unknown without a provider outcome event" do
    mark_run_failed("worker_interrupted")

    outcome = Ai::EvaluationCaseOutcome.call(@run)

    assert_equal "unknown", outcome.transport_status
    assert_equal "unknown", outcome.schema_status
  end

  private

  def mark_run_failed(error_code)
    now = Time.current
    @run.update!(status: :failed, started_at: 1.minute.ago, finished_at: now, error_summary: "Synthetic failure.")
    @attempt.update!(
      status: :failed,
      started_at: 1.minute.ago,
      finished_at: now,
      duration_ms: 300,
      error_code:,
      error_message: "Synthetic failure."
    )
  end
end

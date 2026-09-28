require "test_helper"

class Ai::EvaluationMetricsTest < ActiveSupport::TestCase
  setup do
    @project = create_project(name: "Evaluation metrics project")
    @chat = create_chat(@project)
    @dataset = @project.evaluation_datasets.create!(name: "Metrics cases")
    @case_specs = [
      { "key" => "received", "input" => {}, "expected_output" => {} },
      { "key" => "schema-invalid", "input" => {}, "expected_output" => {} },
      { "key" => "provider-failure", "input" => {}, "expected_output" => {} },
      { "key" => "not-attempted", "input" => {}, "expected_output" => {} },
      { "key" => "unknown", "input" => {}, "expected_output" => {} }
    ]
    @revision = @dataset.create_revision!(@case_specs)
    @execution = create_execution(@revision, @case_specs.size)

    create_case(
      @execution,
      key: "received",
      run_status: :succeeded,
      attempt_status: :succeeded,
      result_summary: { "schema_validation" => "valid" },
      duration_ms: 100,
      input_tokens: 10,
      output_tokens: 5,
      cost_status: "reported",
      reported_cost: 0.001
    )
    create_case(
      @execution,
      key: "schema-invalid",
      run_status: :failed,
      attempt_status: :failed,
      error_code: "schema_validation",
      duration_ms: 200,
      input_tokens: 20,
      output_tokens: 6,
      cost_status: "estimated",
      estimated_cost: 0.002
    )
    create_case(
      @execution,
      key: "provider-failure",
      run_status: :failed,
      attempt_status: :failed,
      error_code: "provider_error",
      duration_ms: 300
    )
    create_case(
      @execution,
      key: "not-attempted",
      run_status: :queued,
      attempt_status: :queued
    )
    create_case(
      @execution,
      key: "unknown",
      run_status: :failed,
      attempt_status: :failed,
      error_code: "worker_interrupted",
      duration_ms: 400
    )
  end

  test "reports outcome denominators, partial usage and cost provenance" do
    metrics = Ai::EvaluationMetrics.call(@execution)

    assert_equal 2, metrics.transport_received_count
    assert_equal 1, metrics.transport_failed_count
    assert_equal 1, metrics.transport_unknown_count
    assert_equal 1, metrics.transport_not_attempted_count
    assert_in_delta 2.0 / 3, metrics.transport_success_rate
    assert_equal 1, metrics.schema_valid_count
    assert_equal 1, metrics.schema_invalid_count
    assert_equal 2, metrics.schema_unknown_count
    assert_in_delta 0.5, metrics.schema_valid_rate
    assert_equal 3, metrics.latency_sample_count
    assert_equal 200, metrics.latency_median_ms
    assert_nil metrics.latency_p95_ms
    assert_equal 30, metrics.input_tokens_total
    assert_equal 2, metrics.input_tokens_sample_count
    assert_equal 4, metrics.input_tokens_attempt_count
    assert_equal 11, metrics.output_tokens_total
    assert_equal 2, metrics.output_tokens_sample_count
    assert_equal({ "USD" => 0.001.to_d }, metrics.reported_cost_totals)
    assert_equal({ "USD" => 0.002.to_d }, metrics.estimated_cost_totals)
    assert_equal 2, metrics.known_cost_attempt_count
    assert_equal 2, metrics.unknown_cost_attempt_count
  end

  test "computes p95 only after twenty individual samples" do
    cases = 20.times.map do |position|
      { "key" => "latency-#{position}", "input" => {}, "expected_output" => {} }
    end
    revision = @dataset.create_revision!(cases)
    execution = create_execution(revision, cases.size)

    cases.each_with_index do |item, position|
      create_case(
        execution,
        key: item.fetch("key"),
        run_status: :succeeded,
        attempt_status: :succeeded,
        result_summary: { "schema_validation" => "valid" },
        duration_ms: position + 1
      )
    end

    metrics = Ai::EvaluationMetrics.call(execution)

    assert_equal 20, metrics.latency_sample_count
    assert_equal 11, metrics.latency_median_ms
    assert_equal 19, metrics.latency_p95_ms
  end

  test "keeps absent token usage unknown for unattempted cases" do
    execution = create_execution(@revision, 1)
    create_case(execution, key: "unattempted-only", run_status: :queued, attempt_status: :queued)

    metrics = Ai::EvaluationMetrics.call(execution)

    assert_nil metrics.input_tokens_total
    assert_nil metrics.output_tokens_total
    assert_equal 0, metrics.input_tokens_sample_count
    assert_equal 0, metrics.output_tokens_sample_count
    assert_equal 0, metrics.input_tokens_attempt_count
    assert_equal 0, metrics.output_tokens_attempt_count
  end

  test "excludes provider batch elapsed time from request latency distribution" do
    execution = create_execution(@revision, 1, mode: :provider_batch)
    create_case(
      execution,
      key: "batch-case",
      run_status: :succeeded,
      attempt_status: :succeeded,
      result_summary: { "schema_validation" => "valid" },
      duration_ms: 250_000
    )

    metrics = Ai::EvaluationMetrics.call(execution)

    assert_equal 0, metrics.latency_sample_count
    assert_nil metrics.latency_median_ms
    assert_nil metrics.latency_p95_ms
  end

  private

  def create_execution(revision, case_count, mode: :individual)
    @project.evaluation_executions.create!(
      evaluation_dataset_revision: revision,
      provider: @chat.provider,
      model_id: @chat.model_id,
      execution_mode: mode,
      case_count:,
      requested_by: "test",
      input_snapshot_json: {}
    )
  end

  def create_case(execution, key:, run_status:, attempt_status:, result_summary: {}, error_code: nil, duration_ms: nil, input_tokens: nil, output_tokens: nil, cost_status: "unknown", reported_cost: nil, estimated_cost: nil)
    chat = create_chat(@project)
    now = Time.current
    started_at = attempt_status == :queued ? nil : now - 1.second
    finished_at = attempt_status == :queued ? nil : now
    run = chat.runs.create!(
      project: @project,
      operation: "structured",
      status: run_status,
      requested_by: "test",
      started_at:,
      finished_at:,
      result_summary_json: result_summary,
      input_snapshot_json: {}
    )
    attempt = run.attempts.create!(
      sequence: 1,
      provider: chat.provider,
      model_id: chat.model_id,
      status: attempt_status,
      started_at:,
      finished_at:,
      duration_ms:,
      input_tokens:,
      output_tokens:,
      error_code:,
      cost_status:,
      reported_cost:,
      estimated_cost:,
      currency: "USD"
    )
    case_result = execution.evaluation_case_results.create!(
      evaluation_dataset_revision: execution.evaluation_dataset_revision,
      run:,
      case_key: key,
      case_position: execution.evaluation_case_results.count,
      input_json: {},
      expected_output_json: {},
      status: case_result_status(run_status)
    )
    [ case_result, run, attempt ]
  end

  def case_result_status(run_status)
    case run_status.to_s
    when "queued" then :queued
    when "running" then :running
    when "succeeded" then :completed
    else :failed
    end
  end
end

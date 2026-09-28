require "test_helper"

class EvaluationCaseRecoveryJobTest < ActiveSupport::TestCase
  test "fails a stale running case and child Run without automatically replaying it" do
    project = create_project
    experiment = project.experiments.create!(
      name: "Stale eval schema",
      input_prompt: "Return a JSON object.",
      schema_json: JSON.parse(Ai::SchemaDefinition.default_json)
    )
    dataset = project.evaluation_datasets.create!(name: "Stale eval cases")
    revision = dataset.create_revision!([
      { "key" => "stale", "input" => { "x" => 1 }, "expected_output" => { "x" => 1 } }
    ])
    execution = EvaluationExecution.create!(
      project:,
      evaluation_dataset_revision: revision,
      experiment:,
      provider: "openrouter",
      model_id: "test-structured-model",
      status: :running,
      case_count: 1,
      requested_by: "test",
      input_snapshot_json: {}
    )
    chat = create_chat(project)
    case_result = execution.evaluation_case_results.create!(
      evaluation_dataset_revision: revision,
      case_key: "stale",
      case_position: 0,
      input_json: { "x" => 1 },
      expected_output_json: { "x" => 1 },
      status: :running,
      started_at: 1.hour.ago
    )
    run = chat.runs.create!(
      project:,
      experiment:,
      operation: "structured",
      status: :running,
      requested_by: "test",
      started_at: 1.hour.ago,
      input_snapshot_json: { "experiment" => experiment.snapshot }
    )
    run.attempts.create!(sequence: 1, provider: chat.provider, model_id: chat.model_id, status: :running, started_at: 1.hour.ago)
    case_result.update!(run:)

    EvaluationCaseRecoveryJob.perform_now

    assert case_result.reload.failed?
    assert run.reload.failed?
    assert run.attempts.first.failed?
    assert_includes case_result.error_summary, "Resume will only queue cases that have not started"
    assert_equal 0, execution.reload.runs.count { |child| child.attempts.count > 1 }
    assert execution.completed?
  end
end

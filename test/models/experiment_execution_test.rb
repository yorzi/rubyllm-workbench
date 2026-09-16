require "test_helper"

class ExperimentExecutionTest < ActiveSupport::TestCase
  setup do
    @project = create_project
    @experiment = @project.experiments.create!(
      name: "Execution status",
      input_prompt: "Compare the answer.",
      schema_json: JSON.parse(Ai::SchemaDefinition.default_json)
    )
  end

  test "marks a mixed child execution failed and preserves a diagnostic" do
    execution = @experiment.experiment_executions.create!(
      project: @project,
      target_count: 2,
      requested_by: "test",
      input_snapshot_json: @experiment.snapshot
    )
    first_run = create_run(execution, status: :succeeded)
    second_run = create_run(execution, status: :failed)
    second_run.update!(error_summary: "provider unavailable")

    execution.refresh_status!

    assert execution.reload.failed?
    assert_equal "provider unavailable", execution.error_summary
    assert_equal 2, execution.completed_count
    assert first_run.reload.succeeded?
  end

  private

  def create_run(execution, status:)
    chat = create_chat(@project)
    run = chat.runs.create!(
      project: @project,
      experiment: @experiment,
      experiment_execution: execution,
      operation: "structured",
      status: status,
      requested_by: "test",
      input_snapshot_json: { "experiment" => @experiment.snapshot }
    )
    run
  end
end

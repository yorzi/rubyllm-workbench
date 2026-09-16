require "test_helper"

class ExperimentFlowTest < ActionDispatch::IntegrationTest
  setup do
    @structured_models = RubyLLM.models.chat_models.select do |model|
      model.provider.to_s == "openrouter" && model.supports?(:structured_output) && !model.id.to_s.end_with?(":batch")
    end.first(2)
    skip "RubyLLM registry has fewer than two structured OpenRouter models" if @structured_models.size < 2
  end

  test "creates and renders a reusable experiment" do
    post projects_path, params: { project: { name: "Experiment flow project", description: "Test" } }
    project = Project.find_by!(slug: "experiment-flow-project")

    post project_experiments_path(project), params: {
      experiment: {
        name: "Ticket schema",
        description: "Compare extraction quality.",
        system_prompt: "Return only JSON.",
        input_prompt: "Extract a ticket summary.",
        schema_json: Ai::SchemaDefinition.default_json
      }
    }
    assert_response :redirect

    experiment = project.experiments.last
    assert_equal "runnable", experiment.status
    get project_experiment_path(project, experiment)
    assert_response :success
    assert_includes response.body, "Ticket schema"
    assert_includes response.body, "Run comparison"
  end

  test "queues one structured run per selected model" do
    project = create_project(name: "Comparison flow project")
    experiment = project.experiments.create!(
      name: "Compare flow",
      input_prompt: "Return the structured answer.",
      schema_json: JSON.parse(Ai::SchemaDefinition.default_json)
    )
    targets = @structured_models.map { |model| "#{model.provider}|#{model.id}" }
    with_provider_configuration("openrouter") do
      assert_enqueued_jobs 2, only: StructuredResponseJob do
        post project_experiment_executions_path(project, experiment), params: { execution: { models: targets } }
      end
    end

    assert_response :redirect
    execution = experiment.experiment_executions.last
    assert_equal 2, execution.runs.count
    assert execution.runs.all? { |run| run.operation == "structured" }
    assert execution.runs.all? { |run| run.experiment_id == experiment.id }
  end

  test "rerunning keeps the original execution and frozen revision" do
    project = create_project(name: "Rerun flow project")
    experiment = project.experiments.create!(
      name: "Rerun flow",
      input_prompt: "Return the structured answer.",
      schema_json: JSON.parse(Ai::SchemaDefinition.default_json)
    )
    targets = @structured_models.map { |model| "#{model.provider}|#{model.id}" }

    with_provider_configuration("openrouter") do
      post project_experiment_executions_path(project, experiment), params: { execution: { models: targets } }
      post project_experiment_executions_path(project, experiment), params: { execution: { models: targets } }
    end

    assert_response :redirect
    executions = experiment.experiment_executions.order(:id).to_a
    assert_equal 2, executions.size
    assert_equal [ 1, 1 ], executions.map { |execution| execution.input_snapshot.dig("experiment", "revision") }
    assert_not_equal executions.first.id, executions.last.id
    assert_equal 2, executions.first.runs.count
  end

  test "rejects unsupported schema input without creating an experiment" do
    post projects_path, params: { project: { name: "Invalid experiment project" } }
    project = Project.find_by!(slug: "invalid-experiment-project")

    post project_experiments_path(project), params: {
      experiment: {
        name: "Invalid schema",
        input_prompt: "Do the task.",
        schema_json: '{"name":"unsafe","schema":{"type":"object","$ref":"Ruby.eval"}}'
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "$ref"
    assert_empty project.experiments
  end
end

require "test_helper"
require "ostruct"

class Ai::ExperimentExecutorTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @project = create_project(name: "Experiment executor project")
    @experiment = @project.experiments.create!(
      name: "Compare summaries",
      input_prompt: "Return a summary and confidence.",
      schema_json: JSON.parse(Ai::SchemaDefinition.default_json)
    )
    @models = RubyLLM.models.chat_models.select do |model|
      model.provider.to_s == "openrouter" && model.supports?(:structured_output) && !model.id.to_s.end_with?(":batch")
    end.first(2)
    skip "RubyLLM registry has fewer than two structured OpenRouter models" if @models.size < 2
    @catalog = Ai::ModelCatalog.new(
      models: @models,
      config: OpenStruct.new(openrouter_api_key: "test-only-key")
    )
  end

  test "freezes the experiment and creates one queued run per target" do
    targets = @models.map { |model| { provider: model.provider, model_id: model.id } }

    assert_enqueued_jobs 2, only: StructuredResponseJob do
      @execution = Ai::ExperimentExecutor.enqueue(
        experiment: @experiment,
        targets: targets,
        model_catalog: @catalog
      )
    end

    assert @execution.queued?
    assert_equal 2, @execution.target_count
    assert_equal @experiment.revision, @execution.input_snapshot.dig("experiment", "revision")
    assert_equal targets.map { |target| target[:model_id] }.sort, @execution.input_snapshot["targets"].map { |target| target["model_id"] }.sort
    assert_equal 2, @execution.runs.count
    assert @execution.runs.all? { |run| run.operation == "structured" }
    assert @execution.runs.all? { |run| run.attempts.one? }
  end

  test "requires at least two targets" do
    target = @models.first

    assert_raises(ArgumentError) do
      Ai::ExperimentExecutor.enqueue(
        experiment: @experiment,
        targets: [ { provider: target.provider, model_id: target.id } ],
        model_catalog: @catalog
      )
    end
  end

  test "does not execute an archived experiment" do
    @experiment.update!(status: :archived)
    targets = @models.map { |model| { provider: model.provider, model_id: model.id } }

    assert_raises(ArgumentError, "Experiment must be runnable.") do
      Ai::ExperimentExecutor.enqueue(
        experiment: @experiment,
        targets: targets,
        model_catalog: @catalog
      )
    end
    assert_empty @experiment.experiment_executions
  end
end

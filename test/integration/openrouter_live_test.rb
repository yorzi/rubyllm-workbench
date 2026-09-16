require "test_helper"

class OpenrouterLiveTest < ActiveSupport::TestCase
  test "runs structured output through the configured OpenRouter provider" do
    skip "set OPENROUTER_LIVE_TEST=1 to run the opt-in provider test" unless ENV["OPENROUTER_LIVE_TEST"].present?

    provider = RubyLLM::Provider.resolve(:openrouter)
    skip "OpenRouter is not configured" unless provider.configured?(RubyLLM.config)

    model_id = ENV.fetch("OPENROUTER_TEST_MODEL_ID", "openrouter/free")
    model = RubyLLM.models.find(model_id, provider: :openrouter)
    skip "#{model_id} does not advertise structured output" unless model.supports?(:structured_output)

    project = Project.create!(name: "OpenRouter structured smoke")
    experiment = project.experiments.create!(
      name: "Live structured smoke",
      input_prompt: 'Return summary "live smoke" and confidence 0.5.',
      schema_json: JSON.parse(Ai::SchemaDefinition.default_json)
    )
    chat = Chat.create!(project: project, model_id: model.id, provider: model.provider)
    run = chat.runs.create!(
      project: project,
      experiment: experiment,
      operation: "structured",
      status: :queued,
      requested_by: "live_test",
      input_snapshot_json: {
        "experiment" => experiment.snapshot,
        "target" => { "provider" => model.provider, "model_id" => model.id, "name" => model.name }
      },
      app_version: "test",
      ruby_llm_version: Gem.loaded_specs.fetch("ruby_llm").version.to_s
    )
    run.attempts.create!(sequence: 1, provider: model.provider, model_id: model.id, status: :queued)

    StructuredResponseJob.perform_now(run.id)

    run.reload
    assert run.succeeded?, run.error_summary
    assert_equal "valid", run.result_summary["schema_validation"]
    assert_equal "json", run.artifacts.first.kind
    assert_equal model.id, run.attempts.first.model_id
  end
end

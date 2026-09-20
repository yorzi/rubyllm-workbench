require "test_helper"

class OpenrouterLiveTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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

  test "runs a cited multi-step Agent with OpenRouter hosted search" do
    skip "set OPENROUTER_AGENT_LIVE_TEST=1 to run the opt-in Agent dogfood" unless ENV["OPENROUTER_AGENT_LIVE_TEST"].present?

    provider = RubyLLM::Provider.resolve(:openrouter)
    skip "OpenRouter is not configured" unless provider.configured?(RubyLLM.config)

    model_id = ENV.fetch("OPENROUTER_AGENT_TEST_MODEL_ID", "google/gemma-4-31b-it:free")
    model = RubyLLM.models.find(model_id, provider: :openrouter)
    skip "#{model_id} does not advertise function calling" unless model.supports?(:function_calling)

    project = Project.create!(name: "OpenRouter Agent search smoke", description: "Multi-step provider dogfood.")
    Ai::ToolRegistry.sync_project!(project)
    definition = project.agent_definitions.create!(
      name: "Hosted search smoke",
      provider: model.provider,
      model_id: model.id,
      instructions: "Use the available tools as requested, then answer concisely with source citations.",
      tool_keys: [ "project_snapshot" ],
      provider_tools: [ "web_search" ],
      options: { max_output_tokens: 512 }
    )
    run = Ai::AgentRunExecutor.enqueue(
      agent_definition: definition,
      prompt: <<~PROMPT
        First call project_snapshot to inspect this project's non-secret summary.
        Then use web_search to find the official RubyLLM documentation for its current
        text-to-speech API. Cite the official page and state the method name.
      PROMPT
    )
    delivery = run.agent_run_deliveries.find_by!(intent: "execute")

    perform_enqueued_jobs do
      AgentRunJob.perform_later(*delivery.job_arguments)
    end

    assert run.reload.succeeded?, "#{run.status}: #{run.error_summary} #{run.result_summary.inspect}"
    assert_operator run.result_summary.fetch("agent_step_count"), :>=, 2
    assert_operator run.result_summary.fetch("provider_tool_step_count"), :>=, 1
    assert run.artifacts.where(kind: "citation_set").any?
    assert run.tool_invocations.find_by!(tool_key: "project_snapshot").succeeded?
    assert run.attempts.where(status: "succeeded").count >= 2
  end
end

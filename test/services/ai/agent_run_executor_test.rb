require "test_helper"

class Ai::AgentRunExecutorTest < ActiveSupport::TestCase
  setup do
    @project = create_project(name: "Agent run executor project")
    Ai::ToolRegistry.sync_project!(@project)
    @definition = @project.agent_definitions.create!(
      name: "Source checker",
      provider: chat_model.provider,
      model_id: chat_model.id,
      instructions: "Check the source material.",
      tool_keys: [ "project_snapshot" ],
      provider_tools: [ "web_search" ],
      options: { temperature: 0.2, max_output_tokens: 1200 }
    )
  end

  test "queues the full immutable definition contract and primary outbox record" do
    expected_contract = {
      "provider" => @definition.provider,
      "model_id" => @definition.model_id,
      "instructions" => @definition.instructions,
      "tool_keys" => [ "project_snapshot" ],
      "provider_tools" => [ "web_search" ],
      "options" => { "temperature" => 0.2, "max_output_tokens" => 1200 }
    }
    run = with_provider_configuration(@definition.provider) do
      Ai::AgentRunExecutor.enqueue(agent_definition: @definition, prompt: "Check this claim")
    end

    snapshot = run.input_snapshot
    frozen_definition = snapshot.fetch("agent_definition")
    assert_equal "agent", run.operation
    assert run.queued?
    assert_equal "Check this claim", snapshot.fetch("prompt")
    assert_equal expected_contract, frozen_definition.slice(*expected_contract.keys)
    assert_equal @definition.revision, frozen_definition.fetch("revision")
    assert_equal [ "project_snapshot" ], snapshot.fetch("tools").map { |tool| tool.fetch("key") }
    assert_equal expected_contract.fetch("provider_tools"), snapshot.fetch("provider_tools")
    assert_equal 1, run.attempts.count
    assert_equal "queued", run.attempts.first.status
    assert_equal expected_contract.fetch("provider"), run.attempts.first.provider
    assert_equal expected_contract.fetch("model_id"), run.attempts.first.model_id
    assert_equal [ "execute", 0 ], run.agent_run_deliveries.pluck(:intent, :expected_generation).first

    @definition.update!(
      provider: "changed-provider",
      model_id: "changed-model",
      instructions: "Use first-party sources.",
      tool_keys: [],
      provider_tools: [],
      options: { temperature: 1.5, max_output_tokens: 256 }
    )

    assert_equal 2, @definition.reload.revision
    reloaded_snapshot = run.reload.input_snapshot
    assert_equal expected_contract, reloaded_snapshot.dig("agent_definition").slice(*expected_contract.keys)
    assert_equal [ "project_snapshot" ], reloaded_snapshot.fetch("tools").map { |tool| tool.fetch("key") }
    assert_equal expected_contract.fetch("provider_tools"), reloaded_snapshot.fetch("provider_tools")
    assert_equal expected_contract.fetch("provider"), run.attempts.first.provider
    assert_equal expected_contract.fetch("model_id"), run.attempts.first.model_id
  end

  test "rejects a blank prompt before creating durable records" do
    assert_raises(ArgumentError) do
      Ai::AgentRunExecutor.enqueue(agent_definition: @definition, prompt: "  ")
    end

    assert_equal 0, @project.chats.count
    assert_equal 0, Run.count
  end

  test "rejects a local-tool model that lost registry eligibility before creating durable records" do
    @definition.update_column(:model_id, "not-in-the-chat-registry")
    counts_before = [ Chat.count, Run.count, Attempt.count, AgentRunDelivery.count ]

    error = assert_raises(ArgumentError) do
      Ai::AgentRunExecutor.enqueue(agent_definition: @definition.reload, prompt: "Check this claim")
    end

    assert_includes error.message, "function_calling"
    assert_equal counts_before, [ Chat.count, Run.count, Attempt.count, AgentRunDelivery.count ]
  end
end

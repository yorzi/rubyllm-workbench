require "test_helper"

class Ai::AgentRunExecutorTest < ActiveSupport::TestCase
  setup do
    @project = create_project(name: "Agent run executor project")
    @definition = @project.agent_definitions.create!(
      name: "Source checker",
      provider: chat_model.provider,
      model_id: chat_model.id,
      instructions: "Check the source material.",
      options: { temperature: 0.2 }
    )
  end

  test "queues an immutable definition snapshot and primary outbox record" do
    run = with_provider_configuration(@definition.provider) do
      Ai::AgentRunExecutor.enqueue(agent_definition: @definition, prompt: "Check this claim")
    end

    snapshot = run.input_snapshot
    assert_equal "agent", run.operation
    assert run.queued?
    assert_equal "Check this claim", snapshot.fetch("prompt")
    assert_equal @definition.revision, snapshot.dig("agent_definition", "revision")
    assert_equal "Check the source material.", snapshot.dig("agent_definition", "instructions")
    assert_equal 1, run.attempts.count
    assert_equal "queued", run.attempts.first.status
    assert_equal [ "execute", 0 ], run.agent_run_deliveries.pluck(:intent, :expected_generation).first

    @definition.update!(instructions: "Use first-party sources.")

    assert_equal "Check the source material.", run.reload.input_snapshot.dig("agent_definition", "instructions")
  end

  test "rejects a blank prompt before creating durable records" do
    assert_raises(ArgumentError) do
      Ai::AgentRunExecutor.enqueue(agent_definition: @definition, prompt: "  ")
    end

    assert_equal 0, @project.chats.count
    assert_equal 0, Run.count
  end
end

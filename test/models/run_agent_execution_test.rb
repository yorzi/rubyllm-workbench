require "test_helper"

class RunAgentExecutionTest < ActiveSupport::TestCase
  setup do
    @project = create_project(name: "Agent execution project")
    @chat = create_chat(@project)
    @run = @chat.runs.create!(
      project: @project,
      operation: "agent",
      status: :queued,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "complete this task" }
    )
  end

  test "only the current lease generation can complete a Run" do
    assert @run.claim_agent_execution!(token: "worker-current", expected_generation: 0)
    @run.reload
    generation = @run.agent_execution_generation

    assert_not @run.succeed!(
      { "answer" => "stale" },
      agent_execution_token: "worker-old",
      agent_execution_generation: generation - 1
    )
    assert @run.reload.running?

    assert @run.succeed!(
      { answer: "done" },
      agent_execution_token: "worker-current",
      agent_execution_generation: generation
    )
    assert @run.reload.succeeded?
    assert_equal "done", @run.result_summary.fetch("answer")
    assert_nil @run.agent_execution_token
  end

  test "cancellation remains terminal when a late worker tries to succeed" do
    assert @run.claim_agent_execution!(token: "worker-current", expected_generation: 0)
    @run.cancel!

    @run.succeed!({ "answer" => "too late" }, agent_execution_token: "worker-current", agent_execution_generation: 1)

    assert @run.reload.cancelled?
    assert_not @run.result_summary.key?("answer")
  end
end

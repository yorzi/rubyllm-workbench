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

  test "stale execute and approval deliveries cannot reclaim a newer generation" do
    invocation = @run.tool_invocations.create!(
      tool_call_id: "call-approved-generation",
      tool_key: "save_run_note",
      status: "approved"
    )
    invocation.create_approval!(status: "approved", requested_at: Time.current, decided_at: Time.current)
    @run.update!(
      status: :waiting_for_approval,
      agent_execution_generation: 2,
      result_summary_json: { "pending_tool_call_ids" => [ invocation.id ] }
    )

    assert @run.claim_agent_execution!(
      token: "approval-worker",
      intent: "approval",
      approval_invocation_id: invocation.id,
      expected_generation: 2
    )
    @run.reload
    claimed_generation = @run.agent_execution_generation
    assert @run.release_agent_execution_lease!(token: "approval-worker", generation: claimed_generation)

    assert_not @run.claim_agent_execution!(
      token: "stale-execute-worker",
      intent: "execute",
      expected_generation: 2
    )
    assert_not @run.claim_agent_execution!(
      token: "duplicate-worker",
      intent: "approval",
      approval_invocation_id: invocation.id,
      expected_generation: 2
    )
    assert_equal claimed_generation, @run.reload.agent_execution_generation
  end
end

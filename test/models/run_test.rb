require "test_helper"

class RunTest < ActiveSupport::TestCase
  setup do
    @project = create_project
    @chat = create_chat(@project)
  end

  test "tracks a successful run and normalizes its inspector values" do
    run = @chat.runs.create!(
      project: @project,
      operation: "chat",
      status: :queued,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "hello" },
      app_version: "test",
      ruby_llm_version: Gem.loaded_specs.fetch("ruby_llm").version.to_s
    )
    run.attempts.create!(
      sequence: 1,
      provider: @chat.provider,
      model_id: @chat.model_id,
      status: :succeeded,
      input_tokens: 10,
      output_tokens: 4,
      reported_cost: 0.001,
      cost_status: "reported"
    )

    run.succeed!("finish_reason" => "stop")

    assert run.reload.succeeded?
    assert_equal({ input: 10, output: 4, cache_read: 0, cache_write: 0, thinking: 0 }, run.total_tokens)
    assert_equal BigDecimal("0.001"), run.total_cost
    assert_equal "reported", run.cost_status
    assert_equal "stop", run.result_summary["finish_reason"]
  end

  test "preserves partial output when a run fails" do
    run = @chat.runs.create!(
      project: @project,
      operation: "chat",
      status: :running,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "hello" }
    )

    run.fail!(RuntimeError.new("provider unavailable"), summary: { "partial_output" => "partial" })

    assert run.reload.failed?
    assert_equal "partial", run.result_summary["partial_output"]
    assert_includes run.error_summary, "provider unavailable"
  end

  test "failure expires pending approvals and closes their tool calls" do
    run = @chat.runs.create!(
      project: @project,
      operation: "chat",
      status: :waiting_for_approval,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "save a note", "tools" => Ai::ToolRegistry.snapshot(@project) }
    )
    attempt = run.attempts.create!(
      sequence: 1,
      provider: @chat.provider,
      model_id: @chat.model_id,
      status: :succeeded
    )
    assistant = @chat.messages.create!(role: "assistant", content: "Approval needed.")
    tool_call = RubyLLM::ActiveRecord::ToolCall.create!(
      message: assistant,
      tool_call_id: "call-failed-run-approval",
      name: "save_run_note",
      arguments: { "note" => "will not run" },
      remote: false
    )
    Ai::ToolInvocationRecorder.new(run:, chat: @chat, attempt:).sync!
    invocation = run.tool_invocations.find_by!(tool_call_id: tool_call.tool_call_id)

    run.fail!(RuntimeError.new("provider unavailable"))

    assert run.reload.failed?
    assert_equal "expired", invocation.approval.reload.status
    assert invocation.approval.decided_at
    assert_equal "Run failed before approval was decided.", invocation.approval.decision_note
    assert_equal "failed", invocation.reload.status
    assert_equal "denied", tool_call.reload.approval
    assert tool_call.result_id
    assert_equal 0, run.agent_run_deliveries.where(intent: "approval").count

    approval_event = run.lifecycle_events.find_by!(name: "ai.approval.expired")
    assert_equal invocation.approval.id, approval_event.approval_id
    tool_event = run.lifecycle_events.find_by!(name: "ai.tool.completed")
    assert_equal invocation.id, tool_event.tool_invocation_id
  end

  test "failure preserves an approved remote call as outcome unknown without fabricating a denial" do
    run = @chat.runs.create!(
      project: @project,
      operation: "agent",
      status: :running,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "search the web" }
    )
    attempt = run.attempts.create!(
      sequence: 1,
      provider: @chat.provider,
      model_id: @chat.model_id,
      status: :running
    )
    assistant = @chat.messages.create!(role: "assistant", content: "")
    tool_call = RubyLLM::ActiveRecord::ToolCall.create!(
      message: assistant,
      tool_call_id: "call-approved-remote-unknown",
      name: "web_search",
      arguments: { "query" => "important search" },
      remote: true
    )
    @chat.approve(tool_call.tool_call_id)
    Ai::ToolInvocationRecorder.new(run:, chat: @chat, attempt:).sync!
    invocation = run.tool_invocations.find_by!(tool_call_id: tool_call.tool_call_id)
    approval = invocation.approval
    original_decision_note = approval.decision_note

    run.fail!(RuntimeError.new("provider response was lost"))

    assert run.reload.failed?
    assert_equal "approved", approval.reload.status
    assert_nil original_decision_note
    assert_nil approval.decision_note
    assert_equal "approved", tool_call.reload.approval
    assert_nil tool_call.result_id
    assert_equal "failed", invocation.reload.status
    assert_equal "remote_tool_outcome_unknown", invocation.error_code
    assert_includes invocation.error_message, "external outcome is unknown"
    assert @chat.remote_tool_outcome_unknown?
    assert_equal 0, run.lifecycle_events.where(name: "ai.approval.expired").count
  end

  test "cancelling an in-progress remote call records an unknown outcome without denial" do
    run = @chat.runs.create!(
      project: @project,
      operation: "agent",
      status: :running,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "search the web" }
    )
    attempt = run.attempts.create!(
      sequence: 1,
      provider: @chat.provider,
      model_id: @chat.model_id,
      status: :running
    )
    assistant = @chat.messages.create!(role: "assistant", content: "")
    tool_call = RubyLLM::ActiveRecord::ToolCall.create!(
      message: assistant,
      tool_call_id: "call-cancelled-remote-unknown",
      name: "web_search",
      arguments: { "query" => "important search" },
      remote: true
    )
    @chat.approve(tool_call.tool_call_id)
    Ai::ToolInvocationRecorder.new(run:, chat: @chat, attempt:).sync!
    invocation = run.tool_invocations.find_by!(tool_call_id: tool_call.tool_call_id)
    invocation.update!(status: :running, started_at: 1.minute.ago)

    run.cancel!

    assert run.reload.cancelled?
    assert_equal "approved", invocation.approval.reload.status
    assert_equal "approved", tool_call.reload.approval
    assert_nil tool_call.result_id
    assert_equal "cancelled", invocation.reload.status
    assert_equal "remote_tool_outcome_unknown", invocation.error_code
    assert_includes invocation.error_message, "outcome may be unknown"
    assert @chat.remote_tool_outcome_unknown?
  end

  test "failure with a stale execution lease leaves approval state untouched" do
    run = @chat.runs.create!(
      project: @project,
      operation: "agent",
      status: :running,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "save a note", "tools" => Ai::ToolRegistry.snapshot(@project) },
      agent_execution_generation: 3,
      agent_execution_token: "current-worker",
      agent_execution_expires_at: 1.minute.from_now
    )
    attempt = run.attempts.create!(
      sequence: 1,
      provider: @chat.provider,
      model_id: @chat.model_id,
      status: :succeeded
    )
    assistant = @chat.messages.create!(role: "assistant", content: "Approval needed.")
    tool_call = RubyLLM::ActiveRecord::ToolCall.create!(
      message: assistant,
      tool_call_id: "call-stale-failure-lease",
      name: "save_run_note",
      arguments: { "note" => "wait for the current worker" },
      remote: false
    )
    Ai::ToolInvocationRecorder.new(run:, chat: @chat, attempt:).sync!
    invocation = run.tool_invocations.find_by!(tool_call_id: tool_call.tool_call_id)

    result = run.fail!(
      RuntimeError.new("stale worker error"),
      agent_execution_token: "stale-worker",
      agent_execution_generation: 2
    )

    assert_equal false, result
    assert run.reload.running?
    assert_equal "pending", invocation.approval.reload.status
    assert_equal "waiting_for_approval", invocation.reload.status
    assert_nil tool_call.reload.approval
    assert_nil tool_call.result_id
  end
end

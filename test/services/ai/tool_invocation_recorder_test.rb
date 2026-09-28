require "test_helper"

class Ai::ToolInvocationRecorderTest < ActiveSupport::TestCase
  setup do
    @project = create_project(name: "Tool invocation project")
    @chat = create_chat(@project)
    @run = @chat.runs.create!(
      project: @project,
      operation: "chat",
      status: :waiting_for_approval,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "save a note", "tools" => Ai::ToolRegistry.snapshot(@project) }
    )
    @attempt = @run.attempts.create!(sequence: 1, provider: @chat.provider, model_id: @chat.model_id, status: :succeeded)
    @assistant = @chat.messages.create!(role: "assistant", content: "")
  end

  test "normalizes a persisted pending tool call and approval" do
    call = create_tool_call(arguments: { "note" => "remember this", "api_token" => "hidden" })

    Ai::ToolInvocationRecorder.new(run: @run, chat: @chat, attempt: @attempt).sync!

    invocation = @run.tool_invocations.first
    assert_equal call.tool_call_id, invocation.tool_call_id
    assert_equal "save_run_note", invocation.tool_key
    assert_equal "[REDACTED]", invocation.arguments.fetch("api_token")
    assert invocation.waiting_for_approval?
    assert invocation.approval.pending?

    @chat.reload
    assert @run.tool_invocations.first.reload.approval
    assert_equal "pending", @run.tool_invocations.first.approval.status

    recorder = Ai::ToolInvocationRecorder.new(run: @run, chat: @chat, attempt: @attempt)
    recorder.sync!
    recorder.sync!
    assert_equal 1, @run.lifecycle_events.where(name: "ai.tool.requested").count
    assert_equal 1, @run.lifecycle_events.where(name: "ai.approval.requested").count
    assert_equal invocation.approval.id, @run.lifecycle_events.find_by!(name: "ai.tool.requested").approval_id
  end

  test "records a tool result as a successful invocation" do
    call = create_tool_call(arguments: { "note" => "remember this" })
    result = @chat.add_message(
      role: :tool,
      content: JSON.generate("status" => "saved", "artifact_id" => 12),
      tool_call_id: call.tool_call_id
    )

    Ai::ToolInvocationRecorder.new(run: @run, chat: @chat, attempt: @attempt).sync!

    invocation = @run.tool_invocations.first
    assert_equal result.id, call.reload.result_id
    assert invocation.succeeded?
    assert_equal "saved", invocation.result.fetch("parsed").fetch("status")
  end

  test "keeps multiple tool calls independently inspectable" do
    first_call = create_tool_call(arguments: {}, tool_call_id: "call-parallel-1", name: "project_snapshot")
    second_call = create_tool_call(arguments: {}, tool_call_id: "call-parallel-2", name: "project_snapshot")
    first_result = @chat.add_message(
      role: :tool,
      content: JSON.generate("call" => first_call.tool_call_id, "status" => "ok"),
      tool_call_id: first_call.tool_call_id
    )
    second_result = @chat.add_message(
      role: :tool,
      content: JSON.generate("call" => second_call.tool_call_id, "status" => "ok"),
      tool_call_id: second_call.tool_call_id
    )

    Ai::ToolInvocationRecorder.new(run: @run, chat: @chat, attempt: @attempt).sync!

    invocations = @run.tool_invocations.order(:tool_call_id).to_a
    assert_equal [ first_call.tool_call_id, second_call.tool_call_id ], invocations.map(&:tool_call_id)
    assert_equal [ first_result.id, second_result.id ], [ first_call.reload.result_id, second_call.reload.result_id ]
    assert invocations.all?(&:succeeded?)
    assert_equal 2, @run.lifecycle_events.where(name: "ai.tool.requested").count
    assert_equal 2, @run.lifecycle_events.where(name: "ai.tool.completed").count
    assert_equal 2, @run.lifecycle_events.where(name: "ai.tool.requested").distinct.count(:event_key)
  end

  test "finalizes a local tool exception with an answerable tool result" do
    call = create_tool_call(arguments: { "note" => "will fail" })
    @run.tool_invocations.create!(
      attempt: @attempt,
      tool_call_id: call.tool_call_id,
      tool_key: call.name,
      status: :running,
      started_at: 1.second.ago
    )
    error = RuntimeError.new("tool exploded")

    Ai::ToolErrorFinalizer.new(@chat, error, run: @run).call
    Ai::ToolInvocationRecorder.new(run: @run, chat: @chat, attempt: @attempt).sync!(failure: error)

    tool_message = @chat.messages.reload.find { |message| message.role.to_s == "tool" }
    invocation = @run.tool_invocations.first
    assert tool_message
    assert_equal call.tool_call_id, tool_message.parent_tool_call.id
    assert invocation.failed?
    assert_nil invocation.approval
    assert_equal "RubyLLM::ToolError", invocation.error_class
    assert_includes invocation.error_message, "Local tool execution failed"
  end

  test "does not finalize pending or remote tool calls as local execution failures" do
    local_call = create_tool_call(arguments: { "note" => "waiting" })
    remote_call = create_tool_call(arguments: { "query" => "waiting" }, name: "web_search", remote: true)
    Ai::ToolInvocationRecorder.new(run: @run, chat: @chat, attempt: @attempt).sync!

    Ai::ToolErrorFinalizer.new(@chat, RuntimeError.new("later step failed"), run: @run).call

    assert_nil local_call.reload.result_id
    assert_nil remote_call.reload.result_id
    assert @run.tool_invocations.all?(&:waiting_for_approval?)
    assert_equal 2, @run.tool_invocations.joins(:approval).where(approvals: { status: "pending" }).count
  end

  test "labels provider-hosted tool calls as remote and local ones as local" do
    remote_call = create_tool_call(arguments: { "query" => "rubyllm" }, name: "web_search", remote: true)
    local_call = create_tool_call(arguments: { "note" => "local" })

    Ai::ToolInvocationRecorder.new(run: @run, chat: @chat, attempt: @attempt).sync!

    remote_invocation = @run.tool_invocations.find_by(tool_call_id: remote_call.tool_call_id)
    assert remote_invocation.remote?
    assert remote_invocation.waiting_for_approval?
    assert remote_invocation.approval.pending?
    assert_not @run.tool_invocations.find_by(tool_call_id: local_call.tool_call_id).remote?
    assert_equal 1, @run.tool_invocations.where(remote: true).count
  end

  private

  def create_tool_call(arguments:, tool_call_id: "call-#{SecureRandom.hex(6)}", name: "save_run_note", remote: false)
    RubyLLM::ActiveRecord::ToolCall.create!(
      message: @assistant,
      tool_call_id: tool_call_id,
      name: name,
      arguments: arguments,
      remote: remote
    )
  end
end

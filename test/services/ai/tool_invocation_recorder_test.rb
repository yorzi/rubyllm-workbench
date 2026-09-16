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

  test "finalizes a local tool exception with an answerable tool result" do
    call = create_tool_call(arguments: { "note" => "will fail" })
    error = RuntimeError.new("tool exploded")

    Ai::ToolErrorFinalizer.new(@chat, error).call
    Ai::ToolInvocationRecorder.new(run: @run, chat: @chat, attempt: @attempt).sync!(failure: error)

    tool_message = @chat.messages.reload.find { |message| message.role.to_s == "tool" }
    invocation = @run.tool_invocations.first
    assert tool_message
    assert_equal call.tool_call_id, tool_message.parent_tool_call.id
    assert invocation.failed?
    assert_equal "RubyLLM::ToolError", invocation.error_class
    assert_includes invocation.error_message, "Local tool execution failed"
  end

  private

  def create_tool_call(arguments:)
    RubyLLM::ActiveRecord::ToolCall.create!(
      message: @assistant,
      tool_call_id: "call-#{SecureRandom.hex(6)}",
      name: "save_run_note",
      arguments: arguments,
      remote: false
    )
  end
end

require "test_helper"

class ToolApprovalFlowTest < ActionDispatch::IntegrationTest
  setup do
    @project = create_project(name: "Approval flow project")
    @chat = create_chat(@project)
    tools_snapshot = Ai::ToolRegistry.snapshot(@project)
    @run = @chat.runs.create!(
      project: @project,
      operation: "chat",
      status: :waiting_for_approval,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "save a note", "tools" => tools_snapshot }
    )
    @attempt = @run.attempts.create!(sequence: 1, provider: @chat.provider, model_id: @chat.model_id, status: :succeeded)
    assistant = @chat.messages.create!(role: "assistant", content: "")
    @tool_call = RubyLLM::ActiveRecord::ToolCall.create!(
      message: assistant,
      tool_call_id: "call-approval-flow",
      name: "save_run_note",
      arguments: { "note" => "a reviewed note" },
      remote: false
    )
    Ai::ToolInvocationRecorder.new(run: @run, chat: @chat, attempt: @attempt).sync!
    @invocation = @run.tool_invocations.first
  end

  test "lists registered tools and toggles the next Run snapshot" do
    get project_tool_definitions_path(@project)

    assert_response :success
    assert_includes response.body, "Tool Lab"
    assert_includes response.body, "Inspect JSON Schema"
    assert_includes response.body, "save_run_note"

    patch project_tool_definition_path(@project, @project.tool_definitions.find_by!(key: "project_snapshot")), params: {
      tool_definition: { enabled: "0" }
    }

    assert_response :redirect
    assert_not @project.tool_definitions.find_by!(key: "project_snapshot").reload.enabled?
  end

  test "shows a pending approval after reload and records approval before resuming" do
    get project_chat_path(@project, @chat)

    assert_response :success
    assert_includes response.body, "Approval required"
    assert_includes response.body, "save_run_note"
    assert_includes response.body, "Review its arguments"

    assert_enqueued_with(job: ChatResponseJob, args: [ @run.id ]) do
      patch project_chat_approval_path(@project, @chat, @invocation.approval), params: {
        approval: { decision: "approved", note: "Reviewed in integration test" }
      }
    end

    assert_response :redirect
    assert_equal "approved", @invocation.approval.reload.status
    assert_equal "Reviewed in integration test", @invocation.approval.decision_note
    assert_equal "approved", @invocation.reload.status
    assert_equal "approved", @tool_call.reload.approval
  end

  test "records denial in both the app audit row and RubyLLM tool call" do
    assert_enqueued_with(job: ChatResponseJob, args: [ @run.id ]) do
      patch project_chat_approval_path(@project, @chat, @invocation.approval), params: {
        approval: { decision: "denied" }
      }
    end

    assert_response :redirect
    assert_equal "denied", @invocation.approval.reload.status
    assert_equal "denied", @invocation.reload.status
    assert_equal "denied", @tool_call.reload.approval
    assert @invocation.approval.decided?
    assert @invocation.approval.decided_at
  end
end

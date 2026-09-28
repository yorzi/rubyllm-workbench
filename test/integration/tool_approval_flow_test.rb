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
    assert_includes response.body, "Tool execution"
    assert_includes response.body, "Sequential — one call at a time"
    assert_includes response.body, "save_run_note"

    patch project_tool_settings_path(@project), params: {
      tool_settings: { execution_mode: "parallel" }
    }

    assert_response :redirect
    assert_equal "parallel", @project.reload.tool_execution_mode

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
    assert_includes response.body, "Review each request and its location"

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
    assert_equal 1, @run.lifecycle_events.where(name: "ai.approval.decided").count
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

  test "blocks a new Run when an approved remote call has no recorded provider result" do
    chat = create_chat(@project)
    run = chat.runs.create!(
      project: @project,
      operation: "agent",
      status: :running,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "search" }
    )
    attempt = run.attempts.create!(sequence: 1, provider: chat.provider, model_id: chat.model_id, status: :running)
    assistant = chat.messages.create!(role: "assistant", content: "")
    remote_call = RubyLLM::ActiveRecord::ToolCall.create!(
      message: assistant,
      tool_call_id: "call-approved-remote-without-result",
      name: "web_search",
      arguments: { "query" => "search" },
      remote: true
    )
    chat.approve(remote_call.tool_call_id)
    Ai::ToolInvocationRecorder.new(run:, chat:, attempt:).sync!
    invocation = run.tool_invocations.find_by!(tool_call_id: remote_call.tool_call_id)
    run.fail!(RuntimeError.new("provider response was lost"))

    assert_equal "approved", invocation.approval.reload.status
    assert_equal "remote_tool_outcome_unknown", invocation.reload.error_code
    assert_nil remote_call.reload.result_id

    assert_no_enqueued_jobs only: ChatResponseJob do
      post project_chat_messages_path(@project, chat), params: { message: { content: "continue" } }
    end
    assert_response :redirect
    assert_equal "This chat has an approved remote tool call with no saved provider result. Its external outcome is unknown; start a new chat instead of resuming it.", flash[:alert]

    get project_chat_path(@project, chat)
    assert_response :success
    assert_includes response.body, "its external outcome is unknown"
    assert_includes response.body, "Start a new chat"
  end

  test "cancelling a Run expires pending approval and removes stale controls" do
    @run.update!(operation: "agent")
    @run.cancel!

    assert @run.reload.cancelled?
    assert_equal "expired", @invocation.approval.reload.status
    assert @invocation.approval.decided_at
    assert_equal "Run cancelled before approval was decided.", @invocation.approval.decision_note
    assert_equal "cancelled", @invocation.reload.status
    assert_equal "RunCancellation", @invocation.error_class
    assert_equal "Run cancelled before the tool action started.", @invocation.error_message
    assert_equal "denied", @tool_call.reload.approval
    assert @tool_call.result_id
    assert_not @chat.reload.cancelled?
    assert_not @invocation.approval_pending?
    assert_equal 0, AgentRunDelivery.where(run_id: @run.id, intent: "approval").count

    approval_event = @run.lifecycle_events.find_by!(name: "ai.approval.expired")
    assert_equal @invocation.approval.id, approval_event.approval_id
    assert_equal @invocation.id, approval_event.tool_invocation_id
    tool_event = @run.lifecycle_events.find_by!(name: "ai.tool.cancelled")
    assert_equal @invocation.id, tool_event.tool_invocation_id

    assert_raises(ArgumentError) do
      Ai::ApprovalService.decide!(invocation: @invocation, decision: "approved")
    end
    assert_equal "expired", @invocation.approval.reload.status
    assert_equal "cancelled", @invocation.reload.status
    assert_equal 0, AgentRunDelivery.where(run_id: @run.id, intent: "approval").count

    assert_nothing_raised do
      with_provider_configuration(@chat.provider) do
        @chat.reload.ask_later("a later independent message")
      end
    end

    get project_chat_path(@project, @chat)

    assert_response :success
    assert_select "#tool-approvals", count: 0
    assert_equal "expired", @invocation.approval.reload.status
    assert_equal "cancelled", @invocation.reload.status
  end

  test "failing a Run expires pending approval and rejects stale decisions" do
    @run.update!(operation: "agent")
    @run.fail!(RuntimeError.new("provider unavailable"))

    assert_equal "expired", @invocation.approval.reload.status
    assert_equal "failed", @invocation.reload.status
    assert_equal 0, @run.agent_run_deliveries.where(intent: "approval").count

    get project_chat_path(@project, @chat)

    assert_response :success
    assert_select "#tool-approvals", count: 0

    patch project_chat_approval_path(@project, @chat, @invocation.approval), params: {
      approval: { decision: "approved", note: "stale decision" }
    }

    assert_response :redirect
    assert_equal "This Run can no longer be resumed.", flash[:alert]
    assert_equal "expired", @invocation.approval.reload.status
    assert_equal "failed", @invocation.reload.status
    assert_equal 0, @run.agent_run_deliveries.where(intent: "approval").count
  end

  test "cancelling a running Run reconciles an approval before its waiting state is saved" do
    @run.update!(operation: "agent", status: :running)

    @run.cancel!

    assert @run.reload.cancelled?
    assert_equal "expired", @invocation.approval.reload.status
    assert_equal "cancelled", @invocation.reload.status
    assert_equal "denied", @tool_call.reload.approval
    assert @tool_call.result_id
    assert_not @chat.reload.cancelled?
    assert_equal 0, AgentRunDelivery.where(run_id: @run.id, intent: "approval").count

    assert_nothing_raised do
      with_provider_configuration(@chat.provider) do
        @chat.reload.ask_later("a later independent message")
      end
    end
  end

  test "surfaces and approves a provider-hosted remote tool request" do
    remote_chat, run, tool_call, invocation = create_remote_pending_approval

    get project_chat_path(@project, remote_chat)

    assert_response :success
    assert_includes response.body, "provider-hosted calls run through the selected provider"
    assert_includes response.body, "Provider hosted"
    assert_includes response.body, "web_search"
    assert_select "#tool-approvals" do
      assert_select "button", text: "Approve"
      assert_select "button", text: "Deny"
    end
    assert invocation.waiting_for_approval?
    assert invocation.approval.pending?

    assert_enqueued_with(job: ChatResponseJob, args: [ run.id ]) do
      patch project_chat_approval_path(@project, remote_chat, invocation.approval), params: {
        approval: { decision: "approved", note: "Allow provider hosted search" }
      }
    end

    assert_equal "approved", invocation.reload.status
    assert_equal "approved", invocation.approval.reload.status
    assert_equal "approved", tool_call.reload.approval

    with_provider_configuration("openai") do
      Ai::ChatTooling.new(chat: remote_chat, project: @project, run:).configure
      remote_chat.run_tools
    end

    tool_call.reload
    assert tool_call.result_id
    result = remote_chat.messages.find(tool_call.result_id)
    assert_equal "tool", result.role
    assert_includes result.raw_content.to_json, "mcp_approval_response"
    assert_includes result.raw_content.to_json, '"approve":true'
  end

  test "routes denial of a provider-hosted remote tool through the Agent outbox" do
    remote_chat, run, tool_call, invocation = create_remote_pending_approval(operation: "agent")

    assert_no_enqueued_jobs(only: ChatResponseJob) do
      patch project_chat_approval_path(@project, remote_chat, invocation.approval), params: {
        approval: { decision: "denied", note: "Do not run provider hosted search" }
      }
    end

    delivery = run.agent_run_deliveries.find_by!(intent: "approval")
    assert_equal [ run.id, "approval", invocation.id, run.agent_execution_generation ], delivery.job_arguments
    assert_equal "denied", invocation.reload.status
    assert_equal "denied", tool_call.reload.approval

    with_provider_configuration("openai") do
      Ai::ChatTooling.new(chat: remote_chat, project: @project, run:).configure
      remote_chat.run_tools
    end

    tool_call.reload
    assert tool_call.result_id
    result = remote_chat.messages.find(tool_call.result_id)
    assert_equal "tool", result.role
    assert_includes result.raw_content.to_json, "mcp_approval_response"
    assert_includes result.raw_content.to_json, '"approve":false'
  end

  test "cancelling remote approval writes the provider approval response shape" do
    model_info = RubyLLM.models.chat_models.select { |candidate| candidate.provider == "openai" }.first
    model = RubyLLM::ActiveRecord::Model.find_or_create_by!(model_id: model_info.id, provider: model_info.provider) do |record|
      record.assign_attributes(
        name: model_info.name,
        family: model_info.family,
        model_created_at: model_info.created_at,
        context_window: model_info.context_window,
        max_output_tokens: model_info.max_output_tokens,
        knowledge_cutoff: model_info.knowledge_cutoff,
        modalities: model_info.modalities.to_h,
        capabilities: model_info.capabilities,
        pricing: model_info.pricing.to_h,
        metadata: model_info.metadata
      )
    end
    remote_chat = Chat.create!(project: @project, model:)
    run = remote_chat.runs.create!(
      project: @project,
      operation: "chat",
      status: :running,
      requested_by: "test",
      input_snapshot_json: { "tools" => [], "provider_tools" => [ "web_search" ] }
    )
    attempt = run.attempts.create!(
      sequence: 1,
      provider: "openai",
      model_id: model.model_id,
      status: :succeeded
    )
    assistant = remote_chat.messages.create!(role: "assistant", content: "")
    tool_call = RubyLLM::ActiveRecord::ToolCall.create!(
      message: assistant,
      tool_call_id: "call-remote-approval",
      name: "web_search",
      arguments: { "query" => "Rails" },
      remote: true
    )
    invocation = run.tool_invocations.create!(
      attempt:,
      tool_call_id: tool_call.tool_call_id,
      tool_key: tool_call.name,
      remote: true,
      status: :waiting_for_approval,
      arguments_json: tool_call.arguments
    )
    with_provider_configuration("openai") { run.cancel! }

    assert run.reload.cancelled?
    assert_equal "cancelled", invocation.reload.status
    assert_nil invocation.approval
    assert_equal "denied", tool_call.reload.approval
    assert tool_call.result_id
    result = remote_chat.messages.find(tool_call.result_id)
    assert_equal "tool", result.role
    assert_equal "Denied", result.content
    assert_includes result.raw_content.to_json, "mcp_approval_response"
    assert_includes result.raw_content.to_json, tool_call.tool_call_id
    assert_equal 0, AgentRunDelivery.where(run_id: run.id, intent: "approval").count
  end

  private

  def create_remote_pending_approval(operation: "chat")
    model_info = RubyLLM.models.chat_models.select { |candidate| candidate.provider == "openai" }.first
    model = RubyLLM::ActiveRecord::Model.find_or_create_by!(model_id: model_info.id, provider: model_info.provider) do |record|
      record.assign_attributes(
        name: model_info.name,
        family: model_info.family,
        model_created_at: model_info.created_at,
        context_window: model_info.context_window,
        max_output_tokens: model_info.max_output_tokens,
        knowledge_cutoff: model_info.knowledge_cutoff,
        modalities: model_info.modalities.to_h,
        capabilities: model_info.capabilities,
        pricing: model_info.pricing.to_h,
        metadata: model_info.metadata
      )
    end
    remote_chat = Chat.create!(project: @project, model:)
    run = remote_chat.runs.create!(
      project: @project,
      operation:,
      status: :waiting_for_approval,
      requested_by: "test",
      input_snapshot_json: { "tools" => [], "provider_tools" => [ "web_search" ] }
    )
    attempt = run.attempts.create!(
      sequence: 1,
      provider: "openai",
      model_id: model.model_id,
      status: :succeeded
    )
    assistant = remote_chat.messages.create!(role: "assistant", content: "")
    tool_call = RubyLLM::ActiveRecord::ToolCall.create!(
      message: assistant,
      tool_call_id: "call-remote-approval-#{SecureRandom.hex(4)}",
      name: "web_search",
      arguments: { "query" => "RubyLLM documentation" },
      remote: true
    )

    Ai::ToolInvocationRecorder.new(run:, chat: remote_chat, attempt:).sync!
    invocation = run.tool_invocations.find_by!(tool_call_id: tool_call.tool_call_id)
    [ remote_chat, run, tool_call, invocation ]
  end
end

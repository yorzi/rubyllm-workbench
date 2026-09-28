require "test_helper"

class AgentRunFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  class AgentToolRecorderStub
    attr_accessor :attempt

    def sync!(failure: nil)
      true
    end
  end

  class CitedDeterministicAgent
    def initialize(chat)
      @chat = chat
    end

    def ask_later(prompt)
      @chat.messages.create!(role: "user", content: prompt)
    end

    def awaiting_approval?
      false
    end

    def complete?
      @chat.messages.where(role: "assistant").count >= 2
    end

    def step
      number = @chat.messages.where(role: "assistant").count + 1
      message = @chat.messages.create!(
        role: "assistant",
        content: "Research step #{number}.",
        citations: number == 1 ? [
          { "title" => "Primary source", "url" => "https://example.test/reference" }
        ] : []
      )
      yield Data.define(:content).new(message.content) if block_given?
      message
    end
  end

  class CitedDeterministicAgentRunJob < AgentRunJob
    private

    def restore_agent
      @agent = CitedDeterministicAgent.new(@run.chat)
      @tool_recorder = AgentToolRecorderStub.new
    end
  end

  setup do
    @project = create_project(name: "Agent UI project")
    @model = chat_model
    Ai::ToolRegistry.sync_project!(@project)
    @tool_key = @project.tool_definitions.enabled.order(:key).pick(:key)
    assert @tool_key, "the default Tool Lab should expose an enabled local tool"
  end

  test "renders a decided Agent approval as a queued continuation until a worker claims it" do
    chat, run, _attempt, invocation = create_pending_agent_approval(title: "Resolved approval")

    with_provider_configuration(@model.provider) do
      patch project_chat_approval_path(@project, chat, invocation.approval), params: {
        approval: { decision: "denied", note: "No provider work in this test" }
      }
    end

    assert_response :see_other
    assert run.reload.waiting_for_approval?
    assert_equal 1, run.agent_run_deliveries.where(intent: "approval").count

    get project_chat_path(@project, chat)

    assert_response :success
    assert_select "#tool-approvals", count: 0
    assert_select "#run_#{run.id}_status", text: "Continuation queued"
    assert_includes response.body, "Tool decision recorded; Run ##{run.id} queued to continue."
  end

  test "cancels a pending Agent approval from the Run inspector and shows a terminal state" do
    chat, run, attempt, invocation = create_pending_agent_approval(title: "Cancelled approval")

    get run_path(run)
    assert_response :success
    assert_select "button", text: "Cancel Run"

    post cancel_run_path(run)

    assert_response :see_other
    assert_redirected_to run_path(run)
    assert run.reload.cancelled?
    assert attempt.reload.cancelled?
    assert_equal "expired", invocation.approval.reload.status
    assert_equal "cancelled", invocation.reload.status
    assert_equal 0, run.agent_run_deliveries.where(intent: "approval").count

    follow_redirect!
    assert_response :success
    assert_select "#run_#{run.id}_status", text: "Cancelled"
    assert_select "button", text: "Cancel Run", count: 0

    get project_chat_path(@project, chat)

    assert_response :success
    assert_select "#tool-approvals", count: 0
    assert_select "#run_#{run.id}_status", text: "Cancelled"
  end

  test "creates an Agent in the UI, dispatches it, and reloads its frozen steps and citation" do
    get project_agent_definitions_path(@project)
    assert_response :success
    assert_select "h1", text: "Agents"
    assert_select "a", text: "New agent"

    get new_project_agent_definition_path(@project)
    assert_response :success
    assert_select "legend", text: "Local tools"
    assert_select "legend", text: "Provider tools"

    definition = nil
    with_provider_configuration(@model.provider) do
      post project_agent_definitions_path(@project), params: {
        agent_definition: {
          name: "Source checker",
          provider: @model.provider,
          model_id: @model.id,
          instructions: "Verify claims with trustworthy sources.",
          tool_keys: [ @tool_key ],
          provider_tools: [ "" ],
          options: { temperature: "0.2", max_output_tokens: "512" }
        }
      }
      definition = @project.agent_definitions.order(:id).last
    end

    assert_response :see_other
    assert_equal 1, definition.revision
    assert_equal [ @tool_key ], definition.tool_keys

    get project_agent_definition_path(@project, definition)
    assert_response :success
    assert_select "h2", text: "Run this Agent"
    assert_select "form[action=?]", project_agent_definition_runs_path(@project, definition)

    run = nil
    with_provider_configuration(@model.provider) do
      post project_agent_definition_runs_path(@project, definition), params: {
        agent_run: { prompt: "Check whether the claim has a reliable source." }
      }
      run = Run.order(:id).last
    end

    assert_response :see_other
    assert_equal "agent", run.operation
    assert run.queued?
    assert_equal "Check whether the claim has a reliable source.", run.input_snapshot.fetch("prompt")
    frozen_definition = run.input_snapshot.fetch("agent_definition")
    assert_equal 1, frozen_definition.fetch("revision")
    assert_equal "Verify claims with trustworthy sources.", frozen_definition.fetch("instructions")
    assert_equal [ @tool_key ], frozen_definition.fetch("tool_keys")
    assert_includes run.input_snapshot.fetch("tools").map { |tool| tool.fetch("key") }, @tool_key
    delivery = run.agent_run_deliveries.find_by!(intent: "execute")
    assert_equal 0, delivery.expected_generation

    with_provider_configuration(@model.provider) do
      perform_enqueued_jobs do
        CitedDeterministicAgentRunJob.perform_later(*delivery.job_arguments)
      end
    end

    run.reload
    assert run.succeeded?, "#{run.status}: #{run.error_summary}"
    assert_equal 2, run.result_summary.fetch("agent_step_count")
    assert_equal [ "succeeded", "succeeded" ], run.attempts.order(:sequence).pluck(:status)
    citation_artifact = run.artifacts.find_by!(kind: "citation_set")
    research_report = run.artifacts.find_by!(kind: "report", name: "Research report · Source checker")
    assert_equal "agent_research_report", research_report.metadata_json.fetch("report_type")
    assert_equal run.result_summary.fetch("source_message_id"), research_report.content_json.fetch("source_message_id")
    assert_equal [ citation_artifact.id ], research_report.content_json.fetch("citation_artifact_ids")
    assert_equal 1, research_report.content_json.dig("agent", "revision")
    assert_equal "Research step 2.", research_report.content_text
    assert_equal research_report.id, run.result_summary.fetch("research_report_artifact_id")
    assert_equal [ "Check whether the claim has a reliable source." ],
      run.chat.messages.where(role: "user").pluck(:content)

    definition.update!(instructions: "Use government and academic sources.")
    assert_equal 2, definition.reload.revision
    assert_equal 1, run.input_snapshot.dig("agent_definition", "revision")
    assert_equal "Verify claims with trustworthy sources.", run.input_snapshot.dig("agent_definition", "instructions")

    assert_equal run.result_summary.fetch("citation_artifact_id"), citation_artifact.id
    assert_equal 1, citation_artifact.metadata_json.fetch("citation_count")
    source_message_id = citation_artifact.metadata_json.fetch("source_message_id")
    assert_equal "assistant", run.chat.messages.find(source_message_id).role

    step_events = run.lifecycle_events.where(name: "ai.agent.step").order(:occurred_at, :id)
    assert_equal [ "started", "completed", "started", "completed" ],
      step_events.map { |event| event.payload.fetch("step_status") }

    get run_path(run)
    assert_response :success
    assert_select "#lifecycle-events-heading"
    assert_select "#agent-research-report", text: /Research step 2\./
    assert_select "#agent-research-report a[href=?]", "#citation-artifact-#{citation_artifact.id}"
    assert_select "h2", text: "Source citations"
    assert_select "a[href=?]", "https://example.test/reference", text: "Primary source"
    assert_select "h2", text: "Input snapshot"
    assert_includes response.body, "Verify claims with trustworthy sources."
  end

  test "disables queueing local-tool Agents when registry capability metadata is missing" do
    definition = @project.agent_definitions.create!(
      name: "Unlisted local-tool agent",
      provider: @model.provider,
      model_id: @model.id,
      instructions: "Use the project tool.",
      tool_keys: [ @tool_key ]
    )
    definition.update_column(:model_id, "not-in-the-chat-registry")

    get project_agent_definition_path(@project, definition)

    assert_response :success
    assert_includes response.body, "This Agent cannot be queued"
    assert_select "input[type=submit][disabled]"
  end

  private

  def create_pending_agent_approval(title:)
    chat = create_chat(@project)
    approval_tool = @project.tool_definitions.find_by!(key: "save_run_note")
    definition = @project.agent_definitions.create!(
      name: "#{title} Agent",
      provider: @model.provider,
      model_id: @model.id,
      instructions: "Decide whether the saved tool request should continue.",
      tool_keys: [ approval_tool.key ],
      provider_tools: [],
      options: {}
    )
    run = chat.runs.create!(
      project: @project,
      operation: "agent",
      status: :running,
      started_at: Time.current,
      requested_by: "integration test",
      input_snapshot_json: {
        "prompt" => "Review this tool request.",
        "agent_definition" => definition.snapshot,
        "tools" => Ai::ToolRegistry.snapshot(@project)
      }
    )
    attempt = run.attempts.create!(
      sequence: 1,
      provider: @model.provider,
      model_id: @model.id,
      status: :running,
      started_at: Time.current
    )
    assistant = chat.messages.create!(role: "assistant", content: "")
    RubyLLM::ActiveRecord::ToolCall.create!(
      message: assistant,
      tool_call_id: "#{title.parameterize}-#{SecureRandom.hex(4)}",
      name: approval_tool.key,
      arguments: { "note" => "synthetic request" },
      remote: false
    )
    Ai::ToolInvocationRecorder.new(run:, chat:, attempt:).sync!
    invocation = run.tool_invocations.first
    run.wait_for_approval!({ "pending_tool_call_ids" => [ invocation.id ] }, attempt_id: attempt.id)

    [ chat, run, attempt, invocation ]
  end
end

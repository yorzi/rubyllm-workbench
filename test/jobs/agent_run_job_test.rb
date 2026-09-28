require "test_helper"

class AgentRunJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  CitationResponse = Data.define(:id, :citations, :server_tool_calls)
  AttemptRecorderStub = Struct.new(:partial_output)
  AgentToolRecorderStub = Struct.new(:attempt) do
    def sync!(failure: nil)
      true
    end
  end

  class DeterministicAgent
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
      content = "Deterministic step #{@chat.messages.where(role: 'assistant').count + 1}."
      message = @chat.messages.create!(role: "assistant", content: content)
      yield Data.define(:content).new(content) if block_given?
      message
    end
  end

  class DeterministicAgentRunJob < AgentRunJob
    class << self
      attr_accessor :received_arguments
    end

    def perform(*arguments)
      self.class.received_arguments ||= []
      self.class.received_arguments << arguments.dup
      super
    end

    private

    def restore_agent
      @agent = DeterministicAgent.new(@run.chat)
      @tool_recorder = AgentToolRecorderStub.new
    end
  end

  class EmptyAnswerAgent < DeterministicAgent
    def complete?
      @chat.messages.where(role: "assistant").exists?
    end

    def step
      @chat.messages.create!(role: "assistant", content: "")
      RubyLLM::Message.new(role: :assistant, content: "", finish_reason: :length)
    end
  end

  class EmptyAnswerAgentRunJob < AgentRunJob
    private

    def restore_agent
      @agent = EmptyAnswerAgent.new(@run.chat)
      @tool_recorder = AgentToolRecorderStub.new
    end
  end

  class DeterministicRecoveryAgent
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
      @chat.messages.where(role: "assistant").exists?
    end

    def step
      message = @chat.messages.create!(role: "assistant", content: "Recovered after interruption.")
      yield Data.define(:content).new(message.content) if block_given?
      message
    end
  end

  class DeterministicRecoveryAgentRunJob < AgentRunJob
    private

    def restore_agent
      @agent = DeterministicRecoveryAgent.new(@run.chat)
      @tool_recorder = AgentToolRecorderStub.new
    end
  end

  class DeterministicCancellationAgent
    def initialize(chat, run)
      @chat = chat
      @run = run
    end

    def ask_later(prompt)
      @chat.messages.create!(role: "user", content: prompt)
    end

    def awaiting_approval?
      false
    end

    def complete?
      false
    end

    def step
      message = @chat.messages.create!(role: "assistant", content: "Reply returned after cancellation.")
      yield Data.define(:content).new(message.content) if block_given?
      @run.cancel!
      message
    end
  end

  class DeterministicCancellationAgentRunJob < AgentRunJob
    private

    def restore_agent
      @agent = DeterministicCancellationAgent.new(@run.chat, @run)
      @tool_recorder = AgentToolRecorderStub.new
    end
  end

  class DeterministicApprovalAgent
    def initialize(chat, run)
      @chat = chat
      @run = run
    end

    def ask_later(prompt)
      @chat.messages.create!(role: "user", content: prompt)
    end

    def awaiting_approval?
      @run.tool_invocations.waiting_for_approval.exists?
    end

    def complete?
      @chat.messages.where(role: "assistant").count >= 2
    end

    def step
      tool_call = persisted_tool_calls.first
      if tool_call.nil?
        message = @chat.messages.create!(role: "assistant", content: "A note needs approval.")
        RubyLLM::ActiveRecord::ToolCall.create!(
          message: message,
          tool_call_id: SecureRandom.uuid,
          name: "save_run_note",
          arguments: { "note" => "Approved note" },
          remote: false
        )
      elsif tool_call.result.nil?
        tool_result = if tool_call.approval == "approved"
          Ai::Tools::SaveRunNote.new(project: @run.project, run: @run).execute(
            note: tool_call.arguments.fetch("note"),
            tool_call: tool_call.to_llm
          )
        else
          { "status" => "denied" }
        end
        message = @chat.messages.create!(role: "tool", content: JSON.generate(tool_result))
        tool_call.update!(result: message)
      else
        message = @chat.messages.create!(role: "assistant", content: "Approval decision processed.")
      end

      yield Data.define(:content).new(message.content) if block_given?
      message
    end

    private

    def persisted_tool_calls
      RubyLLM::ActiveRecord::ToolCall.where(
        message_type: Message.polymorphic_name,
        message_id: @chat.messages.select(:id)
      ).order(:id)
    end
  end

  class DeterministicApprovalAgentRunJob < AgentRunJob
    class << self
      attr_accessor :received_arguments
    end

    def perform(*arguments)
      self.class.received_arguments ||= []
      self.class.received_arguments << arguments.dup
      super
    end

    private

    def restore_agent
      @agent = DeterministicApprovalAgent.new(@run.chat, @run)
      @tool_recorder = Ai::ToolInvocationRecorder.new(
        run: @run,
        chat: @run.chat,
        agent_execution_token: @lease_token,
        agent_execution_generation: @lease_generation
      )
    end
  end

  class DeterministicRemoteApprovalAgent
    def initialize(chat, run)
      @chat = chat
      @run = run
    end

    def ask_later(prompt)
      @chat.messages.create!(role: "user", content: prompt)
    end

    def awaiting_approval?
      @run.tool_invocations.waiting_for_approval.exists?
    end

    def complete?
      @chat.messages.where(role: "assistant").count >= 2
    end

    def step
      tool_call = pending_remote_tool_call
      if tool_call
        @chat.run_tools
        message = @chat.messages.reorder(id: :desc).first
      else
        message = @chat.messages.create!(role: "assistant", content: "Hosted approval handled.")
      end

      yield Data.define(:content).new(message.content) if block_given?
      message
    end

    private

    def pending_remote_tool_call
      RubyLLM::ActiveRecord::ToolCall.where(
        message_type: Message.polymorphic_name,
        message_id: @chat.messages.select(:id)
      ).includes(:result).order(:id).find do |tool_call|
        tool_call.remote? && tool_call.result.nil?
      end
    end
  end

  class DeterministicRemoteApprovalAgentRunJob < AgentRunJob
    private

    def restore_agent
      @agent = DeterministicRemoteApprovalAgent.new(@run.chat, @run)
      @tool_recorder = Ai::ToolInvocationRecorder.new(
        run: @run,
        chat: @run.chat,
        agent_execution_token: @lease_token,
        agent_execution_generation: @lease_generation
      ).attach
    end
  end

  class FailingApprovalAgent
    def initialize(chat, run, tool_recorder)
      @chat = chat
      @run = run
      @tool_recorder = tool_recorder
    end

    def ask_later(prompt)
      @chat.messages.create!(role: "user", content: prompt)
    end

    def awaiting_approval?
      false
    end

    def complete?
      false
    end

    def step
      assistant = @chat.messages.create!(role: "assistant", content: "Two calls need approval.")
      RubyLLM::ActiveRecord::ToolCall.create!(
        message: assistant,
        tool_call_id: "failed-local-approval-#{SecureRandom.hex(4)}",
        name: "save_run_note",
        arguments: { "note" => "must not execute" },
        remote: false
      )
      RubyLLM::ActiveRecord::ToolCall.create!(
        message: assistant,
        tool_call_id: "failed-remote-approval-#{SecureRandom.hex(4)}",
        name: "web_search",
        arguments: { "query" => "RubyLLM" },
        remote: true
      )
      @tool_recorder.sync!
      raise "provider failed after requesting approvals"
    end
  end

  class FailingApprovalAgentRunJob < AgentRunJob
    private

    def restore_agent
      @tool_recorder = Ai::ToolInvocationRecorder.new(
        run: @run,
        chat: @run.chat,
        agent_execution_token: @lease_token,
        agent_execution_generation: @lease_generation
      ).attach
      @agent = FailingApprovalAgent.new(@run.chat, @run, @tool_recorder)
    end
  end

  AgentStub = Struct.new(:approval_pending) do
    def awaiting_approval?
      approval_pending
    end
  end

  setup do
    @project = create_project(name: "Agent job project")
    @chat = create_chat(@project)
    @run = @chat.runs.create!(
      project: @project,
      operation: "agent",
      status: :running,
      requested_by: "test",
      input_snapshot_json: {
        "prompt" => "verify a claim",
        "agent_definition" => { "id" => 42, "name" => "Source checker", "revision" => 3 }
      }
    )
    @attempt = @run.attempts.create!(
      sequence: 1,
      provider: @chat.provider,
      model_id: @chat.model_id,
      status: :succeeded
    )
  end

  test "stores a cited Agent step on the Run and in its lifecycle timeline" do
    source_message = @chat.messages.create!(role: "assistant", content: "Claim verified.")
    response = CitationResponse.new(
      source_message.id,
      [ { "title" => "Primary source", "url" => "https://example.test/source" } ],
      []
    )
    artifact = Ai::CitationSetRecorder.new(
      run: @run,
      attempt: @attempt,
      response: response,
      source_message_id: source_message.id
    ).call
    job = AgentRunJob.new
    job.instance_variable_set(:@run, @run)
    job.instance_variable_set(:@agent, AgentStub.new(false))
    job.instance_variable_set(:@attempt_recorder, AttemptRecorderStub.new(nil))

    job.send(:save_step_summary, 1, response, source_message.id, artifact)
    job.send(:emit_step_event, 1, @attempt, "completed")

    summary = @run.reload.result_summary
    assert_equal 1, summary.fetch("agent_step_count")
    assert_equal 3, summary.dig("agent_definition", "revision")
    assert_equal [ artifact.id ], summary.fetch("citation_artifact_ids")
    assert_equal artifact.id, summary.fetch("citation_artifact_id")
    assert_equal source_message.id, artifact.metadata_json.fetch("source_message_id")

    event = @run.lifecycle_events.find_by!(name: "ai.agent.step")
    assert_equal 1, event.payload_json.fetch("step_number")
    assert_equal "completed", event.payload_json.fetch("step_status")
    assert_equal 3, event.payload_json.fetch("agent_revision")
  end

  test "rejects a frozen local-tool snapshot without function-calling registry metadata before agent construction" do
    @run.update!(input_snapshot_json: {
      "prompt" => "verify a claim",
      "tools" => [],
      "agent_definition" => {
        "provider" => @chat.provider,
        "model_id" => "not-in-the-chat-registry",
        "instructions" => "Use the local tool.",
        "tool_keys" => [ "project_snapshot" ],
        "provider_tools" => [],
        "options" => {}
      }
    })
    job = AgentRunJob.new
    job.instance_variable_set(:@run, @run)

    error = assert_raises(ArgumentError) { job.send(:restore_agent) }

    assert_includes error.message, "function_calling"
    assert_not job.instance_variable_defined?(:@agent)
  end

  test "executes a deterministic multi-step Agent Run through completion" do
    DeterministicAgentRunJob.received_arguments = []
    snapshot = {
      "prompt" => "verify a claim",
      "tools" => [],
      "tool_options" => {},
      "provider_tools" => [],
      "agent_definition" => {
        "id" => 42,
        "name" => "Source checker",
        "revision" => 3,
        "provider" => @chat.provider.to_s,
        "model_id" => @chat.model_id.to_s,
        "instructions" => "Check sources.",
        "tool_keys" => [],
        "provider_tools" => [],
        "options" => {}
      }
    }
    run = @chat.runs.create!(
      project: @project,
      operation: "agent",
      status: :queued,
      requested_by: "test",
      input_snapshot_json: snapshot
    )
    delivery = AgentRunDelivery.record!(run:, intent: "execute", expected_generation: 0)

    perform_enqueued_jobs do
      DeterministicAgentRunJob.perform_later(*delivery.job_arguments)
    end

    assert run.reload.succeeded?, "#{run.status}: #{run.error_summary} #{run.result_summary.inspect}"
    assert_nil run.agent_execution_token
    assert_equal 2, run.result_summary.fetch("agent_step_count")
    research_report = run.artifacts.find_by!(kind: "report", name: "Research report · Source checker")
    assert_equal "Deterministic step 2.", research_report.content_text
    assert_equal run.result_summary.fetch("research_report_artifact_id"), research_report.id
    assert_equal [ 0, 1 ], DeterministicAgentRunJob.received_arguments.map { |arguments| arguments[3] }
    assert_equal 3, run.result_summary.dig("agent_definition", "revision")
    assert_equal [ "succeeded", "succeeded" ], run.attempts.order(:sequence).pluck(:status)
    assert_equal [ "verify a claim" ], @chat.messages.where(role: "user").pluck(:content)
    assert_equal [ "Deterministic step 1.", "Deterministic step 2." ],
      @chat.messages.where(role: "assistant").order(:id).pluck(:content)

    events = run.lifecycle_events.where(name: "ai.agent.step").order(:created_at, :id)
    assert_equal [ "started", "completed", "started", "completed" ],
      events.map { |event| event.payload_json.fetch("step_status") }
  end

  test "fails instead of storing an empty report when the model exhausts its output budget" do
    snapshot = {
      "prompt" => "research something", "tools" => [], "tool_options" => {}, "provider_tools" => [],
      "agent_definition" => {
        "id" => 7, "name" => "Budgeted", "revision" => 1, "provider" => @chat.provider.to_s, "model_id" => @chat.model_id.to_s,
        "instructions" => "Answer.", "tool_keys" => [], "provider_tools" => [], "options" => { "max_output_tokens" => 16 }
      }
    }
    run = @chat.runs.create!(project: @project, operation: "agent", status: :queued, requested_by: "test", input_snapshot_json: snapshot)
    delivery = AgentRunDelivery.record!(run:, intent: "execute", expected_generation: 0)

    perform_enqueued_jobs { EmptyAnswerAgentRunJob.perform_later(*delivery.job_arguments) }

    run.reload
    assert run.failed?, "#{run.status}: #{run.result_summary.inspect}"
    assert_includes run.error_summary, "finished without a final answer (finish reason: length)"
    assert_not run.artifacts.where(kind: "report").exists?
    assert_equal "length", run.attempts.order(:sequence).last.finish_reason
  end

  test "reconciles a blank assistant placeholder after reclaiming an expired Run lease" do
    chat = create_chat(@project)
    snapshot = {
      "prompt" => "continue after a worker restart",
      "tools" => [],
      "tool_options" => {},
      "provider_tools" => [],
      "agent_definition" => {
        "id" => 44,
        "name" => "Recovery checker",
        "revision" => 1,
        "provider" => chat.provider.to_s,
        "model_id" => chat.model_id.to_s,
        "instructions" => "Recover the incomplete step.",
        "tool_keys" => [],
        "provider_tools" => [],
        "options" => {}
      }
    }
    run = chat.runs.create!(
      project: @project,
      operation: "agent",
      status: :running,
      requested_by: "test",
      input_snapshot_json: snapshot,
      agent_execution_generation: 1,
      agent_execution_token: "expired-worker",
      agent_execution_expires_at: 1.minute.ago
    )
    user_message = chat.messages.create!(role: "user", content: snapshot.fetch("prompt"))
    interrupted_attempt = run.attempts.create!(
      sequence: 1,
      provider: chat.provider,
      model_id: chat.model_id,
      status: :running,
      started_at: 10.seconds.ago,
      metadata_json: { "message_ids_before" => [ user_message.id ], "usage_ids_before" => [] }
    )
    placeholder = chat.messages.create!(role: "assistant", content: "")
    delivery = AgentRunDelivery.record!(run:, intent: "execute", expected_generation: 1)

    perform_enqueued_jobs do
      DeterministicRecoveryAgentRunJob.perform_later(*delivery.job_arguments)
    end

    assert run.reload.succeeded?, "#{run.status}: #{run.error_summary}"
    assert_equal [ "failed", "succeeded" ], run.attempts.order(:sequence).pluck(:status)
    assert_equal AgentRunJob::InterruptedStepError.name, interrupted_attempt.reload.error_class
    assert_not chat.messages.exists?(id: placeholder.id)
    assert_equal [ "Recovered after interruption." ], chat.messages.where(role: "assistant").pluck(:content)
    assert_equal 2, run.result_summary.fetch("agent_step_count")
  end

  test "keeps a Run cancelled when cancellation lands before step completion" do
    chat = create_chat(@project)
    snapshot = {
      "prompt" => "cancel while the step returns",
      "tools" => [],
      "tool_options" => {},
      "provider_tools" => [],
      "agent_definition" => {
        "id" => 45,
        "name" => "Cancellation checker",
        "revision" => 1,
        "provider" => chat.provider.to_s,
        "model_id" => chat.model_id.to_s,
        "instructions" => "Respect Run cancellation.",
        "tool_keys" => [],
        "provider_tools" => [],
        "options" => {}
      }
    }
    run = chat.runs.create!(
      project: @project,
      operation: "agent",
      status: :queued,
      requested_by: "test",
      input_snapshot_json: snapshot
    )
    delivery = AgentRunDelivery.record!(run:, intent: "execute", expected_generation: 0)

    perform_enqueued_jobs do
      DeterministicCancellationAgentRunJob.perform_later(*delivery.job_arguments)
    end

    assert run.reload.cancelled?
    assert_equal [ "cancelled" ], run.attempts.order(:sequence).pluck(:status)
    assert_empty run.artifacts.where(kind: "report")
    assert_not run.result_summary.key?("agent_step_count")
    assert_equal [ "Reply returned after cancellation." ], chat.messages.where(role: "assistant").pluck(:content)
    step_statuses = run.lifecycle_events.where(name: "ai.agent.step").map do |event|
      event.payload_json.fetch("step_status")
    end
    assert_equal [ "started" ], step_statuses
  end

  test "resumes approved and denied tool decisions through Agent Run delivery" do
    %w[approved denied].each do |decision|
      DeterministicApprovalAgentRunJob.received_arguments = []
      chat = create_chat(@project)
      tools_snapshot = Ai::ToolRegistry.snapshot(@project)
      tool_keys = tools_snapshot.map { |tool| tool.fetch("key") }
      snapshot = {
        "prompt" => "save a note",
        "tools" => tools_snapshot,
        "tool_options" => {},
        "provider_tools" => [],
        "agent_definition" => {
          "id" => 43,
          "name" => "Approval checker",
          "revision" => 1,
          "provider" => chat.provider.to_s,
          "model_id" => chat.model_id.to_s,
          "instructions" => "Save a note after approval.",
          "tool_keys" => tool_keys,
          "provider_tools" => [],
          "options" => {}
        }
      }
      run = chat.runs.create!(
        project: @project,
        operation: "agent",
        status: :queued,
        requested_by: "test",
        input_snapshot_json: snapshot
      )
      execution_delivery = AgentRunDelivery.record!(run:, intent: "execute", expected_generation: 0)

      perform_enqueued_jobs do
        DeterministicApprovalAgentRunJob.perform_later(*execution_delivery.job_arguments)
      end

      assert run.reload.waiting_for_approval?, "#{run.status}: #{run.error_summary} #{run.result_summary.inspect}"
      invocation = run.tool_invocations.find_by!(tool_key: "save_run_note")
      Ai::ApprovalService.decide!(invocation:, decision:, note: "Reviewed in test")
      approval_delivery = run.agent_run_deliveries.find_by!(intent: "approval")
      assert_equal [ run.id, "approval", invocation.id, run.agent_execution_generation ],
        approval_delivery.job_arguments

      perform_enqueued_jobs do
        DeterministicApprovalAgentRunJob.perform_later(*approval_delivery.job_arguments)
      end

      assert run.reload.succeeded?, "#{decision}: #{run.status} #{run.error_summary}"
      assert_equal 4, run.agent_execution_generation
      approval_arguments = DeterministicApprovalAgentRunJob.received_arguments
        .select { |arguments| arguments[1] == "approval" }
      assert_equal 2, approval_arguments.size
      assert_equal [ run.agent_execution_generation - 2, run.agent_execution_generation - 1 ],
        approval_arguments.map { |arguments| arguments[3] }
      assert_equal decision, invocation.approval.reload.status
      assert_equal(decision == "approved" ? "succeeded" : "denied", invocation.reload.status)
      assert_equal 2, run.result_summary.fetch("agent_step_count")
      report = run.artifacts.where(kind: "report").find do |artifact|
        artifact.metadata_json.to_h["report_type"] == "agent_research_report"
      end
      assert report, "expected a durable Agent research report"
      if decision == "approved"
        assert_equal "Approved note", run.artifacts.find_by!(source_tool_call_id: invocation.tool_call_id).content_text
      else
        assert_empty run.artifacts.where(source_tool_call_id: invocation.tool_call_id)
      end
    end
  end

  test "resumes approved and denied provider-hosted MCP calls through Agent Run delivery" do
    openai_model = RubyLLM.models.chat_models.to_a.find { |candidate| candidate.provider == "openai" }
    assert openai_model, "expected RubyLLM's OpenAI model registry entry"
    model = RubyLLM::ActiveRecord::Model.find_or_create_by!(
      model_id: openai_model.id,
      provider: openai_model.provider
    ) do |record|
      record.assign_attributes(
        name: openai_model.name,
        family: openai_model.family,
        model_created_at: openai_model.created_at,
        context_window: openai_model.context_window,
        max_output_tokens: openai_model.max_output_tokens,
        knowledge_cutoff: openai_model.knowledge_cutoff,
        modalities: openai_model.modalities.to_h,
        capabilities: openai_model.capabilities,
        pricing: openai_model.pricing.to_h,
        metadata: openai_model.metadata
      )
    end

    %w[approved denied].each do |decision|
      remote_chat = Chat.create!(project: @project, model:)
      snapshot = {
        "prompt" => "Search the official documentation.",
        "tools" => [],
        "tool_options" => {},
        "provider_tools" => [],
        "agent_definition" => {
          "id" => 44,
          "name" => "Hosted approval checker",
          "revision" => 1,
          "provider" => "openai",
          "model_id" => model.model_id,
          "instructions" => "Continue after the hosted approval decision.",
          "tool_keys" => [],
          "provider_tools" => [],
          "options" => {}
        }
      }
      run = remote_chat.runs.create!(
        project: @project,
        operation: "agent",
        status: :waiting_for_approval,
        requested_by: "test",
        input_snapshot_json: snapshot
      )
      attempt = run.attempts.create!(
        sequence: 1,
        provider: "openai",
        model_id: model.model_id,
        status: :succeeded
      )
      remote_chat.messages.create!(role: "user", content: snapshot.fetch("prompt"))
      assistant = remote_chat.messages.create!(role: "assistant", content: "Checking the official source.")
      tool_call = RubyLLM::ActiveRecord::ToolCall.create!(
        message: assistant,
        tool_call_id: "mcp-approval-#{decision}-#{SecureRandom.hex(4)}",
        name: "documentation_search",
        arguments: { "query" => "RubyLLM Responses approval" },
        remote: true
      )
      Ai::ToolInvocationRecorder.new(run:, chat: remote_chat, attempt:).sync!
      invocation = run.tool_invocations.find_by!(tool_call_id: tool_call.tool_call_id)
      run.update!(result_summary_json: {
        "pending_tool_calls" => [ invocation.tool_key ],
        "pending_tool_call_ids" => [ invocation.id ]
      })
      assert invocation.waiting_for_approval?
      assert invocation.remote?

      Ai::ApprovalService.decide!(invocation:, decision:, note: "Reviewed hosted request")
      delivery = run.agent_run_deliveries.find_by!(intent: "approval")
      assert_equal [ run.id, "approval", invocation.id, run.agent_execution_generation ], delivery.job_arguments

      with_provider_configuration("openai") do
        perform_enqueued_jobs do
          DeterministicRemoteApprovalAgentRunJob.perform_later(*delivery.job_arguments)
        end
      end

      assert run.reload.succeeded?, "#{decision}: #{run.status} #{run.error_summary}"
      assert_equal decision, invocation.approval.reload.status
      assert_equal(decision == "approved" ? "succeeded" : "denied", invocation.reload.status)
      assert_equal 1, remote_chat.messages.where(role: "user", content: snapshot.fetch("prompt")).count
      assert tool_call.reload.result_id
      protocol_result = remote_chat.messages.find(tool_call.result_id)
      assert_equal "tool", protocol_result.role
      assert_includes protocol_result.raw_content.to_json, "mcp_approval_response"
      assert_includes protocol_result.raw_content.to_json, %Q("approve":#{decision == "approved"})
      assert_equal 1, run.artifacts.where(kind: "report").count
      assert_equal 2, run.result_summary.fetch("agent_step_count")
    end
  end

  test "failure atomically expires local and remote approvals without executing tools" do
    model = openai_model_record
    chat = Chat.create!(project: @project, model:)
    run = chat.runs.create!(
      project: @project,
      operation: "agent",
      status: :queued,
      requested_by: "test",
      input_snapshot_json: {
        "prompt" => "make two approval requests",
        "tools" => Ai::ToolRegistry.snapshot(@project),
        "agent_definition" => {
          "id" => 991,
          "name" => "Failing approval checker",
          "revision" => 1,
          "provider" => "openai",
          "model_id" => model.model_id,
          "instructions" => "Request approval before acting.",
          "tool_keys" => [],
          "provider_tools" => [],
          "options" => {}
        }
      }
    )

    with_provider_configuration("openai") do
      perform_enqueued_jobs do
        FailingApprovalAgentRunJob.perform_later(run.id)
      end
    end

    invocations = run.tool_invocations.order(:tool_call_id).to_a
    assert run.reload.failed?, "#{run.status}: #{run.error_summary}"
    assert_equal %w[failed failed], invocations.map(&:status).sort,
      "#{run.error_summary}: #{run.result_summary.inspect}"
    assert_equal %w[expired expired], invocations.map { |invocation| invocation.approval.reload.status }.sort
    assert invocations.all? { |invocation| invocation.approval.decided_at.present? }
    assert_equal 0, run.agent_run_deliveries.where(intent: "approval").count
    assert_equal 0, run.artifacts.count

    tool_calls = RubyLLM::ActiveRecord::ToolCall.where(
      message_type: Message.polymorphic_name,
      message_id: chat.messages.select(:id)
    ).index_by(&:name)
    local_call = tool_calls.fetch("save_run_note")
    remote_call = tool_calls.fetch("web_search")
    assert_equal "denied", local_call.approval
    assert_equal "denied", remote_call.approval
    assert local_call.result_id
    assert remote_call.result_id

    local_result = chat.messages.find(local_call.result_id)
    assert_includes local_result.content, "failed before this tool call was executed"
    remote_result = chat.messages.find(remote_call.result_id)
    assert_equal "Denied", remote_result.content
    assert_includes remote_result.raw_content.to_json, "mcp_approval_response"
    assert_includes remote_result.raw_content.to_json, '"approve":false'
    assert_equal 0, run.tool_invocations.waiting_for_approval.count
  end

  private

  def openai_model_record
    model_info = RubyLLM.models.chat_models.to_a.find { |candidate| candidate.provider == "openai" }
    RubyLLM::ActiveRecord::Model.find_or_create_by!(model_id: model_info.id, provider: model_info.provider) do |record|
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
  end
end

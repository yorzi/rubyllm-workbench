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
      if decision == "approved"
        assert_equal "Approved note", run.artifacts.find_by!(source_tool_call_id: invocation.tool_call_id).content_text
      else
        assert_empty run.artifacts.where(kind: "report")
      end
    end
  end
end

require "test_helper"

class AgentRunDeliveryDispatcherJobTest < ActiveSupport::TestCase
  class TerminalRunGuardAgentJob < AgentRunJob
    class << self
      attr_accessor :restore_calls
    end

    private

    def restore_agent
      self.class.restore_calls = self.class.restore_calls.to_i + 1
    end
  end

  setup do
    @project = create_project(name: "Agent dispatcher project")
    @chat = create_chat(@project)
    @job = AgentRunDeliveryDispatcherJob.new
  end

  test "recovers queued and expired Agent Runs into durable execute deliveries" do
    queued_run = create_agent_run(status: :queued, generation: 0)
    expired_run = create_agent_run(status: :running, generation: 3, token: "dead-worker", expires_at: 1.minute.ago)

    @job.send(:recover_unclaimed_runs)

    assert_equal 2, AgentRunDelivery.where(run_id: [ queued_run.id, expired_run.id ], intent: "execute").count
    assert_equal [ 0, 3 ], AgentRunDelivery.where(run_id: [ queued_run.id, expired_run.id ])
      .order(:run_id).pluck(:expected_generation)
  end

  test "waits for every pending approval before recovering an Agent Run" do
    run = create_agent_run(status: :waiting_for_approval, generation: 2)
    first = create_invocation(run, "call-first", "approved")
    second = create_invocation(run, "call-second", "waiting_for_approval")
    run.update!(result_summary_json: { "pending_tool_call_ids" => [ first.id, second.id ] })
    first.approval.update!(status: "approved", decided_at: Time.current)

    @job.send(:recover_ready_approvals)

    assert_not AgentRunDelivery.where(run:, intent: "approval").exists?

    second.update!(status: "denied")
    second.approval.update!(status: "denied", decided_at: Time.current)
    @job.send(:recover_ready_approvals)

    delivery = AgentRunDelivery.find_by!(run:, intent: "approval")
    assert_equal first.id, delivery.approval_invocation_id
    assert_equal 2, delivery.expected_generation
  end

  test "marks a delivery dispatched only after the Agent job accepts enqueue" do
    run = create_agent_run(status: :queued, generation: 0)
    delivery = AgentRunDelivery.record!(run:, intent: "execute", expected_generation: 0)
    job_arguments = nil
    job = Object.new
    job.define_singleton_method(:enqueue) { true }

    job_arguments = with_agent_job_constructor(job) do
      @job.send(:dispatch, delivery.id)
    end

    assert_equal [ run.id, "execute", nil, 0 ], job_arguments
    assert delivery.reload.delivered_at
    assert_equal 0, delivery.dispatch_attempts
  end

  test "retains a delivery for retry when the Agent queue rejects enqueue" do
    run = create_agent_run(status: :queued, generation: 0)
    delivery = AgentRunDelivery.record!(run:, intent: "execute", expected_generation: 0)
    job = Object.new
    job.define_singleton_method(:enqueue) { false }
    job.define_singleton_method(:enqueue_error) { IOError.new("queue unavailable") }

    with_agent_job_constructor(job) do
      @job.send(:dispatch, delivery.id)
    end

    assert_equal 1, delivery.reload.dispatch_attempts
    assert_equal "IOError", delivery.last_error_class
    assert_nil delivery.delivered_at
  end

  test "re-enqueues after an accepted enqueue loses its outbox acknowledgement" do
    run = create_agent_run(status: :queued, generation: 0)
    delivery = AgentRunDelivery.record!(run:, intent: "execute", expected_generation: 0)
    job = Object.new
    enqueue_attempts = 0
    job.define_singleton_method(:enqueue) { enqueue_attempts += 1; true }
    original_mark_delivered = AgentRunDelivery.instance_method(:mark_delivered!)
    AgentRunDelivery.define_method(:mark_delivered!) do |token:, now: Time.current|
      original_mark_delivered.bind(self).call(token:, now: now + AgentRunDelivery::CLAIM_DURATION + 1.second)
    end

    begin
      first_job_arguments = with_agent_job_constructor(job) do
        @job.send(:dispatch, delivery.id)
      end
    ensure
      AgentRunDelivery.define_method(:mark_delivered!, original_mark_delivered)
    end

    assert_nil delivery.reload.delivered_at
    assert delivery.claimed_until.future?
    delivery.update_columns(claimed_until: 1.second.ago)

    second_job_arguments = with_agent_job_constructor(job) do
      @job.send(:dispatch, delivery.id)
    end

    assert_equal first_job_arguments, second_job_arguments
    assert delivery.reload.delivered_at
    assert_equal 0, delivery.dispatch_attempts
    assert_equal 2, enqueue_attempts

    assert run.claim_agent_execution!(token: "first-delivery", expected_generation: first_job_arguments.fetch(3))
    assert_not run.claim_agent_execution!(token: "duplicate-delivery", expected_generation: second_job_arguments.fetch(3))
    run.reload
    generation = run.agent_execution_generation
    report = nil
    succeeded = run.succeed!({ "answer" => "one execution" }, agent_execution_token: "first-delivery",
      agent_execution_generation: generation) do
      report = run.artifacts.create!(
        kind: "report",
        name: "One durable report",
        content_text: "one execution",
        metadata_json: {}
      )
      { "report_artifact_id" => report.id }
    end
    assert succeeded

    assert_not run.claim_agent_execution!(token: "late-duplicate-delivery", expected_generation: second_job_arguments.fetch(3))
    assert_equal 1, run.artifacts.where(kind: "report", name: "One durable report").count
    assert_equal report.id, run.reload.result_summary.fetch("report_artifact_id")

    TerminalRunGuardAgentJob.restore_calls = 0
    TerminalRunGuardAgentJob.perform_now(*second_job_arguments)
    assert_equal 0, TerminalRunGuardAgentJob.restore_calls
    assert_equal 1, run.reload.artifacts.where(kind: "report", name: "One durable report").count
  end

  private

  def with_agent_job_constructor(job)
    singleton = AgentRunJob.singleton_class
    had_constructor = singleton.instance_methods(false).include?(:new)
    original_constructor = singleton.instance_method(:new) if had_constructor
    arguments = nil
    singleton.define_method(:new) do |*job_arguments|
      arguments = job_arguments
      job
    end
    yield
    arguments
  ensure
    if had_constructor
      singleton.define_method(:new, original_constructor)
    else
      singleton.remove_method(:new)
    end
  end

  def create_agent_run(status:, generation:, token: nil, expires_at: nil)
    @chat.runs.create!(
      project: @project,
      operation: "agent",
      status: status,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "resume task" },
      agent_execution_generation: generation,
      agent_execution_token: token,
      agent_execution_expires_at: expires_at
    )
  end

  def create_invocation(run, call_id, status)
    invocation = run.tool_invocations.create!(tool_call_id: call_id, tool_key: "save_run_note", status: status)
    invocation.create_approval!(status: "pending", requested_at: Time.current)
    invocation
  end
end

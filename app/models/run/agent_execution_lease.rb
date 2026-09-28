# A durable, expiring execution lease for Agent Runs. The worker that claims
# the lease owns the Run's transcript, usage and local tool writes until it
# expires; each claim increments the generation so stale or duplicate job
# deliveries are fenced out.
module Run::AgentExecutionLease
  extend ActiveSupport::Concern

  # Acquire one durable execution lease for a worker. Continuation resumes use
  # a fresh token, while duplicate deliveries cannot pass the same live claim.
  def claim_agent_execution!(token:, intent: "execute", approval_invocation_id: nil, expected_generation: nil,
                             lease_duration: Run::AGENT_EXECUTION_LEASE_DURATION)
    claimed = false
    with_lock do
      reload
      return false if terminal?
      return false unless claim_permitted?(intent, approval_invocation_id, expected_generation)

      now = Time.current
      lease_active = agent_execution_token.present? && agent_execution_expires_at&.future?
      return false if lease_active

      was_waiting_for_approval = waiting_for_approval?
      first_start = started_at.nil?

      update!(
        agent_execution_token: token,
        agent_execution_expires_at: now + lease_duration,
        agent_execution_generation: agent_execution_generation.to_i + 1,
        status: :running,
        started_at: started_at || now,
        finished_at: nil
      )
      if first_start
        record_lifecycle_event("ai.run.started", attempt_id: current_attempt_id)
      elsif was_waiting_for_approval
        record_lifecycle_event("ai.run.resumed", attempt_id: current_attempt_id)
      end
      claimed = true
    end
    claimed
  end

  def renew_agent_execution_lease!(token:, generation:, lease_duration: Run::AGENT_EXECUTION_LEASE_DURATION)
    renewed = false
    with_lock do
      reload
      return false if terminal?
      return false unless owns_active_agent_execution_lease?(token, generation:)

      # Lease heartbeats are control metadata; do not broadcast the Run status
      # or touch updated_at on every renewal.
      update_column(:agent_execution_expires_at, Time.current + lease_duration)
      renewed = true
    end
    renewed
  end

  def release_agent_execution_lease!(token:, generation:)
    with_lock do
      reload
      return false unless agent_execution_token == token && agent_execution_generation == generation

      update!(agent_execution_token: nil, agent_execution_expires_at: nil)
    end
    true
  end

  def owns_active_agent_execution_lease?(token, generation: nil)
    agent_execution_token == token &&
      (generation.nil? || agent_execution_generation == generation) &&
      agent_execution_expires_at&.future?
  end

  # Caller must hold this Run's row lock when the lease protects a side effect.
  def assert_agent_execution_lease!(token:, generation:)
    return self if owns_active_agent_execution_lease?(token, generation:)

    raise Ai::ExecutionContext::ExecutionLeaseLost, "the worker no longer owns this Run"
  end

  # True when every pending approval of a waiting Agent Run is decided and an
  # approval continuation delivery exists.
  def agent_continuation_queued?
    return false unless operation == "agent" && waiting_for_approval?

    pending_tool_call_ids = Array(result_summary["pending_tool_call_ids"]).filter_map do |value|
      Integer(value.to_s, exception: false)
    end.uniq
    return false if pending_tool_call_ids.empty?
    return false unless agent_run_deliveries.where(intent: "approval").exists?

    invocations = tool_invocations.where(id: pending_tool_call_ids).includes(:approval).index_by(&:id)
    pending_tool_call_ids.all? do |invocation_id|
      invocation = invocations[invocation_id]
      invocation && %w[approved denied].include?(invocation.status) && invocation.approval&.status == invocation.status
    end
  end

  private

  # A terminal transition that names a lease token is accepted only from the
  # worker that still owns that lease. Transitions without a token (user or
  # system actions) are not fenced.
  def foreign_agent_execution?(token, generation)
    !token.nil? && !owns_active_agent_execution_lease?(token, generation:)
  end

  def claim_permitted?(intent, approval_invocation_id, expected_generation)
    case intent.to_s
    when "execute"
      (queued? || running?) && (expected_generation.nil? || expected_generation.to_i == agent_execution_generation.to_i)
    when "approval"
      approval_invocation = tool_invocations.find_by(id: approval_invocation_id) if approval_invocation_id
      pending_invocation_ids = Array(result_summary["pending_tool_call_ids"]).map(&:to_i)

      (waiting_for_approval? || running?) &&
        decided_approval?(approval_invocation) &&
        pending_invocation_ids.any? &&
        pending_invocation_ids.all? { |invocation_id| decided_approval?(tool_invocations.find_by(id: invocation_id)) } &&
        expected_generation.to_i == agent_execution_generation.to_i &&
        pending_invocation_ids.include?(approval_invocation.id)
    else
      false
    end
  end

  def decided_approval?(invocation)
    invocation.present? && %w[approved denied].include?(invocation.status) &&
      invocation.approval&.status == invocation.status
  end
end

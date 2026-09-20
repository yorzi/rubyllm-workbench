class AgentRunDeliveryDispatcherJob < ApplicationJob
  queue_as :maintenance

  DISPATCH_BATCH_SIZE = 50
  RECOVERY_BATCH_SIZE = 100
  RECOVERY_INTERVAL = 5.minutes

  def perform
    recover_unclaimed_runs
    recover_ready_approvals
    AgentRunDelivery.ready_to_dispatch.limit(DISPATCH_BATCH_SIZE).pluck(:id).each do |delivery_id|
      dispatch(delivery_id)
    end
  end

  private

  def recover_unclaimed_runs
    now = Time.current
    Run.where(operation: "agent", status: %w[queued running])
      .where("agent_execution_token IS NULL OR agent_execution_expires_at IS NULL OR agent_execution_expires_at <= ?", now)
      .find_each(batch_size: RECOVERY_BATCH_SIZE) do |run|
        run.with_lock do
          run.reload
          next unless run.operation == "agent" && (run.queued? || run.running?)
          next if run.agent_execution_token.present? && run.agent_execution_expires_at&.future?

          generation = run.agent_execution_generation.to_i
          next if recently_delivered_or_pending?(run, intent: "execute", generation:, now:)

          window = now.to_i / RECOVERY_INTERVAL.to_i
          recovery_kind = run.queued? ? "queued" : "expired-lease"
          AgentRunDelivery.record!(
            run:,
            intent: "execute",
            expected_generation: generation,
            available_at: now,
            dedupe_key: "recovery:#{recovery_kind}:#{run.id}:#{generation}:#{window}"
          )
        end
      end
  end

  def recover_ready_approvals
    now = Time.current
    Run.where(operation: "agent", status: "waiting_for_approval")
      .find_each(batch_size: RECOVERY_BATCH_SIZE) do |run|
        run.with_lock do
          run.reload
          next unless run.operation == "agent" && run.waiting_for_approval?

          pending_ids = Array(run.result_summary["pending_tool_call_ids"]).map(&:to_i).uniq
          next if pending_ids.empty?

          decided = run.tool_invocations.where(id: pending_ids, status: %w[approved denied]).includes(:approval).to_a
          next unless decided.size == pending_ids.size
          next unless decided.all? { |invocation| invocation.approval&.status == invocation.status }
          next if recently_delivered_or_pending?(run, intent: "approval", generation: run.agent_execution_generation, now:)

          window = now.to_i / RECOVERY_INTERVAL.to_i
          invocation = decided.min_by(&:id)
          AgentRunDelivery.record!(
            run:,
            intent: "approval",
            approval_invocation_id: invocation.id,
            expected_generation: run.agent_execution_generation,
            available_at: now,
            dedupe_key: "recovery:approval:#{run.id}:#{run.agent_execution_generation}:#{window}"
          )
        end
      end
  end

  def recently_delivered_or_pending?(run, intent:, generation:, now:)
    run.agent_run_deliveries.where(intent:, expected_generation: generation)
      .where("delivered_at IS NULL OR created_at >= ?", now - RECOVERY_INTERVAL).exists?
  end

  def dispatch(delivery_id)
    delivery = AgentRunDelivery.find_by(id: delivery_id)
    return unless delivery

    claim_token = delivery.claim_for_dispatch!
    return unless claim_token

    job = AgentRunJob.new(*delivery.job_arguments)
    unless job.enqueue
      enqueue_error = job.enqueue_error || StandardError.new("Active Job enqueue was not accepted")
      delivery.retry_dispatch!(token: claim_token, error: enqueue_error)
      Rails.logger.warn("Agent Run delivery ##{delivery.id} will retry after #{enqueue_error.class}")
      return
    end

    unless delivery.mark_delivered!(token: claim_token)
      Rails.logger.warn("Agent Run delivery ##{delivery.id} was enqueued after its dispatch claim expired")
    end
  rescue StandardError => error
    delivery&.retry_dispatch!(token: claim_token, error:) if claim_token
    Rails.logger.error("Agent Run delivery ##{delivery_id} failed: #{error.class}: #{error.message}")
  end
end

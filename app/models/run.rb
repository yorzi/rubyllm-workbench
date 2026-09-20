class Run < ApplicationRecord
  STATUSES = %w[queued running waiting_for_approval succeeded failed cancelled].freeze
  AGENT_EXECUTION_LEASE_DURATION = 5.minutes

  belongs_to :project
  belongs_to :chat
  belongs_to :experiment, optional: true
  belongs_to :experiment_execution, optional: true
  has_many :attempts, -> { order(:sequence, :id) }, dependent: :destroy
  has_many :artifacts, dependent: :destroy
  has_many :tool_invocations, dependent: :destroy
  has_many :agent_run_deliveries, dependent: :destroy
  has_many :lifecycle_events, -> { chronological }, dependent: :destroy

  after_create :record_created_event
  after_create_commit :broadcast_status
  after_update_commit :broadcast_status

  enum :status, STATUSES.index_with(&:itself), validate: true

  validates :operation, presence: true
  validates :requested_by, presence: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def input_snapshot
    input_snapshot_json || {}
  end

  def result_summary
    result_summary_json || {}
  end

  def experiment?
    experiment.present?
  end

  def duration_ms
    return unless started_at

    (((finished_at || Time.current) - started_at).to_f * 1_000).round
  end

  def total_tokens
    columns = %i[input_tokens output_tokens cache_read_tokens cache_write_tokens thinking_tokens]
    rows = attempts.pluck(*columns)

    %i[input output cache_read cache_write thinking].each_with_index.to_h do |field, index|
      [ field, rows.sum { |row| (row[index] || 0).to_i } ]
    end
  end

  def total_cost
    values = attempts.filter_map do |attempt|
      next if attempt.cost_status == "unknown"

      attempt.reported_cost || attempt.estimated_cost
    end
    values.sum if values.any?
  end

  def cost_status
    return "unknown" if attempts.empty?
    return "unknown" if attempts.any? { |attempt| attempt.cost_status == "unknown" }
    return "estimated" if attempts.any? { |attempt| attempt.cost_status == "estimated" }

    "reported"
  end

  def terminal?
    succeeded? || failed? || cancelled?
  end

  def stream_key
    chat.stream_key
  end

  def start!
    with_lock do
      reload
      return self if terminal?

      was_waiting_for_approval = waiting_for_approval?
      first_start = started_at.nil?
      update!(status: :running, started_at: started_at || Time.current)
      if first_start
        record_lifecycle_event("ai.run.started", attempt_id: current_attempt_id)
      elsif was_waiting_for_approval
        record_lifecycle_event("ai.run.resumed", attempt_id: current_attempt_id)
      end
    end
    self
  end

  def wait_for_approval!(summary = {}, attempt_id: nil, agent_execution_token: nil, agent_execution_generation: nil)
    accepted = true
    with_lock do
      reload
      return self if terminal?
      unless agent_execution_token.nil? || owns_active_agent_execution_lease?(
        agent_execution_token,
        generation: agent_execution_generation
      )
        accepted = false
        next
      end

      update!(
        status: :waiting_for_approval,
        finished_at: nil,
        result_summary_json: summary,
        agent_execution_token: nil,
        agent_execution_expires_at: nil
      )
      record_lifecycle_event("ai.run.waiting_for_approval", attempt_id: attempt_id)
    end
    accepted ? self : false
  end

  def succeed!(summary = nil, agent_execution_token: nil, agent_execution_generation: nil, **summary_fields)
    summary = (summary || {}).to_h.deep_stringify_keys.merge(summary_fields.deep_stringify_keys)
    accepted = true
    with_lock do
      reload
      return self if terminal?
      unless agent_execution_token.nil? || owns_active_agent_execution_lease?(
        agent_execution_token,
        generation: agent_execution_generation
      )
        accepted = false
        next
      end

      update!(
        status: :succeeded,
        finished_at: Time.current,
        result_summary_json: summary,
        agent_execution_token: nil,
        agent_execution_expires_at: nil
      )
      record_lifecycle_event("ai.run.succeeded")
    end
    accepted ? self : false
  end

  def fail!(error, summary: {}, agent_execution_token: nil, agent_execution_generation: nil)
    failure_summary = { "failure_kind" => Ai::ErrorClassifier.code(error) }
    accepted = true
    with_lock do
      reload
      return self if terminal?
      unless agent_execution_token.nil? || owns_active_agent_execution_lease?(
        agent_execution_token,
        generation: agent_execution_generation
      )
        accepted = false
        next
      end

      update!(
        status: :failed,
        finished_at: Time.current,
        error_summary: error_message_for(error),
        result_summary_json: result_summary.merge(failure_summary).merge(summary),
        agent_execution_token: nil,
        agent_execution_expires_at: nil
      )
      record_lifecycle_event(
        "ai.run.failed",
        error_class: error.class.name,
        error_code: Ai::ErrorClassifier.code(error),
        failure_kind: failure_summary.fetch("failure_kind")
      )
    end
    accepted ? self : false
  end

  def cancel!
    with_lock do
      reload
      return self if terminal?

      chat.cancel if chat.respond_to?(:cancel)
      now = Time.current
      attempts.where(status: %w[queued running]).find_each do |attempt|
        attempt.finish!(status: :cancelled, finished_at: now)
      end
      update!(
        status: :cancelled,
        finished_at: now,
        agent_execution_token: nil,
        agent_execution_expires_at: nil
      )
      record_lifecycle_event("ai.run.cancelled", attempt_id: current_attempt_id)
    end
    self
  end

  # Acquire one durable execution lease for a worker. Continuation resumes use
  # a fresh token, while duplicate deliveries cannot pass the same live claim.
  def claim_agent_execution!(token:, intent: "execute", approval_invocation_id: nil, expected_generation: nil,
                             lease_duration: AGENT_EXECUTION_LEASE_DURATION)
    claimed = false
    with_lock do
      reload
      return false if terminal?

      approval_invocation = tool_invocations.find_by(id: approval_invocation_id) if approval_invocation_id
      approval_decided = approval_invocation && %w[approved denied].include?(approval_invocation.status) &&
        approval_invocation.approval&.status == approval_invocation.status
      permitted_state = case intent.to_s
      when "execute"
        (queued? || running?) && (expected_generation.nil? || expected_generation.to_i == agent_execution_generation.to_i)
      when "approval"
        if waiting_for_approval?
          pending_invocation_ids = Array(result_summary["pending_tool_call_ids"]).map(&:to_i)
          all_approvals_decided = pending_invocation_ids.any? && pending_invocation_ids.all? do |invocation_id|
            invocation = tool_invocations.find_by(id: invocation_id)
            invocation && %w[approved denied].include?(invocation.status) &&
              invocation.approval&.status == invocation.status
          end
          approval_decided && all_approvals_decided &&
            expected_generation.to_i == agent_execution_generation.to_i &&
            pending_invocation_ids.include?(approval_invocation.id)
        else
          pending_invocation_ids = Array(result_summary["pending_tool_call_ids"]).map(&:to_i)
          all_approvals_decided = pending_invocation_ids.any? && pending_invocation_ids.all? do |invocation_id|
            invocation = tool_invocations.find_by(id: invocation_id)
            invocation && %w[approved denied].include?(invocation.status) &&
              invocation.approval&.status == invocation.status
          end
          running? && approval_decided && all_approvals_decided && pending_invocation_ids.include?(approval_invocation.id)
        end
      else
        false
      end
      return false unless permitted_state

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

  def renew_agent_execution_lease!(token:, generation:, lease_duration: AGENT_EXECUTION_LEASE_DURATION)
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

  def inspector_path
    Rails.application.routes.url_helpers.run_path(self)
  end

  private

  def record_created_event
    record_lifecycle_event("ai.run.created")
  end

  def record_lifecycle_event(event_name, **payload)
    event_payload = {
      run_id: id,
      project_id: project_id,
      operation: operation,
      status: status
    }.merge(payload)
    event_payload[:event_key] = lifecycle_event_key(event_name, event_payload)

    Ai::LifecycleEventRecorder.emit(
      event_name,
      event_payload
    )
  end

  def current_attempt_id
    attempts.reorder(sequence: :desc, id: :desc).pick(:id)
  end

  def lifecycle_event_key(event_name, payload)
    base = "run:#{id}:#{event_name.delete_prefix('ai.run.')}"
    attempt_id = payload[:attempt_id] || payload["attempt_id"]
    attempt_id.present? ? "#{base}:attempt:#{attempt_id}" : base
  end

  def error_message_for(error)
    return error.to_s if error.is_a?(String)

    [ error.class.name, redact(error.message) ].compact.join(": ").truncate(2_000)
  end

  def broadcast_status
    return unless defined?(Turbo::StreamsChannel)

    Turbo::StreamsChannel.broadcast_replace_to(
      stream_key,
      target: "run_#{id}_status",
      partial: "runs/status",
      locals: { run: self }
    )
  rescue StandardError => error
    Rails.logger.warn("Run status broadcast failed: #{error.class}: #{error.message}")
  end

  def redact(message)
    Ai::ErrorText.redact(message)
  end
end

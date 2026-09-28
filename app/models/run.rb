class Run < ApplicationRecord
  STATUSES = %w[queued running waiting_for_approval succeeded failed cancelled].freeze
  ACTIVE_STATUSES = %w[queued running waiting_for_approval].freeze
  AGENT_EXECUTION_LEASE_DURATION = 5.minutes

  belongs_to :project
  belongs_to :chat
  belongs_to :experiment, optional: true
  belongs_to :experiment_execution, optional: true
  has_one :evaluation_case_result, dependent: :nullify
  has_one :evaluation_case_judgment, dependent: :destroy
  has_many :artifacts, dependent: :destroy
  has_many :agent_run_deliveries, dependent: :destroy
  has_many :tool_invocations, dependent: :destroy
  has_many :attempts, -> { order(:sequence, :id) }, dependent: :destroy
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

  def claim_queued_execution!(operation:)
    claimed = false
    with_lock do
      reload
      next unless queued? && self.operation == operation.to_s

      first_start = started_at.nil?
      update!(status: :running, started_at: started_at || Time.current)
      record_lifecycle_event("ai.run.started", attempt_id: current_attempt_id) if first_start
      claimed = true
    end
    claimed
  end

  # Finish a non-Agent queued execution only while the worker still owns the
  # active Run state. The caller's writes share this row lock and transaction,
  # so a concurrent cancellation cannot leave a succeeded Attempt or Artifact
  # attached to a cancelled Run.
  def finish_running_execution!(operation:, status:, summary: {}, error: nil, started_before: nil)
    finished = false
    with_lock do
      reload
      next unless running? && self.operation == operation.to_s
      next if started_before && (started_at.nil? || started_at > started_before)

      completion_summary = yield if block_given?
      case status.to_s
      when "succeeded"
        update!(
          status: :succeeded,
          finished_at: Time.current,
          result_summary_json: (completion_summary || summary).deep_stringify_keys,
          agent_execution_token: nil,
          agent_execution_expires_at: nil
        )
        record_lifecycle_event("ai.run.succeeded", operation: operation.to_s)
      when "failed"
        raise ArgumentError, "an error is required for a failed execution" unless error

        failure_summary = { "failure_kind" => Ai::ErrorClassifier.code(error) }
        update!(
          status: :failed,
          finished_at: Time.current,
          error_summary: error_message_for(error),
          result_summary_json: result_summary.merge(failure_summary).merge(summary.deep_stringify_keys),
          agent_execution_token: nil,
          agent_execution_expires_at: nil
        )
        record_lifecycle_event(
          "ai.run.failed",
          error_class: error.class.name,
          error_code: Ai::ErrorClassifier.code(error),
          failure_kind: failure_summary.fetch("failure_kind")
        )
      else
        raise ArgumentError, "unsupported execution status: #{status}"
      end
      finished = true
    end
    finished ? self : false
  end

  def fail_queued_execution!(operation:, error:, summary: {})
    failure_summary = { "failure_kind" => Ai::ErrorClassifier.code(error) }
    failed = false
    with_lock do
      reload
      next unless queued? && self.operation == operation.to_s

      yield if block_given?
      update!(
        status: :failed,
        finished_at: Time.current,
        error_summary: error_message_for(error),
        result_summary_json: with_conversation_message_end_id(
          result_summary.merge(failure_summary).merge(summary.deep_stringify_keys)
        ),
        agent_execution_token: nil,
        agent_execution_expires_at: nil
      )
      record_lifecycle_event(
        "ai.run.failed",
        error_class: error.class.name,
        error_code: Ai::ErrorClassifier.code(error),
        failure_kind: failure_summary.fetch("failure_kind")
      )
      failed = true
    end
    failed ? self : false
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
        result_summary_json: with_conversation_message_end_id(summary),
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

      success_artifact_summary = yield if block_given?
      if success_artifact_summary.is_a?(Hash)
        summary = summary.merge(success_artifact_summary.deep_stringify_keys)
      end
      summary = with_conversation_message_end_id(summary)

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

      finalize_failed_tool_approvals!(error)
      failure_summary = with_conversation_message_end_id(result_summary.merge(failure_summary).merge(summary))
      update!(
        status: :failed,
        finished_at: Time.current,
        error_summary: error_message_for(error),
        result_summary_json: failure_summary,
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

      pending_tool_approvals = pending_tool_approval_invocations
      if running? && pending_tool_approvals.empty? && operation.in?(%w[agent chat]) && chat.respond_to?(:cancel)
        chat.cancel
      end
      resolve_pending_tool_approvals!(pending_tool_approvals)

      now = Time.current
      attempts.where(status: %w[queued running]).find_each do |attempt|
        attempt.finish!(status: :cancelled, finished_at: now)
      end
      update!(
        status: :cancelled,
        finished_at: now,
        result_summary_json: with_conversation_message_end_id(result_summary),
        agent_execution_token: nil,
        agent_execution_expires_at: nil
      )
      cancel_active_tool_invocations!(now)
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
          running? && approval_decided && all_approvals_decided &&
            expected_generation.to_i == agent_execution_generation.to_i &&
            pending_invocation_ids.include?(approval_invocation.id)
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

  def with_conversation_message_end_id(summary)
    return summary unless operation == "chat"

    end_id = chat.messages.maximum(:id) || input_snapshot["conversation_message_high_watermark"] || 0
    summary.deep_stringify_keys.merge("conversation_message_end_id" => end_id)
  end

  def record_created_event
    record_lifecycle_event("ai.run.created")
  end

  def cancel_active_tool_invocations!(now)
    tool_invocations
      .where(status: %w[requested waiting_for_approval approved running])
      .includes(:approval)
      .order(:id)
      .each do |invocation|
        approval = invocation.approval
        if invocation.status.in?(%w[requested waiting_for_approval approved])
          chat.deny(invocation.tool_call_id)
        end

        if approval&.pending?
          approval.update!(
            status: :expired,
            decided_at: now,
            decision_note: "Run cancelled before approval was decided."
          )
          Ai::LifecycleEventRecorder.emit(
            "ai.approval.expired",
            run_id: id,
            project_id: project_id,
            attempt_id: invocation.attempt_id,
            tool_invocation_id: invocation.id,
            approval_id: approval.id,
            status: approval.status,
            actor: "system",
            event_key: "approval:#{approval.id}:expired"
          )
        end

        cancellation_message = if invocation.status == "running"
          "Run cancelled while the tool action was in progress; its outcome may be unknown."
        else
          "Run cancelled before the tool action started."
        end
        invocation.update!(
          status: :cancelled,
          finished_at: now,
          duration_ms: invocation.started_at ? ((now - invocation.started_at) * 1_000).round : nil,
          error_class: "RunCancellation",
          error_code: invocation.remote? && invocation.status == "running" ? "remote_tool_outcome_unknown" : "run_cancelled",
          error_message: cancellation_message
        )
        Ai::LifecycleEventRecorder.emit(
          "ai.tool.cancelled",
          run_id: id,
          project_id: project_id,
          attempt_id: invocation.attempt_id,
          tool_invocation_id: invocation.id,
          tool_call_id: invocation.tool_call_id,
          tool_key: invocation.tool_key,
          status: invocation.status,
          error_code: invocation.error_code,
          event_key: "tool:#{invocation.id}:cancelled"
        )
      end
  end

  def pending_tool_approval_invocations
    tool_invocations
      .where(status: %w[requested waiting_for_approval approved])
      .includes(:approval, :tool_definition)
      .select do |invocation|
        invocation.remote? || invocation.approval.present? || invocation.tool_definition&.approval_required?
      end
  end

  def finalize_failed_tool_approvals!(error)
    invocations = tool_invocations.includes(:approval, :tool_definition).order(:id).to_a
    return if invocations.empty?

    tool_calls = RubyLLM::ActiveRecord::ToolCall.where(
      message_type: Message.polymorphic_name,
      message_id: chat.messages.select(:id),
      tool_call_id: invocations.map(&:tool_call_id)
    ).includes(:result).index_by(&:tool_call_id)

    now = Time.current
    invocations.each do |invocation|
      approval = invocation.approval
      tool_call = tool_calls[invocation.tool_call_id]
      next unless failed_approval_call?(invocation, approval, tool_call)

      if approved_remote_tool_outcome_unknown?(invocation, approval, tool_call)
        mark_remote_tool_outcome_unknown!(invocation, error, now)
        next
      end

      finalize_failed_tool_call!(invocation, tool_call)
      expire_failed_approval!(invocation, approval, now) if approval&.pending?
      unless invocation.status.in?(%w[succeeded failed denied cancelled])
        mark_failed_tool_invocation!(invocation, error, now)
      end
    end
  end

  def failed_approval_call?(invocation, approval, tool_call)
    return true if approval&.pending?
    return false unless tool_call && tool_call.result.nil?
    return true if invocation.remote?

    approval_required = approval.present? || invocation.tool_definition&.approval_required?
    approval_required && (
      approval&.approved? || approval&.denied? ||
        invocation.status.in?(%w[requested waiting_for_approval approved])
    )
  end

  def approved_remote_tool_outcome_unknown?(invocation, approval, tool_call)
    invocation.remote? && tool_call && tool_call.result.nil? && (
      approval&.approved? || tool_call.approval == "approved" || invocation.approved?
    )
  end

  def mark_remote_tool_outcome_unknown!(invocation, error, now)
    message = "Remote tool call was approved, but its provider result was not persisted before the Run failed. The external outcome is unknown; this chat cannot safely resume it."
    invocation.update!(
      status: :failed,
      finished_at: now,
      duration_ms: invocation.started_at ? ((now - invocation.started_at) * 1_000).round : nil,
      error_class: error.class.name,
      error_code: "remote_tool_outcome_unknown",
      error_message: message
    )
    Ai::LifecycleEventRecorder.emit(
      "ai.tool.completed",
      run_id: id,
      project_id: project_id,
      attempt_id: invocation.attempt_id,
      tool_invocation_id: invocation.id,
      tool_call_id: invocation.tool_call_id,
      tool_key: invocation.tool_key,
      status: invocation.status,
      error_class: invocation.error_class,
      error_code: invocation.error_code,
      event_key: "tool:#{invocation.id}:completed:remote_outcome_unknown"
    )
  end

  def finalize_failed_tool_call!(invocation, tool_call)
    return unless tool_call

    chat.deny(invocation.tool_call_id) unless tool_call.approval == "denied"
    return if tool_call.result

    if invocation.remote?
      llm_chat = chat.to_llm
      response = llm_chat.provider.tool_approval_response(
        tool_call.to_llm,
        approved: false,
        model: llm_chat.model
      )
      chat.add_message(response)
    else
      chat.add_message(
        role: :tool,
        content: { error: "The Run failed before this tool call was executed." }.to_json,
        tool_call_id: invocation.tool_call_id
      )
    end
  rescue StandardError => error
    Rails.logger.warn("Run ##{id} failed approval cleanup for tool call #{invocation.tool_call_id}: #{error.class}")
  end

  def expire_failed_approval!(invocation, approval, now)
    approval.update!(
      status: :expired,
      decided_at: now,
      decision_note: "Run failed before approval was decided."
    )
    Ai::LifecycleEventRecorder.emit(
      "ai.approval.expired",
      run_id: id,
      project_id: project_id,
      attempt_id: invocation.attempt_id,
      tool_invocation_id: invocation.id,
      approval_id: approval.id,
      status: approval.status,
      actor: "system",
      event_key: "approval:#{approval.id}:expired"
    )
  end

  def mark_failed_tool_invocation!(invocation, error, now)
    invocation.update!(
      status: :failed,
      finished_at: now,
      duration_ms: invocation.started_at ? ((now - invocation.started_at) * 1_000).round : nil,
      error_class: error.class.name,
      error_code: Ai::ErrorClassifier.code(error),
      error_message: Ai::ErrorText.safe(error.message).to_s.truncate(2_000)
    )
    Ai::LifecycleEventRecorder.emit(
      "ai.tool.completed",
      run_id: id,
      project_id: project_id,
      attempt_id: invocation.attempt_id,
      tool_invocation_id: invocation.id,
      tool_call_id: invocation.tool_call_id,
      tool_key: invocation.tool_key,
      status: invocation.status,
      error_class: invocation.error_class,
      error_code: invocation.error_code,
      event_key: "tool:#{invocation.id}:completed:failed"
    )
  end

  def resolve_pending_tool_approvals!(pending_invocations)
    pending_invocations.each do |invocation|
      chat.deny(invocation.tool_call_id)
      next if invocation.remote?

      chat.add_message(
        role: :tool,
        content: { error: "The Run was cancelled before this tool call started." }.to_json,
        tool_call_id: invocation.tool_call_id
      )
    end

    return unless pending_invocations.any?(&:remote?)

    Ai::ChatTooling.new(chat:, project:, run: self).configure
    chat.run_tools
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

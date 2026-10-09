class Run < ApplicationRecord
  include AgentExecutionLease
  include ToolApprovalClosure

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

      attempt.cost
    end
    values.sum if values.any?
  end

  def cost_status
    return "unknown" if attempts.empty?
    return "unknown" if attempts.any? { |attempt| attempt.cost_status == "unknown" }
    return "estimated" if attempts.any? { |attempt| attempt.cost_status == "estimated" }
    return "recorded" if attempts.any? { |attempt| attempt.cost_status == "recorded" }

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
      if foreign_agent_execution?(agent_execution_token, agent_execution_generation)
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
      if foreign_agent_execution?(agent_execution_token, agent_execution_generation)
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
      if foreign_agent_execution?(agent_execution_token, agent_execution_generation)
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
    return if Workbench::DemoMode.enabled?
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

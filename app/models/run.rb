class Run < ApplicationRecord
  STATUSES = %w[queued running waiting_for_approval succeeded failed cancelled].freeze

  belongs_to :project
  belongs_to :chat
  belongs_to :experiment, optional: true
  belongs_to :experiment_execution, optional: true
  has_many :attempts, -> { order(:sequence, :id) }, dependent: :destroy
  has_many :artifacts, dependent: :destroy
  has_many :tool_invocations, dependent: :destroy
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
    was_waiting_for_approval = waiting_for_approval?
    first_start = started_at.nil?
    update!(status: :running, started_at: started_at || Time.current)
    if first_start
      record_lifecycle_event("ai.run.started", attempt_id: current_attempt_id)
    elsif was_waiting_for_approval
      record_lifecycle_event("ai.run.resumed", attempt_id: current_attempt_id)
    end
    self
  end

  def wait_for_approval!(summary = {}, attempt_id: nil)
    update!(
      status: :waiting_for_approval,
      finished_at: nil,
      result_summary_json: summary
    )
    record_lifecycle_event("ai.run.waiting_for_approval", attempt_id: attempt_id)
    self
  end

  def succeed!(summary = {})
    update!(status: :succeeded, finished_at: Time.current, result_summary_json: summary)
    record_lifecycle_event("ai.run.succeeded")
    self
  end

  def fail!(error, summary: {})
    failure_summary = { "failure_kind" => Ai::ErrorClassifier.code(error) }
    update!(
      status: :failed,
      finished_at: Time.current,
      error_summary: error_message_for(error),
      result_summary_json: result_summary.merge(failure_summary).merge(summary)
    )
    record_lifecycle_event(
      "ai.run.failed",
      error_class: error.class.name,
      error_code: Ai::ErrorClassifier.code(error),
      failure_kind: failure_summary.fetch("failure_kind")
    )
    self
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

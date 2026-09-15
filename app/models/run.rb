class Run < ApplicationRecord
  STATUSES = %w[queued running waiting_for_approval succeeded failed cancelled].freeze

  belongs_to :project
  belongs_to :chat
  has_many :attempts, -> { order(:sequence, :id) }, dependent: :destroy

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

  def duration_ms
    return unless started_at

    (((finished_at || Time.current) - started_at).to_f * 1_000).round
  end

  def total_tokens
    %i[input output cache_read cache_write thinking].to_h do |field|
      [ field, attempts.sum("#{field}_tokens") ]
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
    update!(status: :running, started_at: started_at || Time.current)
  end

  def succeed!(summary = {})
    update!(status: :succeeded, finished_at: Time.current, result_summary_json: summary)
  end

  def fail!(error, summary: {})
    update!(
      status: :failed,
      finished_at: Time.current,
      error_summary: error_message_for(error),
      result_summary_json: result_summary.merge(summary)
    )
  end

  def inspector_path
    Rails.application.routes.url_helpers.run_path(self)
  end

  private

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
    message.to_s.gsub(/\b(sk|rk|xai|AIza|gsk|pplx|r8)_[A-Za-z0-9_-]{12,}\b/i, "[REDACTED]")
  end
end

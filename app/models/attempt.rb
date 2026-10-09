class Attempt < ApplicationRecord
  STATUSES = %w[queued running succeeded failed cancelled].freeze

  belongs_to :run
  has_many :lifecycle_events, dependent: :nullify
  has_many :ruby_llm_usages, as: :owner, class_name: "RubyLLM::ActiveRecord::Usage", dependent: :nullify

  enum :status, STATUSES.index_with(&:itself), validate: true

  after_update :record_lifecycle_status_event, if: :saved_change_to_status?

  validates :sequence, numericality: { only_integer: true, greater_than: 0 }
  validates :provider, :model_id, presence: true
  validates :sequence, uniqueness: { scope: :run_id }

  def tokens
    {
      input: input_tokens,
      output: output_tokens,
      cache_read: cache_read_tokens,
      cache_write: cache_write_tokens,
      thinking: thinking_tokens
    }.compact
  end

  def cost
    reported_cost || recorded_cost || estimated_cost
  end

  def start!
    update!(status: :running, started_at: started_at || Time.current)
  end

  def finish!(status:, finished_at: Time.current, **attributes)
    update!(attributes.merge(status: status, finished_at: finished_at))
  end

  private

  def record_lifecycle_status_event
    event_name = {
      "running" => "ai.attempt.started",
      "succeeded" => "ai.attempt.succeeded",
      "failed" => "ai.attempt.failed",
      "cancelled" => "ai.attempt.cancelled"
    }.fetch(status.to_s, nil)
    return unless event_name

    Ai::LifecycleEventRecorder.emit(
      event_name,
      {
        run_id: run_id,
        attempt_id: id,
        provider: provider,
        model_id: model_id,
        status: status,
        duration_ms: duration_ms,
        error_class: error_class,
        error_code: error_code,
        event_key: "attempt:#{id}:#{status}"
      }
    )
  end
end

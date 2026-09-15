class Attempt < ApplicationRecord
  STATUSES = %w[queued running succeeded failed cancelled].freeze

  belongs_to :run

  enum :status, STATUSES.index_with(&:itself), validate: true

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
    reported_cost || estimated_cost
  end

  def start!
    update!(status: :running, started_at: started_at || Time.current)
  end

  def finish!(status:, finished_at: Time.current, **attributes)
    update!(attributes.merge(status: status, finished_at: finished_at))
  end
end

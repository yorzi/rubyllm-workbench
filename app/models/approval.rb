class Approval < ApplicationRecord
  STATUSES = %w[pending approved denied expired].freeze

  belongs_to :tool_invocation

  enum :status, STATUSES.index_with(&:itself), validate: true

  validates :actor, :requested_at, presence: true
  validates :tool_invocation_id, uniqueness: true

  def decided?
    approved? || denied? || expired?
  end
end

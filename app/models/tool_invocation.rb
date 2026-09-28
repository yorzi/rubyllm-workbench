class ToolInvocation < ApplicationRecord
  STATUSES = %w[requested waiting_for_approval approved denied running succeeded failed cancelled].freeze

  belongs_to :run
  belongs_to :attempt, optional: true
  belongs_to :tool_definition, optional: true
  has_one :approval, dependent: :destroy

  enum :status, STATUSES.index_with(&:itself), validate: true

  validates :tool_call_id, :tool_key, presence: true
  validates :tool_call_id, uniqueness: { scope: :run_id }

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def arguments
    arguments_json || {}
  end

  def result
    result_json || {}
  end

  def approval_pending?
    approval&.pending? || false
  end

  def display_name
    tool_definition&.name.presence || tool_key.humanize
  end
end

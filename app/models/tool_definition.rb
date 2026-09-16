class ToolDefinition < ApplicationRecord
  APPROVAL_POLICIES = %w[never always].freeze

  belongs_to :project
  has_many :tool_invocations, dependent: :nullify

  scope :enabled, -> { where(enabled: true) }

  validates :key, :name, :class_identifier, presence: true
  validates :key, uniqueness: { scope: :project_id }, format: { with: /\A[a-z0-9_]+\z/ }
  validates :approval_policy, inclusion: { in: APPROVAL_POLICIES }
  validate :registry_entry_exists

  def registry_entry
    Ai::ToolRegistry.fetch!(class_identifier)
  end

  def tool_instance(run: nil)
    registry_entry.instantiate(project:, run:)
  end

  def approval_required?
    approval_policy == "always"
  end

  def parallel_safe?
    registry_entry.parallel_safe?
  rescue KeyError
    false
  end

  private

  def registry_entry_exists
    Ai::ToolRegistry.fetch!(class_identifier)
  rescue KeyError => error
    errors.add(:class_identifier, error.message)
  end
end

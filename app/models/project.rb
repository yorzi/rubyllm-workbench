class Project < ApplicationRecord
  TOOL_EXECUTION_MODES = %w[sequential parallel].freeze

  has_many :chats, dependent: :destroy
  has_many :agent_definitions, dependent: :destroy
  has_many :experiments, dependent: :destroy
  has_many :experiment_executions, dependent: :destroy
  has_many :evaluation_executions, dependent: :destroy
  has_many :evaluation_comparisons, dependent: :destroy
  has_many :evaluation_datasets, dependent: :destroy
  has_many :knowledge_collections, dependent: :destroy
  has_many :runs, dependent: :destroy
  has_many :tool_definitions, dependent: :destroy
  has_many :tool_invocations, through: :runs

  validates :name, presence: true, length: { maximum: 120 }
  validates :slug, presence: true, uniqueness: true,
    format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }

  before_validation :derive_slug, if: -> { slug.blank? && name.present? }

  def to_param
    slug.presence || super
  end

  def tool_settings
    value = settings_hash["tools"]
    value.is_a?(Hash) ? value : {}
  end

  def tool_execution_mode
    mode = tool_settings["execution_mode"].to_s
    TOOL_EXECUTION_MODES.include?(mode) ? mode : "sequential"
  end

  def update_tool_execution_mode!(mode)
    normalized_mode = mode.to_s
    unless TOOL_EXECUTION_MODES.include?(normalized_mode)
      raise ArgumentError, "Unknown tool execution mode: #{mode.inspect}"
    end

    self.settings_json = settings_hash.merge(
      "tools" => tool_settings.merge("execution_mode" => normalized_mode)
    )
    save!
  end

  private

  def settings_hash
    value = settings_json
    value.is_a?(Hash) ? value.deep_stringify_keys : {}
  end

  def derive_slug
    self.slug = name.to_s.parameterize
  end
end

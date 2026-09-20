class AgentDefinition < ApplicationRecord
  SCHEMA_VERSION = 1
  PROVIDER_TOOLS = %w[web_search].freeze
  SAFE_OPTION_KEYS = %w[temperature max_output_tokens].freeze
  MAX_INSTRUCTIONS_LENGTH = 20_000
  DEFINITION_ATTRIBUTES = %w[
    name provider model_id instructions tool_keys_json provider_tools_json options_json
  ].freeze

  belongs_to :project

  validates :name, presence: true, length: { maximum: 160 }, uniqueness: { scope: :project_id }
  validates :provider, :model_id, presence: true
  validates :provider, length: { maximum: 80 }
  validates :model_id, length: { maximum: 240 }
  validates :instructions, presence: true, length: { maximum: MAX_INSTRUCTIONS_LENGTH }
  validates :revision, numericality: { only_integer: true, greater_than: 0 }
  validate :tool_keys_are_enabled_for_project
  validate :provider_tools_are_allowlisted
  validate :options_are_safe

  before_update :bump_revision, if: :definition_changed?

  def tool_keys
    Array(tool_keys_json).map(&:to_s).reject(&:blank?).uniq
  end

  def tool_keys=(value)
    self.tool_keys_json = normalized_list(value)
  end

  def provider_tools
    Array(provider_tools_json).map(&:to_s).reject(&:blank?).uniq
  end

  def provider_tools=(value)
    self.provider_tools_json = normalized_list(value)
  end

  def options
    value = options_json
    value.is_a?(Hash) ? value.deep_stringify_keys : {}
  end

  def options=(value)
    self.options_json = value.is_a?(Hash) ? value.deep_stringify_keys.reject { |_key, item| item.blank? } : value
  end

  # Return a JSON-safe value contract that can be copied into a durable AgentRun.
  # A JSON round-trip ensures callers cannot mutate the persisted definition through
  # nested arrays or hashes returned by this method.
  def snapshot
    JSON.parse(JSON.generate(
      {
        "schema_version" => SCHEMA_VERSION,
        "id" => id,
        "name" => name,
        "revision" => revision,
        "provider" => provider,
        "model_id" => model_id,
        "instructions" => instructions,
        "tool_keys" => tool_keys,
        "provider_tools" => provider_tools,
        "options" => safe_options
      }
    ))
  end

  private

  def normalized_list(value)
    Array(value).map(&:to_s).reject(&:blank?).uniq
  end

  def tool_keys_are_enabled_for_project
    unless tool_keys_json.is_a?(Array)
      errors.add(:tool_keys, "must be a list")
      return
    end
    return if tool_keys.empty? || project.nil?

    enabled_keys = project.tool_definitions.enabled.where(key: tool_keys).pluck(:key)
    invalid_keys = tool_keys - enabled_keys
    return if invalid_keys.empty?

    errors.add(:tool_keys, "include tools that are unavailable in this Project: #{invalid_keys.join(', ')}")
  end

  def provider_tools_are_allowlisted
    unless provider_tools_json.is_a?(Array)
      errors.add(:provider_tools, "must be a list")
      return
    end

    unknown_tools = provider_tools - PROVIDER_TOOLS
    errors.add(:provider_tools, "include unsupported provider tools: #{unknown_tools.join(', ')}") if unknown_tools.any?
  end

  def options_are_safe
    unless options_json.is_a?(Hash)
      errors.add(:options, "must be an object")
      return
    end

    unknown_options = options.keys - SAFE_OPTION_KEYS
    errors.add(:options, "include unsupported options: #{unknown_options.join(', ')}") if unknown_options.any?

    validate_temperature if options["temperature"].present?
    validate_max_output_tokens if options["max_output_tokens"].present?
  end

  def validate_temperature
    value = Float(options.fetch("temperature"), exception: false)
    unless value&.finite? && value.between?(0.0, 2.0)
      errors.add(:options, "temperature must be a number between 0 and 2")
    end
  end

  def validate_max_output_tokens
    raw_value = options.fetch("max_output_tokens")
    integer_input = raw_value.is_a?(Integer) || raw_value.is_a?(String) && raw_value.match?(/\A[+-]?\d+\z/)
    value = Integer(raw_value, exception: false) if integer_input
    unless value&.positive? && value <= 200_000
      errors.add(:options, "max_output_tokens must be an integer between 1 and 200000")
    end
  end

  def safe_options
    options.each_with_object({}) do |(key, value), result|
      next if value.blank?

      case key
      when "temperature"
        result[key] = Float(value, exception: false) if Float(value, exception: false)&.finite?
      when "max_output_tokens"
        integer_input = value.is_a?(Integer) || value.is_a?(String) && value.match?(/\A[+-]?\d+\z/)
        result[key] = Integer(value, exception: false) if integer_input
      end
    end
  end

  def definition_changed?
    DEFINITION_ATTRIBUTES.any? { |attribute| will_save_change_to_attribute?(attribute) }
  end

  def bump_revision
    self.revision = revision.to_i + 1
  end
end

class Experiment < ApplicationRecord
  STATUSES = %w[draft runnable archived].freeze
  DEFINITION_ATTRIBUTES = %w[name description system_prompt input_prompt schema_json generation_options_json].freeze

  belongs_to :project
  has_many :runs, dependent: :nullify
  has_many :experiment_executions, dependent: :destroy
  has_many :evaluation_executions, dependent: :nullify

  enum :status, STATUSES.index_with(&:itself), validate: true

  validates :name, presence: true, length: { maximum: 160 }
  validates :input_prompt, presence: true, length: { maximum: 20_000 }
  validates :revision, numericality: { only_integer: true, greater_than: 0 }
  validate :schema_document_is_supported

  before_update :bump_revision, if: :definition_changed?

  def schema_definition
    Ai::SchemaDefinition.parse(schema_json)
  end

  def snapshot
    JSON.parse(JSON.generate(
      {
        "id" => id,
        "name" => name,
        "description" => description,
        "system_prompt" => system_prompt,
        "input_prompt" => input_prompt,
        "schema" => schema_definition.document,
        "generation_options" => generation_options_json || {},
        "status" => status,
        "revision" => revision
      }
    ))
  end

  private

  def schema_document_is_supported
    Ai::SchemaDefinition.parse(schema_json)
  rescue Ai::SchemaDefinition::DefinitionError => error
    errors.add(:schema_json, error.message)
  end

  def definition_changed?
    DEFINITION_ATTRIBUTES.any? { |attribute| will_save_change_to_attribute?(attribute) }
  end

  def bump_revision
    self.revision = revision.to_i + 1
  end
end

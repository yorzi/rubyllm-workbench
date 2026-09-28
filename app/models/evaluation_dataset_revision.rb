class EvaluationDatasetRevision < ApplicationRecord
  MAX_CASES = 100
  MAX_CASE_BYTES = 64.kilobytes
  MAX_DATASET_BYTES = 1.megabyte
  MAX_TAGS_PER_CASE = 12
  MAX_TAG_LENGTH = 40
  MAX_RUBRIC_CRITERIA = 8
  MAX_RUBRIC_KEY_LENGTH = 40
  MAX_RUBRIC_DESCRIPTION_LENGTH = 240
  RUBRIC_KEY_FORMAT = /\A[a-z][a-z0-9_]*\z/

  belongs_to :evaluation_dataset
  has_many :evaluation_executions, dependent: :restrict_with_exception
  has_many :evaluation_comparisons, dependent: :restrict_with_exception
  has_many :evaluation_case_results, dependent: :restrict_with_exception
  has_many :case_attachments, -> { order(:case_key, :position, :id) }, class_name: "EvaluationDatasetCaseAttachment", dependent: :destroy

  validates :revision, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :evaluation_dataset_id }
  validate :cases_are_bounded_and_valid
  before_update :keep_revision_immutable

  def cases
    Array(cases_json).map(&:deep_stringify_keys)
  end

  def case_attachments_for(case_key)
    case_attachments.select { |attachment| attachment.case_key == case_key.to_s }
  end

  private

  def cases_are_bounded_and_valid
    unless cases_json.is_a?(Array) && cases_json.any? && cases_json.size <= MAX_CASES
      errors.add(:cases_json, "must contain between 1 and #{MAX_CASES} cases")
      return
    end

    keys = []
    dataset_bytes = 0
    cases_json.each_with_index do |item, index|
      unless item.is_a?(Hash)
        errors.add(:cases_json, "case #{index + 1} must be an object")
        next
      end

      item = item.deep_stringify_keys
      case_bytes = JSON.generate(item).bytesize
      dataset_bytes += case_bytes
      errors.add(:cases_json, "case #{index + 1} exceeds #{MAX_CASE_BYTES / 1.kilobyte} KB") if case_bytes > MAX_CASE_BYTES
      key = item["key"].to_s
      errors.add(:cases_json, "case #{index + 1} needs a non-empty key") if key.blank? || key.length > 120
      errors.add(:cases_json, "case key #{key.inspect} is repeated") if keys.include?(key)
      keys << key
      errors.add(:cases_json, "case #{index + 1} must include input") unless item.key?("input")
      errors.add(:cases_json, "case #{index + 1} must include expected_output") unless item.key?("expected_output")
      validate_tags(item, index)
      validate_rubric(item, index)
    end
    errors.add(:cases_json, "dataset exceeds #{MAX_DATASET_BYTES / 1.megabyte} MB") if dataset_bytes > MAX_DATASET_BYTES
  end

  def validate_tags(item, index)
    return unless item.key?("tags")

    tags = item["tags"]
    unless tags.is_a?(Array) && tags.size <= MAX_TAGS_PER_CASE
      errors.add(:cases_json, "case #{index + 1} tags must be an array of at most #{MAX_TAGS_PER_CASE} strings")
      return
    end

    valid_tags = tags.select do |tag|
      valid = tag.is_a?(String) && tag.present? && tag == tag.strip && tag.length <= MAX_TAG_LENGTH
      errors.add(:cases_json, "case #{index + 1} tags must be non-empty strings up to #{MAX_TAG_LENGTH} characters") unless valid
      valid
    end
    normalized_tags = valid_tags.map { |tag| tag.strip.downcase }
    errors.add(:cases_json, "case #{index + 1} tags must be unique") unless normalized_tags.uniq.size == normalized_tags.size
  end

  def validate_rubric(item, index)
    return unless item.key?("rubric")

    rubric = item["rubric"]
    unless rubric.is_a?(Array) && rubric.any? && rubric.size <= MAX_RUBRIC_CRITERIA
      errors.add(:cases_json, "case #{index + 1} rubric must contain between 1 and #{MAX_RUBRIC_CRITERIA} criteria")
      return
    end

    keys = []
    rubric.each_with_index do |criterion, criterion_index|
      unless criterion.is_a?(Hash)
        errors.add(:cases_json, "case #{index + 1} rubric criterion #{criterion_index + 1} must be an object")
        next
      end

      criterion = criterion.deep_stringify_keys
      unless criterion.keys.sort == %w[description key]
        errors.add(:cases_json, "case #{index + 1} rubric criteria must contain only key and description")
      end

      key = criterion["key"]
      unless key.is_a?(String) && key.length <= MAX_RUBRIC_KEY_LENGTH && RUBRIC_KEY_FORMAT.match?(key)
        errors.add(:cases_json, "case #{index + 1} rubric keys must be lowercase identifiers up to #{MAX_RUBRIC_KEY_LENGTH} characters")
        next
      end

      errors.add(:cases_json, "case #{index + 1} rubric key #{key.inspect} is repeated") if keys.include?(key)
      keys << key

      description = criterion["description"]
      unless description.is_a?(String) && description.present? && description == description.strip && description.length <= MAX_RUBRIC_DESCRIPTION_LENGTH
        errors.add(:cases_json, "case #{index + 1} rubric descriptions must be non-empty, unpadded strings up to #{MAX_RUBRIC_DESCRIPTION_LENGTH} characters")
      end
    end
  end

  def keep_revision_immutable
    errors.add(:base, "Evaluation dataset revisions are immutable.")
    throw :abort
  end
end

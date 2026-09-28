class EvaluationDatasetCaseAttachment < ApplicationRecord
  MAX_FILE_BYTES = 10.megabytes
  MAX_FILES_PER_CASE = 5
  MAX_FILES_PER_REVISION = 50
  MAX_REVISION_BYTES = 50.megabytes
  ALLOWED_CONTENT_TYPES = %w[
    application/json
    application/pdf
    image/jpeg
    image/png
    text/csv
    text/plain
  ].freeze

  belongs_to :evaluation_dataset_revision
  has_one_attached :file, dependent: :purge_later

  validates :case_key, presence: true, length: { maximum: 120 }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :position, uniqueness: { scope: [ :evaluation_dataset_revision_id, :case_key ] }
  validate :case_exists_in_revision
  validate :file_is_present_and_bounded

  before_update :keep_attachment_immutable

  private

  def case_exists_in_revision
    return if evaluation_dataset_revision&.cases&.any? { |item| item["key"] == case_key }

    errors.add(:case_key, "must belong to the evaluation dataset revision")
  end

  def file_is_present_and_bounded
    unless file.attached?
      errors.add(:file, "must be attached")
      return
    end

    blob = file.blob
    errors.add(:file, "must not be empty") if blob.byte_size.zero?
    errors.add(:file, "must be #{MAX_FILE_BYTES / 1.megabyte} MB or smaller") if blob.byte_size > MAX_FILE_BYTES
    unless ALLOWED_CONTENT_TYPES.include?(blob.content_type)
      errors.add(:file, "must be one of: #{ALLOWED_CONTENT_TYPES.join(', ')}")
    end
  end

  def keep_attachment_immutable
    errors.add(:base, "Evaluation case attachments are immutable; create a new dataset revision.")
    throw :abort
  end
end

class EvaluationDataset < ApplicationRecord
  belongs_to :project
  has_many :evaluation_dataset_revisions, dependent: :destroy
  has_many :evaluation_executions, through: :evaluation_dataset_revisions
  has_many :evaluation_comparisons, through: :evaluation_dataset_revisions

  validates :name, presence: true, length: { maximum: 160 }, uniqueness: { scope: :project_id }
  validates :current_revision, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def current_revision_record
    evaluation_dataset_revisions.find_by(revision: current_revision)
  end

  def create_revision!(cases, uploads_by_case_key: {}, removed_attachment_ids: [], base_revision_id: nil)
    document = cases.is_a?(String) ? JSON.parse(cases) : cases
    revision = nil
    with_lock do
      previous_revision = current_revision_record
      if base_revision_id.present? && previous_revision&.id != base_revision_id.to_i
        raise_invalid_attachment_change!("The dataset changed while files were being edited. Reload the current revision and try again.", document)
      end
      case_keys = case_keys_for(document)
      uploads = normalize_case_uploads(uploads_by_case_key, case_keys, document)
      removed_ids = normalize_removal_ids(removed_attachment_ids, document)
      previous_attachments = previous_revision&.case_attachments&.includes(file_attachment: :blob)&.to_a || []
      previous_by_id = previous_attachments.index_by(&:id)

      if (removed_ids - previous_by_id.keys).any?
        raise_invalid_attachment_change!("Selected files must belong to the current revision.", document)
      end

      retained_attachments = previous_attachments.reject do |attachment|
        removed_ids.include?(attachment.id) || !case_keys.include?(attachment.case_key)
      end
      validate_attachment_bounds!(retained_attachments, uploads, document)
      validate_attachment_contents!(uploads, document)

      revision = evaluation_dataset_revisions.create!(revision: current_revision.to_i + 1, cases_json: document)
      retained_attachments.each do |attachment|
        copy_attachment!(revision, attachment.case_key, next_attachment_position(revision, attachment.case_key), attachment.file.blob)
      end
      uploads.each do |case_key, files|
        files.each do |upload|
          attachment = revision.case_attachments.build(
            case_key:,
            position: next_attachment_position(revision, case_key)
          )
          attachment.file.attach(upload)
          attachment.save!
        end
      end
      update!(current_revision: revision.revision)
    end
    revision
  rescue JSON::ParserError => error
    revision = evaluation_dataset_revisions.build(revision: current_revision.to_i + 1, cases_json: [])
    revision.errors.add(:cases_json, "must be valid JSON: #{error.message}")
    raise ActiveRecord::RecordInvalid, revision
  end

  private

  def case_keys_for(document)
    return [] unless document.is_a?(Array)

    document.filter_map do |item|
      item.deep_stringify_keys["key"] if item.is_a?(Hash)
    end.map(&:to_s)
  end

  def normalize_case_uploads(uploads_by_case_key, case_keys, document)
    uploads_by_case_key.to_h.each_with_object({}) do |(raw_key, raw_files), normalized|
      key = raw_key.to_s
      files = Array(raw_files).compact.reject { |file| file.respond_to?(:blank?) && file.blank? }
      next if files.empty?

      unless case_keys.include?(key)
        raise_invalid_attachment_change!("The selected case key does not exist in the new revision.", document)
      end

      unless files.all? { |file| file.respond_to?(:original_filename) && file.respond_to?(:size) }
        raise_invalid_attachment_change!("Choose uploads for an existing case using the file upload control.", document)
      end

      normalized[key] = files
    end
  end

  def normalize_removal_ids(raw_ids, document)
    values = Array(raw_ids).reject(&:blank?).map(&:to_s)
    return [] if values.empty?
    return values.map(&:to_i).uniq if values.all? { |value| value.match?(/\A\d+\z/) }

    raise_invalid_attachment_change!("Selected files are invalid.", document)
  end

  def validate_attachment_bounds!(retained_attachments, uploads, document)
    counts = Hash.new(0)
    byte_sizes = Hash.new(0)
    retained_attachments.each do |attachment|
      counts[attachment.case_key] += 1
      byte_sizes[attachment.case_key] += attachment.file.blob.byte_size
    end
    uploads.each do |case_key, files|
      counts[case_key] += files.size
      files.each do |file|
        byte_sizes[case_key] += file.size.to_i
        if file.size.to_i > EvaluationDatasetCaseAttachment::MAX_FILE_BYTES
          raise_invalid_attachment_change!("Each case attachment must be #{EvaluationDatasetCaseAttachment::MAX_FILE_BYTES / 1.megabyte} MB or smaller.", document)
        end
      end
    end

    if counts.values.sum > EvaluationDatasetCaseAttachment::MAX_FILES_PER_REVISION
      raise_invalid_attachment_change!("A revision may contain at most #{EvaluationDatasetCaseAttachment::MAX_FILES_PER_REVISION} files.", document)
    end
    if byte_sizes.values.sum > EvaluationDatasetCaseAttachment::MAX_REVISION_BYTES
      raise_invalid_attachment_change!("A revision's attachments may total at most #{EvaluationDatasetCaseAttachment::MAX_REVISION_BYTES / 1.megabyte} MB.", document)
    end
    if counts.values.any? { |count| count > EvaluationDatasetCaseAttachment::MAX_FILES_PER_CASE }
      raise_invalid_attachment_change!("A case may contain at most #{EvaluationDatasetCaseAttachment::MAX_FILES_PER_CASE} files.", document)
    end
  end

  def validate_attachment_contents!(uploads, document)
    uploads.each_value do |files|
      files.each do |upload|
        io = upload.respond_to?(:tempfile) ? upload.tempfile : nil
        validator = if io
          Ai::EvaluationCaseAttachmentContentValidator.new(
            io:,
            content_type: upload.content_type,
            filename: upload.original_filename
          )
        end
        unless validator&.supported?
          allowed_types = EvaluationDatasetCaseAttachment::ALLOWED_CONTENT_TYPES.join(", ")
          raise_invalid_attachment_change!("Each case attachment type must be one of: #{allowed_types}.", document)
        end
        valid = validator.valid?
        next if valid

        raise_invalid_attachment_change!("Each case attachment's bytes must match the declared file type.", document)
      end
    end
  end

  def next_attachment_position(revision, case_key)
    revision.case_attachments.where(case_key:).maximum(:position).to_i + 1
  end

  def copy_attachment!(revision, case_key, position, blob)
    attachment = revision.case_attachments.build(case_key:, position:)
    attachment.file.attach(blob)
    attachment.save!
  end

  def raise_invalid_attachment_change!(message, cases)
    invalid_revision = EvaluationDatasetRevision.new(
      evaluation_dataset: self,
      revision: current_revision.to_i + 1,
      cases_json: cases
    )
    invalid_revision.errors.add(:base, message)
    raise ActiveRecord::RecordInvalid, invalid_revision
  end
end

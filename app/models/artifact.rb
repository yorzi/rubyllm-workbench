class Artifact < ApplicationRecord
  KINDS = %w[text json citation_set image video audio transcript ocr_document report export].freeze

  belongs_to :run, optional: true
  belongs_to :attempt, optional: true
  belongs_to :knowledge_item, optional: true
  has_many :lifecycle_events, dependent: :nullify
  has_one_attached :audio_file
  has_one_attached :media_file

  after_create :record_created_event

  validates :kind, presence: true, inclusion: { in: KINDS }
  validate :has_content
  validate :has_owner

  def parsed_content
    return content_json unless content_json.nil?
    return if content_text.blank?

    JSON.parse(content_text)
  end

  private

  def record_created_event
    return if run_id.blank?

    Ai::LifecycleEventRecorder.emit(
      "ai.artifact.created",
      {
        run_id: run_id,
        attempt_id: attempt_id,
        artifact_id: id,
        kind: kind,
        name: name,
        event_key: "artifact:#{id}:created"
      }
    )
  end

  def has_content
    return if kind == "audio" && audio_file.attached?
    return if %w[image video].include?(kind) && media_file.attached?
    return if kind == "transcript" && content_text == ""

    errors.add(:base, "content is required") if content_json.nil? && content_text.blank?
  end

  # Artifacts are either execution evidence (Run) or document provenance
  # (KnowledgeItem); one owner is required so the record stays attributable.
  def has_owner
    return if run_id.present? || knowledge_item_id.present?

    errors.add(:base, "a run or knowledge item is required")
  end
end

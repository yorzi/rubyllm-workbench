class Artifact < ApplicationRecord
  KINDS = %w[text json citation_set image video audio transcript ocr_document report export].freeze

  belongs_to :run
  belongs_to :attempt, optional: true

  validates :kind, presence: true, inclusion: { in: KINDS }
  validate :has_content

  def parsed_content
    return content_json unless content_json.nil?
    return if content_text.blank?

    JSON.parse(content_text)
  end

  private

  def has_content
    errors.add(:base, "content is required") if content_json.nil? && content_text.blank?
  end
end

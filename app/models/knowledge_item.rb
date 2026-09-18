require "digest"

class KnowledgeItem < ApplicationRecord
  SOURCE_KINDS = %w[text file].freeze
  INGESTION_STATUSES = %w[pending ingesting ready failed].freeze
  EXTRACTION_STATUSES = %w[not_required pending extracting ready failed].freeze

  belongs_to :knowledge_collection
  has_many :knowledge_chunks, -> { order(:position, :id) }, dependent: :destroy
  has_many :knowledge_embeddings, through: :knowledge_chunks
  has_many :artifacts, dependent: :destroy
  has_one_attached :document

  enum :ingestion_status, INGESTION_STATUSES.index_with(&:itself), validate: true
  enum :extraction_status, EXTRACTION_STATUSES.index_with(&:itself), prefix: :extraction, validate: true

  validates :title, presence: true, length: { maximum: 200 }
  validates :source_kind, inclusion: { in: SOURCE_KINDS }
  validates :source_reference, length: { maximum: 500 }, allow_blank: true
  validates :content_text, presence: true, length: { maximum: 100_000 }, if: :text_source?
  validates :checksum, presence: true

  before_validation :normalize_content
  before_validation :derive_checksum
  before_validation :assign_extraction_status, on: :create

  scope :documents, -> { where(source_kind: "file") }
  scope :awaiting_extraction, -> { where(extraction_status: %w[pending extracting]) }

  def chunk_count
    knowledge_chunks.size
  end

  def text_source?
    source_kind == "text"
  end

  def file_source?
    source_kind == "file"
  end

  def filename
    document.attached? ? document.filename.to_s : source_reference.presence
  end

  def extraction_artifact
    artifacts.order(:id).last
  end

  private

  def assign_extraction_status
    return unless extraction_status == "not_required"
    return unless file_source?

    self.extraction_status = "pending"
  end

  def normalize_content
    self.content_text = content_text.to_s.gsub(/\r\n?/, "\n").strip
  end

  def derive_checksum
    self.checksum = Digest::SHA256.hexdigest(content_text.to_s)
  end
end

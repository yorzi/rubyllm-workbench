require "digest"

class KnowledgeItem < ApplicationRecord
  SOURCE_KINDS = %w[text].freeze
  INGESTION_STATUSES = %w[pending ingesting ready failed].freeze

  belongs_to :knowledge_collection
  has_many :knowledge_chunks, -> { order(:position, :id) }, dependent: :destroy

  enum :ingestion_status, INGESTION_STATUSES.index_with(&:itself), validate: true

  validates :title, presence: true, length: { maximum: 200 }
  validates :source_kind, inclusion: { in: SOURCE_KINDS }
  validates :source_reference, length: { maximum: 500 }, allow_blank: true
  validates :content_text, presence: true, length: { maximum: 100_000 }
  validates :checksum, presence: true

  before_validation :normalize_content
  before_validation :derive_checksum

  def chunk_count
    knowledge_chunks.size
  end

  private

  def normalize_content
    self.content_text = content_text.to_s.gsub(/\r\n?/, "\n").strip
  end

  def derive_checksum
    self.checksum = Digest::SHA256.hexdigest(content_text.to_s)
  end
end

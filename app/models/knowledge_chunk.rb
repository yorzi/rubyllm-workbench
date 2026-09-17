class KnowledgeChunk < ApplicationRecord
  belongs_to :knowledge_item
  has_many :knowledge_embeddings, dependent: :destroy

  validates :position, :char_start, :char_end, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :content_text, presence: true
  validate :offsets_are_ordered

  scope :ordered, -> { order(:position, :id) }

  def embedding_for(model_id)
    return nil if model_id.blank?

    knowledge_embeddings.ready.for_model(model_id).first
  end

  def content_checksum
    Digest::SHA256.hexdigest(content_text.to_s)
  end

  private

  def offsets_are_ordered
    return if char_start.blank? || char_end.blank?
    return if char_end >= char_start

    errors.add(:char_end, "must be greater than or equal to char_start")
  end
end

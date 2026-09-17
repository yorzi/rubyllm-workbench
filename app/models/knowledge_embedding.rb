class KnowledgeEmbedding < ApplicationRecord
  STATUSES = %w[ready failed].freeze

  belongs_to :knowledge_chunk

  enum :status, STATUSES.index_with(&:itself), validate: true

  validates :provider, presence: true
  validates :model_id, presence: true, length: { maximum: 200 }, uniqueness: { scope: :knowledge_chunk_id }
  validates :dimensions, numericality: { only_integer: true, greater_than: 0 }
  validates :content_checksum, presence: true
  validates :vector, presence: true

  scope :ready, -> { where(status: "ready") }
  scope :for_model, ->(model_id) { where(model_id: model_id.to_s) }

  def vector_values
    Ai::Knowledge::VectorStore.default.decode(vector)
  end

  def dimensions_match?
    vector_values.length == dimensions
  end
end

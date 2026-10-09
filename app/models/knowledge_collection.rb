class KnowledgeCollection < ApplicationRecord
  EMBEDDING_STATUSES = %w[none partial ready failed].freeze

  belongs_to :project
  has_many :knowledge_items, dependent: :destroy
  has_many :knowledge_chunks, through: :knowledge_items
  has_many :knowledge_embeddings, through: :knowledge_chunks

  validates :name, presence: true, length: { maximum: 120 }
  validates :description, length: { maximum: 2_000 }, allow_blank: true
  validates :embedding_status, inclusion: { in: EMBEDDING_STATUSES }

  scope :recent, -> { order(updated_at: :desc, id: :desc) }

  def embedded_chunk_count(model_id: embedding_model_id, provider: nil)
    return 0 if model_id.blank?

    provider = provider.presence
    provider ||= embedding_provider if model_id.to_s == embedding_model_id
    embeddings = knowledge_embeddings.ready.for_model(model_id)
    embeddings = embeddings.where(provider: provider.to_s) if provider.present?
    embeddings.count
  end

  def chunk_count
    knowledge_chunks.count
  end

  def embedding_ready?
    embedding_status == "ready"
  end

  def semantic_searchable?(model_id: embedding_model_id, provider: nil)
    model_id.present? && embedded_chunk_count(model_id: model_id, provider: provider).positive?
  end

  def embedding_label
    return "no embedding model" if embedding_model_id.blank?

    "#{embedding_model_id} · #{embedding_dimensions || '?'}d"
  end
end

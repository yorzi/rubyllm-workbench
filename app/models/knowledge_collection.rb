class KnowledgeCollection < ApplicationRecord
  belongs_to :project
  has_many :knowledge_items, dependent: :destroy
  has_many :knowledge_chunks, through: :knowledge_items

  validates :name, presence: true, length: { maximum: 120 }
  validates :description, length: { maximum: 2_000 }, allow_blank: true

  scope :recent, -> { order(updated_at: :desc, id: :desc) }
end

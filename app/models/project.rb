class Project < ApplicationRecord
  has_many :chats, dependent: :destroy
  has_many :runs, dependent: :destroy

  validates :name, presence: true, length: { maximum: 120 }
  validates :slug, presence: true, uniqueness: true,
    format: { with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ }

  before_validation :derive_slug, if: -> { slug.blank? && name.present? }

  def to_param
    slug.presence || super
  end

  private

  def derive_slug
    self.slug = name.to_s.parameterize
  end
end

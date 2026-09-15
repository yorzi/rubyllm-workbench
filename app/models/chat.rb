class Chat < ApplicationRecord
  acts_as_chat

  belongs_to :project
  has_many :runs, dependent: :destroy

  validates :title, length: { maximum: 160 }, allow_blank: true
  validates :project, presence: true

  def display_title
    title.presence || messages.where(role: "user").order(:created_at, :id).first&.content.to_s.truncate(72)
  end

  def stream_key
    "chat_#{id}"
  end
end

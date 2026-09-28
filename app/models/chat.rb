class Chat < ApplicationRecord
  REMOTE_TOOL_OUTCOME_UNKNOWN_MESSAGE = "This chat has an approved remote tool call with no saved provider result. Its external outcome is unknown; start a new chat instead of resuming it.".freeze

  acts_as_chat

  belongs_to :project
  has_many :runs, dependent: :destroy
  has_many :tool_invocations, through: :runs

  validates :title, length: { maximum: 160 }, allow_blank: true
  validates :project, presence: true

  def display_title
    title.presence || messages.where(role: "user").order(:created_at, :id).first&.content.to_s.truncate(72)
  end

  def stream_key
    "chat_#{id}"
  end

  def remote_tool_outcome_unknown?
    tool_invocations.where(remote: true, error_code: "remote_tool_outcome_unknown").exists?
  end
end

class Message < ApplicationRecord
  acts_as_message

  attr_accessor :web_search

  has_many_attached :attachments

  broadcasts_to ->(message) { message.chat.stream_key }, inserts_by: :append

  def broadcast_append_chunk(content)
    broadcast_append_to(
      chat.stream_key,
      target: "message_#{id}_content",
      content: ERB::Util.html_escape(content.to_s)
    )
  end
end

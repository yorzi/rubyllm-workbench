class Message < ApplicationRecord
  acts_as_message

  before_save :assert_agent_execution_lease

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

  private

  def assert_agent_execution_lease
    token = Ai::ExecutionContext.agent_execution_token
    generation = Ai::ExecutionContext.agent_execution_generation
    return if token.blank? || generation.nil?

    run = Run.find_by(id: Ai::ExecutionContext.run_id, chat_id: chat_id, operation: "agent")
    raise Ai::ExecutionContext::ExecutionLeaseLost, "the Agent Run no longer owns its chat transcript" unless run

    run.with_lock do
      run.reload
      run.assert_agent_execution_lease!(token:, generation:)
    end
  end
end

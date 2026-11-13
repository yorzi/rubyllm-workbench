module Ai
  class ToolErrorFinalizer
    def initialize(chat, error, run:)
      @chat = chat
      @error = error
      @run = run
    end

    def call
      return unless @chat.respond_to?(:record_local_tool_error!)

      unresolved_tool_calls.each do |tool_call|
        @chat.record_local_tool_error!(
          tool_call,
          error: "Local tool execution failed: #{safe_error_message}",
          error_class: @error.class.name
        )
      end
    rescue StandardError => error
      Rails.logger.warn("Tool error finalization failed: #{error.class}: #{error.message}")
    end

    private

    def unresolved_tool_calls
      return [] unless @chat.respond_to?(:messages)

      RubyLLM::ActiveRecord::ToolCall.where(
        message_type: Message.polymorphic_name,
        message_id: @chat.messages.select(:id),
        result_id: nil,
        remote: false,
        tool_call_id: @run.tool_invocations.where(status: :running, remote: false).select(:tool_call_id)
      ).to_a
    end

    def safe_error_message
      Ai::ErrorText.safe(@error.message)
    end
  end
end

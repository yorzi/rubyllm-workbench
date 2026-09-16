module Ai
  class ToolErrorFinalizer
    def initialize(chat, error)
      @chat = chat
      @error = error
    end

    def call
      return unless @chat.respond_to?(:add_message)

      unresolved_tool_calls.each do |tool_call|
        @chat.add_message(
          role: :tool,
          content: JSON.generate(
            "error" => "Local tool execution failed: #{safe_error_message}",
            "error_class" => @error.class.name
          ),
          tool_call_id: tool_call.tool_call_id
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
        result_id: nil
      ).to_a
    end

    def safe_error_message
      @error.message.to_s.gsub(/\b(sk|rk|xai|AIza|gsk|pplx|r8)_[A-Za-z0-9_-]{12,}\b/i, "[REDACTED]").truncate(2_000)
    end
  end
end

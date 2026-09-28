module Ai
  class ChatContextSnapshot
    FORMAT_VERSION = 1

    class ContextChanged < StandardError
    end

    def self.call(chat)
      new(chat).call
    end

    def self.message_document(message)
      new(nil).message_document(message)
    end

    def initialize(chat)
      @chat = chat
    end

    def call
      # Read persisted messages directly so capture is independent of the
      # memoized RubyLLM Chat and can run before provider credentials are used.
      messages = @chat.messages.reload.map(&:to_llm)
      {
        "format_version" => FORMAT_VERSION,
        "capture_point" => "before_run_prompt",
        "messages" => messages.map { |message| message_document(message) },
        "attachments_included" => false,
        "attachment_payloads_omitted" => messages.any? { |message| message.attachments.any? }
      }
    end

    def message_document(message)
      {
        "role" => message.role.to_s,
        "content" => message.content,
        "thinking_text" => message.thinking&.text,
        "thinking_signature" => message.thinking&.signature,
        "citations" => message.citations.map(&:to_h),
        "tool_call_id" => message.tool_call_id,
        "tool_calls" => message.tool_calls&.values&.map(&:to_h),
        "server_tool_calls" => message.server_tool_calls.map(&:to_h),
        "raw_content" => message.raw_content,
        "raw_reasoning" => message.raw_reasoning,
        "finish_reason" => message.finish_reason&.to_s,
        "cache_until_here" => message.cache_until_here?,
        "attachments" => message.attachments.map { |attachment| attachment_document(attachment) }
      }.compact.deep_stringify_keys
    end

    private

    def attachment_document(attachment)
      source = attachment.source
      blob = case source
      when ActiveStorage::Blob then source
      when ActiveStorage::Attachment then source.blob
      else
        source.blob if source.respond_to?(:blob)
      end

      {
        "filename" => attachment.filename,
        "mime_type" => attachment.mime_type,
        "category" => attachment.type.to_s,
        "byte_size" => blob&.byte_size,
        "checksum" => blob&.checksum,
        "included" => false
      }.compact
    end
  end
end

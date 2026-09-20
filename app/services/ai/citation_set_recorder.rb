module Ai
  class CitationSetRecorder
    def initialize(run:, attempt:, response:, source_message_id: nil)
      @run = run
      @attempt = attempt
      @response = response
      @source_message_id = source_message_id
    end

    def call
      citations = normalized_citations
      return if citations.empty?

      @run.artifacts.create!(
        attempt: @attempt,
        kind: "citation_set",
        name: "Provider citations",
        content_text: JSON.pretty_generate(citations),
        content_json: citations,
        metadata_json: {
          "provider" => @run.chat.provider.to_s,
          "model_id" => @run.chat.model_id.to_s,
          "source_message_id" => source_message_id,
          "citation_count" => citations.size,
          "provider_tools" => Array(@run.input_snapshot["provider_tools"])
        }
      )
    end

    private

    def normalized_citations
      return [] unless @response.respond_to?(:citations)

      Array(@response.citations).filter_map do |citation|
        value = citation.respond_to?(:to_h) ? citation.to_h : citation
        sanitized = Ai::ToolPayloadSanitizer.call(value)
        sanitized if sanitized.is_a?(Hash) && sanitized.present?
      end
    end

    def source_message_id
      @source_message_id || @run.chat.messages.where(role: "assistant").reorder(id: :desc).pick(:id)
    end
  end
end

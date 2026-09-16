require "digest"

module Ai
  module Knowledge
    class Ingestor
      class Error < StandardError; end

      def self.call(item)
        new(item).call
      end

      def initialize(item)
        @item = item
      end

      def call
        chunks = Chunker.call(@item.content_text)
        raise Error, "Source text did not produce any searchable chunks." if chunks.empty?

        @item.transaction do
          @item.update!(
            ingestion_status: :ingesting,
            checksum: Digest::SHA256.hexdigest(@item.content_text.to_s),
            error_summary: nil
          )
          @item.knowledge_chunks.delete_all
          chunks.each do |chunk|
            @item.knowledge_chunks.create!(
              position: chunk.position,
              content_text: chunk.content_text,
              char_start: chunk.char_start,
              char_end: chunk.char_end,
              metadata_json: { "chunker" => "char_window_v1" }
            )
          end
          @item.update!(ingestion_status: :ready)
        end

        @item
      rescue StandardError => error
        mark_failed(error)
        raise error if error.is_a?(Error)

        raise Error, "Source ingestion failed: #{error.message.to_s.truncate(500)}"
      end

      private

      def mark_failed(error)
        return unless @item.persisted?

        @item.update_columns(
          ingestion_status: "failed",
          error_summary: error.message.to_s.truncate(2_000),
          updated_at: Time.current
        )
      rescue ActiveRecord::ActiveRecordError
        nil
      end
    end
  end
end

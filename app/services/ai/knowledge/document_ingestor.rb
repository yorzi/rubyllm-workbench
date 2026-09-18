module Ai
  module Knowledge
    # Extracts an attached file, records the provenance Artifact, then hands
    # the extracted text to the existing chunking pipeline.
    #
    # The Artifact is the durable provenance record: it keeps the extractor,
    # provider/model, page count, byte size and blob checksum next to the text
    # that was actually indexed, so a chunk can always be traced back to the
    # file and the extraction that produced it.
    class DocumentIngestor
      class Error < StandardError; end

      def self.call(item, client: RubyLLM, ocr_model_id: nil)
        new(item, client: client, ocr_model_id: ocr_model_id).call
      end

      def initialize(item, client:, ocr_model_id:)
        @item = item
        @client = client
        @ocr_model_id = ocr_model_id.presence
      end

      def call
        @item.update!(extraction_status: :extracting, extraction_error: nil)

        extracted = Ai::Knowledge::Extractor.call(@item, client: @client, ocr_model_id: @ocr_model_id)

        @item.transaction do
          @item.update!(
            content_text: extracted.text,
            extractor: extracted.extractor,
            extracted_at: Time.current,
            extraction_status: :ready,
            extraction_error: nil,
            extraction_metadata_json: extracted.metadata.merge(
              "filename" => @item.document.filename.to_s,
              "blob_checksum" => blob_checksum,
              "source_kind" => "file"
            )
          )

          @item.artifacts.create!(
            kind: "ocr_document",
            name: "Extraction · #{@item.document.filename}",
            content_text: extracted.text,
            metadata_json: {
              "extractor" => extracted.extractor,
              "provider" => extracted.provider,
              "model_id" => extracted.model_id,
              "page_count" => extracted.pages,
              "filename" => @item.document.filename.to_s,
              "content_type" => @item.document.content_type.to_s,
              "bytes" => @item.document.byte_size,
              "blob_checksum" => blob_checksum,
              "content_checksum" => @item.checksum,
              "knowledge_item_id" => @item.id,
              "extracted_at" => Time.current.iso8601
            }.compact
          )

          Ai::Knowledge::Ingestor.call(@item)
        end

        @item
      rescue Ai::Knowledge::Extractor::Unsupported, Ai::Knowledge::Extractor::Error => error
        mark_failed(error)
        raise error if error.is_a?(Ai::Knowledge::Extractor::Unsupported)

        raise Error, error.message
      rescue StandardError => error
        mark_failed(error)
        raise Error, "Document ingestion failed: #{Ai::ErrorText.safe(error.message, limit: 500)}"
      end

      private

      def mark_failed(error)
        @item.update_columns(
          extraction_status: "failed",
          extraction_error: Ai::ErrorText.safe(error.message, limit: 500),
          updated_at: Time.current
        )
      rescue ActiveRecord::ActiveRecordError
        nil
      end

      def blob_checksum
        @item.document.blob.checksum
      end
    end
  end
end

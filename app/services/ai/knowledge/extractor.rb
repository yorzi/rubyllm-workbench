module Ai
  module Knowledge
    # Turns an attached file into text, locally when possible and through a
    # provider OCR model when it is not.
    #
    # The application keeps durable artifacts with provenance, so every extraction
    # records where the text came from: local reader, or provider + model +
    # page count. Nothing here guesses at a binary's contents.
    class Extractor
      class Error < StandardError; end
      class Unsupported < Error; end

      MAX_BYTES = 10.megabytes
      MAX_ERROR_LENGTH = 500

      LOCALLY_EXTRACTABLE_TYPES = %w[
        text/plain text/markdown text/x-markdown text/csv application/json
        application/x-yaml text/yaml text/tab-separated-values
      ].freeze
      LOCALLY_EXTRACTABLE_EXTENSIONS = %w[txt md markdown csv json yaml yml tsv log].freeze

      OCR_EXTRACTABLE_TYPES = %w[application/pdf image/png image/jpeg image/jpg image/tiff image/webp].freeze
      OCR_EXTRACTABLE_EXTENSIONS = %w[pdf png jpg jpeg tiff tif webp].freeze

      Extracted = Data.define(:text, :extractor, :model_id, :provider, :pages, :metadata)

      def self.call(item, client: RubyLLM, ocr_model_id: nil)
        new(item, client: client, ocr_model_id: ocr_model_id).call
      end

      def initialize(item, client:, ocr_model_id:)
        @item = item
        @client = client
        @ocr_model_id = ocr_model_id.presence
      end

      def call
        raise Error, "This source is not a file source." unless @item.file_source?
        raise Error, "No file is attached to this source." unless @item.document.attached?

        validate_size!

        if locally_extractable?
          extract_locally
        elsif ocr_extractable?
          extract_with_ocr
        else
          raise Unsupported, "Unsupported attachment type #{content_type.inspect}; allowed local types are #{LOCALLY_EXTRACTABLE_TYPES.join(', ')} and OCR types are #{OCR_EXTRACTABLE_TYPES.join(', ')}."
        end
      end

      private

      def extract_locally
        raw = @item.document.download.to_s
        text = raw.force_encoding("UTF-8")
        text = text.scrub("").gsub("\u0000", "") unless text.valid_encoding?

        raise Error, "The attached file contained no extractable text." if text.strip.blank?

        Extracted.new(
          text: text,
          extractor: "local_text",
          model_id: nil,
          provider: nil,
          pages: nil,
          metadata: { "content_type" => content_type, "bytes" => byte_size }
        )
      end

      def extract_with_ocr
        availability = Ai::Knowledge::OcrCatalog.availability(@ocr_model_id)
        raise Unsupported, availability.reason unless availability.available

        entry = availability.entry
        result = @client.ocr(@item.document, model: entry.id, provider: entry.provider)
        pages = result.respond_to?(:pages) ? Array(result.pages) : []
        text = pages.filter_map { |page| page.respond_to?(:markdown) ? page.markdown : nil }.join("\n\n")
        text = result.markdown.to_s if text.blank? && result.respond_to?(:markdown)

        raise Error, "The OCR model returned no extractable text." if text.strip.blank?

        Extracted.new(
          text: text,
          extractor: "ruby_llm_ocr",
          model_id: entry.id.to_s,
          provider: entry.provider.to_s,
          pages: pages.length,
          metadata: {
            "content_type" => content_type,
            "bytes" => byte_size,
            "provider" => entry.provider.to_s,
            "model_id" => entry.id.to_s,
            "page_count" => pages.length
          }
        )
      rescue Unsupported
        raise
      rescue StandardError => error
        raise error if error.is_a?(Error)

        raise Error, "OCR failed: #{Ai::ErrorText.safe(error.message, limit: MAX_ERROR_LENGTH)}"
      end

      def locally_extractable?
        LOCALLY_EXTRACTABLE_TYPES.include?(content_type) || LOCALLY_EXTRACTABLE_EXTENSIONS.include?(extension)
      end

      def ocr_extractable?
        OCR_EXTRACTABLE_TYPES.include?(content_type) || OCR_EXTRACTABLE_EXTENSIONS.include?(extension)
      end

      def validate_size!
        return if byte_size.to_i <= MAX_BYTES

        raise Unsupported, "Attachment is #{(byte_size.to_f / 1.megabyte).round(1)} MB; the bounded V0 limit is #{MAX_BYTES / 1.megabyte} MB."
      end

      def content_type
        @item.document.content_type.to_s
      end

      def extension
        File.extname(@item.document.filename.to_s).delete(".").downcase
      end

      def byte_size
        @item.document.byte_size
      end
    end
  end
end

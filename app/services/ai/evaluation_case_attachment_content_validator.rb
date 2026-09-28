require "csv"
require "json"
require "stringio"

module Ai
  class EvaluationCaseAttachmentContentValidator
    MAX_FILE_BYTES = EvaluationDatasetCaseAttachment::MAX_FILE_BYTES
    GENERIC_CONTENT_TYPES = [ "", "application/octet-stream" ].freeze
    TYPES_BY_EXTENSION = {
      ".json" => "application/json",
      ".pdf" => "application/pdf",
      ".jpg" => "image/jpeg",
      ".jpeg" => "image/jpeg",
      ".png" => "image/png",
      ".csv" => "text/csv",
      ".txt" => "text/plain"
    }.freeze
    PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b.freeze
    JPEG_SIGNATURE = "\xFF\xD8\xFF".b.freeze
    PDF_HEADER = "%PDF-".b.freeze
    INVALID_TEXT_CONTROL_BYTES = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/n

    def self.valid?(io:, content_type:, filename:)
      new(io:, content_type:, filename:).valid?
    end

    def initialize(io:, content_type:, filename:)
      @io = io
      declared_type = content_type.to_s.split(";", 2).first.to_s.strip.downcase
      @content_type = if EvaluationDatasetCaseAttachment::ALLOWED_CONTENT_TYPES.include?(declared_type)
        declared_type
      elsif GENERIC_CONTENT_TYPES.include?(declared_type)
        TYPES_BY_EXTENSION[File.extname(filename.to_s).downcase]
      end
    end

    def supported?
      !@content_type.nil?
    end

    def valid?
      return false unless supported?

      position = @io.pos if @io.respond_to?(:pos)
      @io.rewind
      bytes = @io.read(MAX_FILE_BYTES + 1).to_s.b
      return false if bytes.empty? || bytes.bytesize > MAX_FILE_BYTES

      case @content_type
      when "application/json"
        valid_json?(bytes)
      when "application/pdf"
        bytes.byteslice(0, 1_024)&.include?(PDF_HEADER)
      when "image/jpeg"
        bytes.start_with?(JPEG_SIGNATURE)
      when "image/png"
        bytes.start_with?(PNG_SIGNATURE)
      when "text/csv"
        valid_csv?(bytes)
      when "text/plain"
        valid_text?(bytes)
      else
        false
      end
    rescue CSV::MalformedCSVError, JSON::ParserError, EncodingError
      false
    ensure
      @io.seek(position) if position && @io.respond_to?(:seek)
    end

    private

    def valid_json?(bytes)
      text = utf8_text(bytes)
      return false unless text

      JSON.parse(text)
      true
    end

    def valid_csv?(bytes)
      text = utf8_text(bytes)
      return false unless text

      CSV.new(StringIO.new(text)).each { |_row| }
      true
    end

    def valid_text?(bytes)
      !utf8_text(bytes).nil?
    end

    def utf8_text(bytes)
      return if bytes.match?(INVALID_TEXT_CONTROL_BYTES)

      text = bytes.dup.force_encoding(Encoding::UTF_8)
      text if text.valid_encoding?
    end
  end
end

module Ai
  module Knowledge
    class Chunker
      Chunk = Data.define(:position, :content_text, :char_start, :char_end)
      DEFAULT_MAX_CHARS = 800
      DEFAULT_OVERLAP_CHARS = 120

      def self.call(text, max_chars: DEFAULT_MAX_CHARS, overlap_chars: DEFAULT_OVERLAP_CHARS)
        new(text, max_chars:, overlap_chars:).call
      end

      def initialize(text, max_chars:, overlap_chars:)
        @text = text.to_s.gsub(/\r\n?/, "\n").strip
        @max_chars = max_chars.to_i
        @overlap_chars = overlap_chars.to_i
        validate_options!
      end

      def call
        chunks = []
        offset = 0

        while offset < @text.length
          end_offset = chunk_end(offset)
          content_start = first_content_offset(offset, end_offset)
          content_end = last_content_offset(offset, end_offset)
          content = @text[content_start...content_end].to_s

          chunks << Chunk.new(
            position: chunks.length,
            content_text: content,
            char_start: content_start,
            char_end: content_end
          ) if content.present?

          break if end_offset >= @text.length

          next_offset = end_offset - @overlap_chars
          offset = [ next_offset, offset + 1 ].max
        end

        chunks
      end

      private

      def validate_options!
        raise ArgumentError, "max_chars must be positive" unless @max_chars.positive?
        raise ArgumentError, "overlap_chars must be smaller than max_chars" unless @overlap_chars >= 0 && @overlap_chars < @max_chars
      end

      def chunk_end(offset)
        hard_end = [ offset + @max_chars, @text.length ].min
        return hard_end if hard_end == @text.length

        boundary = @text.rindex(/\s/, hard_end - 1)
        boundary && boundary > offset + (@max_chars / 2) ? boundary : hard_end
      end

      def first_content_offset(offset, end_offset)
        leading = @text[offset...end_offset].to_s.index(/\S/)
        leading ? offset + leading : end_offset
      end

      def last_content_offset(offset, end_offset)
        trailing = @text[offset...end_offset].to_s.rindex(/\S/)
        trailing ? offset + trailing + 1 : offset
      end
    end
  end
end

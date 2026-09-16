module Ai
  module Knowledge
    class Retriever
      Result = Data.define(:chunk, :score, :matched_terms)
      DEFAULT_LIMIT = 8
      MAX_LIMIT = 20

      def self.search(collection:, query:, limit: DEFAULT_LIMIT)
        new(collection:, query:, limit:).search
      end

      def initialize(collection:, query:, limit:)
        @collection = collection
        @query = query.to_s
        @limit = [ limit.to_i, 1 ].max.clamp(1, MAX_LIMIT)
      end

      def search
        terms = tokenize(@query)
        return [] if terms.empty?

        @collection.knowledge_chunks
          .joins(:knowledge_item)
          .where(knowledge_items: { ingestion_status: "ready" })
          .includes(:knowledge_item)
          .filter_map { |chunk| score_chunk(chunk, terms) }
          .sort_by { |result| [ -result.score, result.chunk.knowledge_item_id, result.chunk.position ] }
          .first(@limit)
      end

      private

      def score_chunk(chunk, terms)
        normalized_content = normalize(chunk.content_text)
        term_counts = tokenize(normalized_content).tally
        matched_terms = terms.select { |term| term_counts.key?(term) }
        return if matched_terms.empty?

        coverage = matched_terms.length.to_f / terms.length
        frequency = matched_terms.sum { |term| [ term_counts.fetch(term), 3 ].min }.to_f
        frequency_score = frequency / [ terms.length * 3, 1 ].max
        phrase_bonus = normalized_content.include?(normalize(@query)) ? 0.25 : 0.0
        score = (coverage * 0.7) + (frequency_score * 0.25) + phrase_bonus

        Result.new(chunk:, score: score.round(4), matched_terms: matched_terms)
      end

      def tokenize(value)
        normalize(value).scan(/[\p{L}\p{N}_]+/).uniq
      end

      def normalize(value)
        value.to_s.unicode_normalize(:nfkc).downcase
      end
    end
  end
end

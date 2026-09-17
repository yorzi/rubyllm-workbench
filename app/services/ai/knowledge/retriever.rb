module Ai
  module Knowledge
    class Retriever
      MODES = %w[lexical semantic hybrid].freeze
      Result = Data.define(:chunk, :score, :matched_terms, :lexical_score, :similarity)
      DEFAULT_LIMIT = 8
      MAX_LIMIT = 20

      attr_reader :stale_count

      def self.search(collection:, query:, limit: DEFAULT_LIMIT, mode: "lexical", query_vector: nil, model_id: nil)
        new(collection:, query:, limit:, mode:, query_vector:, model_id:).search
      end

      def initialize(collection:, query:, limit:, mode:, query_vector:, model_id:)
        @collection = collection
        @query = query.to_s
        @limit = [ limit.to_i, 1 ].max.clamp(1, MAX_LIMIT)
        @mode = MODES.include?(mode.to_s) ? mode.to_s : "lexical"
        @query_vector = Array(query_vector)
        @model_id = model_id.presence
        @stale_count = 0
      end

      def search
        case @mode
        when "semantic" then semantic_results
        when "hybrid" then hybrid_results
        else lexical_results
        end
      end

      def semantic?
        @mode == "semantic"
      end

      private

      def lexical_results
        lexical_matches.sort_by { |chunk, score, _| [ -score, chunk.knowledge_item_id, chunk.position ] }
          .first(@limit)
          .map do |chunk, score, terms|
            Result.new(chunk:, score: score.round(4), matched_terms: terms, lexical_score: score.round(4), similarity: nil)
          end
      end

      def semantic_results
        require_semantic_inputs!

        VectorStore.default.rank(query_vector: @query_vector, candidates: embedding_candidates, limit: @limit)
          .map do |embedding, similarity|
            chunk = embedding.knowledge_chunk
            Result.new(chunk:, score: similarity.round(4), matched_terms: [], lexical_score: nil, similarity: similarity.round(4))
          end
      end

      def hybrid_results
        lexical = lexical_matches.first(MAX_LIMIT).to_h { |chunk, score, terms| [ chunk.id, [ chunk, score, terms ] ] }
        semantic = semantic_available? ? semantic_matches(MAX_LIMIT).to_h { |embedding, similarity| [ embedding.knowledge_chunk_id, similarity ] } : {}

        max_lexical = lexical.values.map { |_, score, _| score }.max || 0.0
        similarities = semantic.values.compact
        min_similarity = similarities.min
        max_similarity = similarities.max

        candidates = (lexical.keys + semantic.keys).uniq
        chunks_by_id = KnowledgeChunk.where(id: candidates).includes(:knowledge_item).index_by(&:id)

        candidates.filter_map do |chunk_id|
          chunk = lexical.dig(chunk_id, 0) || chunks_by_id[chunk_id]
          next if chunk.nil?

          lexical_score = lexical.dig(chunk_id, 1)
          similarity = semantic[chunk_id]
          score = 0.5 * normalize_lexical(lexical_score, max_lexical) +
            0.5 * normalize_similarity(similarity, min_similarity, max_similarity)

          Result.new(
            chunk:,
            score: score.round(4),
            matched_terms: lexical.dig(chunk_id, 2) || [],
            lexical_score: lexical_score&.round(4),
            similarity: similarity&.round(4)
          )
        end.sort_by { |result| [ -result.score, result.chunk.knowledge_item_id, result.chunk.position ] }.first(@limit)
      end

      def normalize_lexical(score, max_lexical)
        return 0.0 if score.blank? || max_lexical.to_f.zero?

        score.to_f / max_lexical
      end

      def normalize_similarity(similarity, min_similarity, max_similarity)
        return 0.0 if similarity.blank?
        return 0.5 if min_similarity.nil? || max_similarity.nil? || (max_similarity - min_similarity).abs < 1e-9

        (similarity - min_similarity) / (max_similarity - min_similarity)
      end

      def lexical_matches
        terms = tokenize(@query)
        return [] if terms.empty?

        ready_chunks.filter_map { |chunk| score_chunk(chunk, terms) }
          .sort_by { |chunk, score, _| [ -score, chunk.knowledge_item_id, chunk.position ] }
      end

      def semantic_matches(limit)
        VectorStore.default.rank(query_vector: @query_vector, candidates: embedding_candidates, limit: limit)
          .map { |embedding, similarity| [ embedding, similarity ] }
      end

      def semantic_available?
        @query_vector.present? && @model_id.present?
      end

      def require_semantic_inputs!
        raise ArgumentError, "semantic retrieval requires a query vector" if @query_vector.empty?
        raise ArgumentError, "semantic retrieval requires an embedding model id" if @model_id.blank?

        true
      end

      def embedding_candidates
        KnowledgeEmbedding.ready
          .for_model(@model_id)
          .joins(knowledge_chunk: :knowledge_item)
          .where(knowledge_items: { ingestion_status: "ready", knowledge_collection_id: @collection.id })
          .includes(:knowledge_chunk)
          .to_a
          .select { |embedding| fresh?(embedding) }
      end

      def fresh?(embedding)
        return true if embedding.content_checksum.blank?
        return true if embedding.content_checksum == embedding.knowledge_chunk.content_checksum

        @stale_count += 1
        false
      end

      def ready_chunks
        @collection.knowledge_chunks
          .joins(:knowledge_item)
          .where(knowledge_items: { ingestion_status: "ready" })
          .includes(:knowledge_item)
      end

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

        [ chunk, score, matched_terms ]
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

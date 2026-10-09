module Ai
  module Knowledge
    # Resolves one knowledge search request into inspectable evidence.
    #
    # Semantic and hybrid modes need a configured embedding model, stored
    # embeddings and a query vector. When any of those is missing the search
    # degrades to lexical retrieval and reports the reason instead of quietly
    # returning lexical evidence labelled as semantic.
    #
    # Reranking is an optional second stage gated on provider compatibility. It
    # only reorders evidence: when it is unavailable or fails, the original
    # retrieval evidence is returned unchanged with an explicit note.
    class Search
      MODES = Ai::Knowledge::Retriever::MODES

      Outcome = Data.define(
        :results,
        :mode,
        :requested_mode,
        :degraded_reason,
        :embedding_model_id,
        :embedding_provider,
        :dimensions,
        :embedded_chunk_count,
        :stale_count,
        :query,
        :adapter_key,
        :adapter_note,
        :rerank_model_id,
        :rerank_note,
        :rerank_applied
      )

      RerankState = Data.define(:results, :model_id, :note, :applied)

      def self.call(collection:, query:, mode: "lexical", limit: Ai::Knowledge::Retriever::DEFAULT_LIMIT,
                    embedding_model_id: nil, rerank: false, rerank_model_id: nil, client: RubyLLM)
        new(collection:, query:, mode:, limit:, embedding_model_id:, rerank:, rerank_model_id:, client:).call
      end

      def initialize(collection:, query:, mode:, limit:, embedding_model_id:, rerank:, rerank_model_id:, client:)
        @collection = collection
        @query = query.to_s
        @limit = limit
        @requested_mode = MODES.include?(mode.to_s) ? mode.to_s : "lexical"
        @embedding_model_id = embedding_model_id.presence || collection.embedding_model_id.presence
        @embedding_provider = collection.embedding_provider.presence if @embedding_model_id == collection.embedding_model_id
        @rerank = rerank.to_s.in?(%w[1 true]) || rerank == true
        @rerank_model_id = rerank_model_id.presence
        @client = client
      end

      def call
        return empty_outcome if @query.strip.blank?


        resolution = resolve_mode
        retriever = Ai::Knowledge::Retriever.new(
          collection: @collection,
          query: @query,
          limit: @limit,
          mode: resolution[:mode],
          query_vector: resolution[:query_vector],
          model_id: @embedding_model_id,
          provider: @embedding_provider
        )
        results = retriever.search
        rerank_state = apply_rerank(results)

        Outcome.new(
          results: rerank_state.results,
          mode: resolution[:mode],
          requested_mode: @requested_mode,
          degraded_reason: resolution[:degraded_reason],
          embedding_model_id: @embedding_model_id,
          embedding_provider: @embedding_provider,
          dimensions: @collection.embedding_dimensions,
          embedded_chunk_count: @collection.embedded_chunk_count(model_id: @embedding_model_id, provider: @embedding_provider),
          stale_count: retriever.stale_count,
          query: @query,
          adapter_key: selection.key,
          adapter_note: selection.note,
          rerank_model_id: rerank_state.model_id,
          rerank_note: rerank_state.note,
          rerank_applied: rerank_state.applied
        )
      end

      private

      def apply_rerank(results)
        return RerankState.new(results: results, model_id: nil, note: nil, applied: false) unless @rerank
        return skipped(results, "No rerank model is selected.") if @rerank_model_id.blank?

        availability = Ai::Knowledge::RerankCatalog.availability(@rerank_model_id)
        return skipped(results, availability.reason) unless availability.available
        return skipped(results, "No evidence to rerank.") if results.empty?

        rerank_results(results)
      rescue Ai::Knowledge::Reranker::Error => error
        skipped(results, error.message)
      end

      def rerank_results(results)
        ranked = Ai::Knowledge::Reranker.call(
          query: @query,
          documents: results.map { |result| result.chunk.content_text },
          model_id: @rerank_model_id,
          client: @client
        )

        ordered = ranked.filter_map do |row|
          result = results[row.index]
          next if result.nil?

          Ai::Knowledge::Retriever::Result.new(
            chunk: result.chunk,
            score: result.score,
            matched_terms: result.matched_terms,
            lexical_score: result.lexical_score,
            similarity: result.similarity,
            rerank_score: row.score.round(4),
            pre_rank: row.index
          )
        end

        return skipped(results, "Rerank model returned no usable ranking.") if ordered.empty?

        RerankState.new(results: ordered, model_id: @rerank_model_id, note: nil, applied: true)
      end

      def skipped(results, note)
        RerankState.new(results: results, model_id: @rerank ? @rerank_model_id : nil, note: note, applied: false)
      end

      def selection
        Ai::Knowledge::VectorStore.selection
      end

      def empty_outcome
        Outcome.new(
          results: [],
          mode: @requested_mode,
          requested_mode: @requested_mode,
          degraded_reason: nil,
          embedding_model_id: @embedding_model_id,
          embedding_provider: @embedding_provider,
          dimensions: @collection.embedding_dimensions,
          embedded_chunk_count: @collection.embedded_chunk_count(model_id: @embedding_model_id, provider: @embedding_provider),
          stale_count: 0,
          query: @query,
          adapter_key: selection.key,
          adapter_note: selection.note,
          rerank_model_id: nil,
          rerank_note: nil,
          rerank_applied: false
        )
      end

      def resolve_mode
        return { mode: "lexical", query_vector: nil, degraded_reason: nil } if @requested_mode == "lexical"

        if @embedding_model_id.blank?
          return degraded("No embedding model is selected for this collection.")
        end

        availability = Ai::Knowledge::EmbeddingCatalog.availability(@embedding_model_id, provider: @embedding_provider)
        return degraded(availability.reason) unless availability.available
        @embedding_provider = availability.entry.provider
        return degraded("No embeddings are stored for #{@embedding_model_id} yet.") unless @collection.semantic_searchable?(model_id: @embedding_model_id, provider: @embedding_provider)

        { mode: @requested_mode, query_vector: embed_query, degraded_reason: nil }
      rescue Ai::Knowledge::Embedder::Error => error
        degraded(error.message)
      end

      def degraded(reason)
        { mode: "lexical", query_vector: nil, degraded_reason: reason }
      end

      def embed_query
        Ai::Knowledge::Embedder.embed_text(@query, model_id: @embedding_model_id, provider: @embedding_provider, client: @client)
      end
    end
  end
end

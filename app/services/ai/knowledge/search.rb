module Ai
  module Knowledge
    # Resolves one knowledge search request into inspectable evidence.
    #
    # Semantic and hybrid modes need a configured embedding model, stored
    # embeddings and a query vector. When any of those is missing the search
    # degrades to lexical retrieval and reports the reason instead of quietly
    # returning lexical evidence labelled as semantic.
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
        :query
      )

      def self.call(collection:, query:, mode: "lexical", limit: Ai::Knowledge::Retriever::DEFAULT_LIMIT,
                    embedding_model_id: nil, client: RubyLLM)
        new(collection:, query:, mode:, limit:, embedding_model_id:, client:).call
      end

      def initialize(collection:, query:, mode:, limit:, embedding_model_id:, client:)
        @collection = collection
        @query = query.to_s
        @limit = limit
        @requested_mode = MODES.include?(mode.to_s) ? mode.to_s : "lexical"
        @embedding_model_id = embedding_model_id.presence || collection.embedding_model_id.presence
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
          model_id: @embedding_model_id
        )
        results = retriever.search

        Outcome.new(
          results: results,
          mode: resolution[:mode],
          requested_mode: @requested_mode,
          degraded_reason: resolution[:degraded_reason],
          embedding_model_id: @embedding_model_id,
          embedding_provider: @collection.embedding_provider,
          dimensions: @collection.embedding_dimensions,
          embedded_chunk_count: @collection.embedded_chunk_count(model_id: @embedding_model_id),
          stale_count: retriever.stale_count,
          query: @query
        )
      end

      private

      def empty_outcome
        Outcome.new(
          results: [],
          mode: @requested_mode,
          requested_mode: @requested_mode,
          degraded_reason: nil,
          embedding_model_id: @embedding_model_id,
          embedding_provider: @collection.embedding_provider,
          dimensions: @collection.embedding_dimensions,
          embedded_chunk_count: @collection.embedded_chunk_count(model_id: @embedding_model_id),
          stale_count: 0,
          query: @query
        )
      end

      def resolve_mode
        return { mode: "lexical", query_vector: nil, degraded_reason: nil } if @requested_mode == "lexical"

        if @embedding_model_id.blank?
          return degraded("No embedding model is selected for this collection.")
        end

        availability = Ai::Knowledge::EmbeddingCatalog.availability(@embedding_model_id)
        return degraded(availability.reason) unless availability.available
        return degraded("No embeddings are stored for #{@embedding_model_id} yet.") unless @collection.semantic_searchable?(model_id: @embedding_model_id)

        { mode: @requested_mode, query_vector: embed_query, degraded_reason: nil }
      rescue Ai::Knowledge::Embedder::Error => error
        degraded(error.message)
      end

      def degraded(reason)
        { mode: "lexical", query_vector: nil, degraded_reason: reason }
      end

      def embed_query
        Ai::Knowledge::Embedder.embed_text(@query, model_id: @embedding_model_id, client: @client)
      end
    end
  end
end

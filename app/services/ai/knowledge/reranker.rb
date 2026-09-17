module Ai
  module Knowledge
    # Reorders already retrieved evidence with a provider rerank model.
    #
    # Reranking never replaces retrieval evidence: it only produces a new order
    # plus a provider score, and callers keep the original retrieval score and
    # the pre-rerank position so pre/post rank stays inspectable.
    class Reranker
      class Error < StandardError; end
      class ConfigurationError < Error; end

      MAX_ERROR_LENGTH = 500
      MAX_DOCUMENTS = Ai::Knowledge::Retriever::MAX_LIMIT

      Ranked = Data.define(:index, :score)

      def self.call(query:, documents:, model_id:, top_n: nil, client: RubyLLM)
        new(query: query, documents: documents, model_id: model_id, top_n: top_n, client: client).call
      end

      def initialize(query:, documents:, model_id:, top_n:, client:)
        @query = query.to_s
        @documents = Array(documents).first(MAX_DOCUMENTS)
        @model_id = model_id.to_s
        @top_n = top_n
        @client = client
      end

      def call
        availability = Ai::Knowledge::RerankCatalog.availability(@model_id)
        raise ConfigurationError, availability.reason unless availability.available

        entry = availability.entry
        result = @client.rerank(@query, @documents, model: entry.id, provider: entry.provider, top_n: @top_n)
        normalize(result)
      rescue StandardError => error
        raise error if error.is_a?(ConfigurationError) || error.is_a?(Error)

        raise Error, "Reranking failed: #{Ai::ErrorText.safe(error.message, limit: MAX_ERROR_LENGTH)}"
      end

      private

      def normalize(result)
        rows = result.respond_to?(:results) ? Array(result.results) : []
        raise Error, "Rerank model returned no ranked results." if rows.empty?

        rows.filter_map do |row|
          index = row.respond_to?(:index) ? row.index : row[:index]
          score = row.respond_to?(:score) ? row.score : row[:score]
          next if index.nil?

          Ranked.new(index: index.to_i, score: score.to_f)
        end
      end
    end
  end
end

module Ai
  module Knowledge
    # Persists provider embeddings for the ready chunks of a collection.
    #
    # Embeddings are tied to the exact model identifier and the chunk content
    # checksum. Re-embedding the same chunks with the same model replaces their
    # rows; a different model creates its own rows so incompatible dimensions
    # are never mixed inside one retrieval call.
    class Embedder
      class Error < StandardError; end
      class ConfigurationError < Error; end

      BATCH_SIZE = 32
      MAX_ERROR_LENGTH = 500

      Summary = Data.define(:model_id, :provider, :dimensions, :embedded, :failed, :status, :error)

      def self.call(collection:, model_id:, provider: nil, client: RubyLLM, adapter: nil)
        new(collection:, model_id:, provider:, client:, adapter:).call
      end

      def self.embed_text(text, model_id:, provider: nil, client: RubyLLM)
        new(collection: nil, model_id:, provider:, client:).embed_query(text)
      end

      def initialize(collection:, model_id:, provider: nil, client: RubyLLM, adapter: nil)
        @collection = collection
        @model_id = model_id.to_s
        @provider = provider.presence
        @client = client
        @adapter = adapter || Ai::Knowledge::VectorStore.default
        @embedded = 0
        @failed = 0
        @errors = []
        @dimensions = nil
      end

      def call
        availability = Ai::Knowledge::EmbeddingCatalog.availability(@model_id, provider: @provider)
        raise ConfigurationError, availability.reason unless availability.available

        entry = availability.entry
        chunks = ready_chunks
        raise Error, "This collection has no ready chunks to embed." if chunks.empty?

        chunks.each_slice(BATCH_SIZE) { |slice| embed_slice(slice, entry) }

        status = status_for
        persist_collection_state(entry, status)
        raise Error, first_error if status == "failed"

        Summary.new(
          model_id: entry.id,
          provider: entry.provider,
          dimensions: @dimensions,
          embedded: @embedded,
          failed: @failed,
          status: status,
          error: @errors.first
        )
      rescue StandardError => error
        mark_collection_failed(error) unless error.is_a?(ConfigurationError)
        raise error if error.is_a?(ConfigurationError) || error.is_a?(Error)

        raise Error, "Embedding failed: #{Ai::ErrorText.safe(error.message, limit: MAX_ERROR_LENGTH)}"
      end

      def embed_query(text)
        availability = Ai::Knowledge::EmbeddingCatalog.availability(@model_id, provider: @provider)
        raise ConfigurationError, availability.reason unless availability.available

        entry = availability.entry
        result = @client.embed(text.to_s, model: entry.id, provider: entry.provider)
        vector = extract_vector(result.vectors)
        raise Error, "Embedding model #{entry.id} returned no vector for the query." if vector.empty?

        vector
      rescue StandardError => error
        raise error if error.is_a?(ConfigurationError) || error.is_a?(Error)

        raise Error, "Query embedding failed: #{Ai::ErrorText.safe(error.message, limit: MAX_ERROR_LENGTH)}"
      end

      private

      def embed_slice(slice, entry)
        texts = slice.map(&:content_text)
        result = @client.embed(texts, model: entry.id, provider: entry.provider)
        vectors = extract_vectors(result.vectors, slice.length)

        slice.zip(vectors).each do |chunk, vector|
          persist_chunk(chunk, vector, entry, usage: usage_for(result))
        end
      rescue StandardError => error
        record_error(error)
        slice.each { |chunk| embed_single(chunk, entry) }
      end

      def embed_single(chunk, entry)
        result = @client.embed(chunk.content_text, model: entry.id, provider: entry.provider)
        vector = extract_vector(result.vectors)
        raise Error, "no vector returned" if vector.empty?

        persist_chunk(chunk, vector, entry, usage: usage_for(result))
      rescue StandardError => error
        record_error(error)
        @failed += 1
      end

      def persist_chunk(chunk, vector, entry, usage:)
        record = KnowledgeEmbedding.find_or_initialize_by(knowledge_chunk_id: chunk.id, model_id: entry.id.to_s)
        record.assign_attributes(
          provider: entry.provider.to_s,
          dimensions: vector.length,
          vector: @adapter.encode(vector),
          content_checksum: chunk.content_checksum,
          status: :ready,
          input_tokens: usage[:input_tokens],
          reported_cost: usage[:cost],
          metadata_json: {
            "adapter" => @adapter.key,
            "precision" => Ai::Knowledge::VectorStore::SqliteApplicationCosine::PRECISION,
            "provider" => entry.provider.to_s,
            "model_id" => entry.id.to_s,
            "ruby_llm_version" => RubyLLM::VERSION,
            "embedded_at" => Time.current.iso8601
          }
        )
        record.save!

        @dimensions = vector.length if @dimensions.nil?
        @embedded += 1
      rescue StandardError => error
        record_error(error)
        @failed += 1
      end

      def usage_for(result)
        tokens = result.respond_to?(:tokens) ? result.tokens : nil
        cost = result.respond_to?(:cost) ? result.cost : nil
        {
          input_tokens: tokens&.respond_to?(:input) ? tokens.input : nil,
          cost: cost&.respond_to?(:total_cost) ? cost.total_cost : nil
        }
      rescue StandardError
        { input_tokens: nil, cost: nil }
      end

      def extract_vectors(vectors, expected)
        rows = vectors.is_a?(Array) && vectors.first.is_a?(Array) ? vectors : [ vectors ]
        return rows if rows.length == expected

        rows.first(expected)
      end

      def extract_vector(vectors)
        return [] if vectors.blank?

        vectors.first.is_a?(Array) ? vectors.first : Array(vectors)
      end

      def ready_chunks
        @collection.knowledge_chunks
          .joins(:knowledge_item)
          .where(knowledge_items: { ingestion_status: "ready" })
          .includes(:knowledge_item)
          .order(:knowledge_item_id, :position, :id)
          .to_a
      end

      def status_for
        return "failed" if @embedded.zero?
        return "partial" if @failed.positive?

        "ready"
      end

      def first_error
        @errors.first || "No chunk could be embedded."
      end

      def persist_collection_state(entry, status)
        return unless @collection

        @collection.update!(
          embedding_model_id: entry.id.to_s,
          embedding_provider: entry.provider.to_s,
          embedding_dimensions: @dimensions,
          embedding_status: status,
          embedded_at: Time.current,
          embedding_error: status == "ready" ? nil : first_error
        )
      end

      def mark_collection_failed(error)
        return unless @collection

        @collection.update_columns(
          embedding_status: "failed",
          embedding_error: Ai::ErrorText.safe(error.message, limit: MAX_ERROR_LENGTH),
          updated_at: Time.current
        )
      rescue ActiveRecord::ActiveRecordError
        nil
      end

      def record_error(error)
        message = Ai::ErrorText.safe(error.message, limit: MAX_ERROR_LENGTH)
        @errors << message unless @errors.include?(message)
      end
    end
  end
end

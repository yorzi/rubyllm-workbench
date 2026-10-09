require "test_helper"

class Ai::Knowledge::EmbedderTest < ActiveSupport::TestCase
  MODEL_ID = "openai/text-embedding-3-small"

  setup do
    @project = create_project(name: "Embedder project")
    @collection = @project.knowledge_collections.create!(name: "Engineering notes")
  end

  def add_item(title:, text:)
    item = @collection.knowledge_items.create!(title: title, content_text: text)
    Ai::Knowledge::Ingestor.call(item)
    item
  end

  test "embeds ready chunks and records model, dimension and checksum provenance" do
    with_provider_configuration("openrouter") do
      item = add_item(title: "Retrieval notes", text: "SQLite retrieval evidence. " * 12)
      client = FakeEmbeddingClient.new

      summary = Ai::Knowledge::Embedder.call(collection: @collection, model_id: MODEL_ID, client: client)

      assert_equal item.knowledge_chunks.count, summary.embedded
      assert_equal 0, summary.failed
      assert_equal "ready", summary.status
      assert_equal FakeEmbeddingClient::VOCABULARY.length, summary.dimensions
      assert_equal "openrouter", summary.provider

      embedding = @collection.knowledge_embeddings.for_model(MODEL_ID).first
      assert_equal embedding.knowledge_chunk.content_checksum, embedding.content_checksum
      assert_equal "sqlite_application_cosine", embedding.metadata_json["adapter"]
      assert_equal MODEL_ID, embedding.metadata_json["model_id"]

      collection = @collection.reload
      assert_equal MODEL_ID, collection.embedding_model_id
      assert_equal FakeEmbeddingClient::VOCABULARY.length, collection.embedding_dimensions
      assert_equal "ready", collection.embedding_status
      assert collection.semantic_searchable?
    end
  end

  test "mixed vector dimensions produce partial coverage without additional provider requests" do
    with_provider_configuration("openrouter") do
      2.times { |index| add_item(title: "Note #{index}", text: "SQLite retrieval evidence #{index}.") }
      client = Object.new
      requests = 0
      client.define_singleton_method(:embed) do |*args, **options|
        requests += 1
        RubyLLM::Embedding.new(vectors: [ [ 1.0, 0.0 ], [ 1.0, 0.0, 0.0 ] ], model: MODEL_ID, input_tokens: 12)
      end
      summary = Ai::Knowledge::Embedder.call(collection: @collection, model_id: MODEL_ID, client:)
      assert_equal "partial", summary.status
      assert_equal 1, summary.embedded
      assert_equal 1, summary.failed
      assert_equal 2, summary.dimensions
      assert_includes summary.error, "inconsistent"
      assert_equal 1, requests
      assert_equal [ 2 ], @collection.knowledge_embeddings.ready.pluck(:dimensions)
    end
  end

  test "re-embedding with the same model replaces rows instead of duplicating them" do
    with_provider_configuration("openrouter") do
      add_item(title: "Retrieval notes", text: "SQLite retrieval evidence.")

      Ai::Knowledge::Embedder.call(collection: @collection, model_id: MODEL_ID, client: FakeEmbeddingClient.new)
      before = @collection.knowledge_embeddings.for_model(MODEL_ID).pluck(:id, :vector)

      Ai::Knowledge::Embedder.call(collection: @collection, model_id: MODEL_ID, client: FakeEmbeddingClient.new)
      after = @collection.knowledge_embeddings.for_model(MODEL_ID).pluck(:id, :vector)

      assert_equal before.map(&:first), after.map(&:first)
      assert_equal before.map(&:second), after.map(&:second)
    end
  end

  test "refuses an unconfigured or unknown embedding model" do
    with_provider_configuration("openrouter") do
      add_item(title: "Retrieval notes", text: "SQLite retrieval evidence.")

      error = assert_raises(Ai::Knowledge::Embedder::ConfigurationError) do
        Ai::Knowledge::Embedder.call(collection: @collection, model_id: "not-a-real-embedding-model", client: FakeEmbeddingClient.new)
      end
      assert_includes error.message, "not in the RubyLLM catalog"

      unconfigured = Ai::Knowledge::EmbeddingCatalog.entries.reject(&:configured).first&.id || "bedrock-embed"
      error = assert_raises(Ai::Knowledge::Embedder::ConfigurationError) do
        Ai::Knowledge::Embedder.call(collection: @collection, model_id: unconfigured, client: FakeEmbeddingClient.new)
      end
      assert_includes error.message.downcase, "configured"
      assert_equal "none", @collection.reload.embedding_status
    end
  end

  test "marks the collection failed and redacts provider secrets from the error" do
    with_provider_configuration("openrouter") do
      add_item(title: "Retrieval notes", text: "SQLite retrieval evidence.")
      client = FakeEmbeddingClient.new(error: StandardError.new("401 unauthorized for sk-abcdef1234567890abcd"))

      error = assert_raises(Ai::Knowledge::Embedder::Error) do
        Ai::Knowledge::Embedder.call(collection: @collection, model_id: MODEL_ID, client: client)
      end

      assert_includes error.message, "[REDACTED]"
      refute_includes error.message, "sk-abcdef1234567890abcd"

      collection = @collection.reload
      assert_equal "failed", collection.embedding_status
      refute_includes collection.embedding_error.to_s, "sk-abcdef1234567890abcd"
    end
  end

  test "records partial coverage when one chunk cannot be embedded" do
    with_provider_configuration("openrouter") do
      item = add_item(
        title: "Retrieval notes",
        text: ("Alpha section about sqlite retrieval evidence. " * 25) +
          ("Omega marker section about sqlite retrieval evidence. " * 25)
      )
      assert_operator item.knowledge_chunks.count, :>, 1
      client = FakeEmbeddingClient.new(failing_texts: [ "Omega marker" ])

      summary = Ai::Knowledge::Embedder.call(collection: @collection, model_id: MODEL_ID, client: client)

      failing = item.knowledge_chunks.count { |chunk| chunk.content_text.include?("Omega marker") }

      assert_equal "partial", summary.status
      assert_equal failing, summary.failed
      assert_operator summary.embedded, :>, 0
      assert_equal "partial", @collection.reload.embedding_status
      assert_equal item.knowledge_chunks.count - failing, @collection.embedded_chunk_count
    end
  end

  test "refuses a collection without ready chunks" do
    with_provider_configuration("openrouter") do
      error = assert_raises(Ai::Knowledge::Embedder::Error) do
        Ai::Knowledge::Embedder.call(collection: @collection, model_id: MODEL_ID, client: FakeEmbeddingClient.new)
      end

      assert_includes error.message, "no ready chunks"
    end
  end

  test "embed_text returns a query vector for a configured model" do
    with_provider_configuration("openrouter") do
      vector = Ai::Knowledge::Embedder.embed_text("SQLite retrieval", model_id: MODEL_ID, client: FakeEmbeddingClient.new)

      assert_equal FakeEmbeddingClient::VOCABULARY.length, vector.length
      assert_equal [ 1.0, 1.0, 0.0, 0.0, 0.0, 0.0 ], vector
    end
  end

  test "explicit provider is respected for batch and query embeddings" do
    with_provider_configuration("openrouter") do
      add_item(title: "Retrieval notes", text: "SQLite retrieval evidence.")
      client = FakeEmbeddingClient.new

      assert_raises(Ai::Knowledge::Embedder::ConfigurationError) do
        Ai::Knowledge::Embedder.call(collection: @collection, model_id: MODEL_ID, provider: "openai", client: client)
      end
      assert_raises(Ai::Knowledge::Embedder::ConfigurationError) do
        Ai::Knowledge::Embedder.embed_text("query", model_id: MODEL_ID, provider: "openai", client: client)
      end
      assert_empty client.calls
      assert_equal "none", @collection.reload.embedding_status
    end
  end

  test "catalog disambiguates a shared model identifier by provider" do
    with_provider_configuration("openrouter") do
      models = %w[openai openrouter].map do |provider|
        RubyLLM::Model.new(id: "shared-embedding", name: "Shared embedding", provider: provider,
          modalities: { input: [ "text" ], output: [ "embeddings" ] })
      end
      availability = Ai::Knowledge::EmbeddingCatalog.availability("shared-embedding", provider: "openrouter", models: models)

      assert availability.available
      assert_equal "openrouter", availability.entry.provider
    end
  end
end

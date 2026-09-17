require "test_helper"

class Ai::Knowledge::SearchTest < ActiveSupport::TestCase
  MODEL_ID = "openai/text-embedding-3-small"

  setup do
    @project = create_project(name: "Search project")
    @collection = @project.knowledge_collections.create!(name: "Engineering notes")
  end

  def add_item(title:, text:)
    item = @collection.knowledge_items.create!(title: title, content_text: text)
    Ai::Knowledge::Ingestor.call(item)
    item
  end

  test "lexical mode never calls the embedding boundary" do
    add_item(title: "Retrieval notes", text: "SQLite retrieval evidence keeps local search inspectable.")

    outcome = Ai::Knowledge::Search.call(collection: @collection, query: "SQLite retrieval", mode: "lexical")

    assert_equal "lexical", outcome.mode
    assert_nil outcome.degraded_reason
    assert_equal 1, outcome.results.length
    assert_equal 0, outcome.embedded_chunk_count
    assert_nil outcome.embedding_model_id
  end

  test "semantic mode degrades to lexical when no embedding model is selected" do
    add_item(title: "Retrieval notes", text: "SQLite retrieval evidence keeps local search inspectable.")

    outcome = Ai::Knowledge::Search.call(collection: @collection, query: "SQLite retrieval", mode: "semantic")

    assert_equal "lexical", outcome.mode
    assert_equal "semantic", outcome.requested_mode
    assert_includes outcome.degraded_reason, "No embedding model is selected"
    assert_equal 1, outcome.results.length
  end

  test "semantic mode degrades to lexical when the model has no stored embeddings" do
    with_provider_configuration("openrouter") do
      add_item(title: "Retrieval notes", text: "SQLite retrieval evidence keeps local search inspectable.")
      @collection.update!(embedding_model_id: MODEL_ID)

      outcome = Ai::Knowledge::Search.call(collection: @collection, query: "SQLite retrieval", mode: "semantic")

      assert_equal "lexical", outcome.mode
      assert_includes outcome.degraded_reason, "No embeddings are stored"
    end
  end

  test "semantic mode degrades to lexical when the query cannot be embedded" do
    with_provider_configuration("openrouter") do
      add_item(title: "Retrieval notes", text: "SQLite retrieval evidence keeps local search inspectable.")
      @collection.update!(embedding_model_id: MODEL_ID, embedding_status: "ready")
      KnowledgeEmbedding.create!(
        knowledge_chunk: @collection.knowledge_chunks.first,
        provider: "openrouter",
        model_id: MODEL_ID,
        dimensions: 6,
        vector: Ai::Knowledge::VectorStore.default.encode([ 1.0, 1.0, 0.0, 0.0, 0.0, 0.0 ]),
        content_checksum: @collection.knowledge_chunks.first.content_checksum
      )

      outcome = Ai::Knowledge::Search.call(
        collection: @collection,
        query: "SQLite retrieval",
        mode: "semantic",
        client: FakeEmbeddingClient.new(error: StandardError.new("provider unavailable"))
      )

      assert_equal "lexical", outcome.mode
      assert_includes outcome.degraded_reason, "Query embedding failed"
    end
  end

  test "semantic mode returns cosine-ranked evidence when embeddings exist" do
    with_provider_configuration("openrouter") do
      add_item(title: "Retrieval notes", text: ("sqlite retrieval " * 40) + ("sqlite alone " * 40))
      Ai::Knowledge::Embedder.call(collection: @collection, model_id: MODEL_ID, client: FakeEmbeddingClient.new)

      outcome = Ai::Knowledge::Search.call(
        collection: @collection,
        query: "sqlite retrieval",
        mode: "semantic",
        client: FakeEmbeddingClient.new
      )

      assert_equal "semantic", outcome.mode
      assert_nil outcome.degraded_reason
      assert_equal MODEL_ID, outcome.embedding_model_id
      assert_equal @collection.chunk_count, outcome.embedded_chunk_count
      assert_operator outcome.results.length, :>, 0
      assert_in_delta 1.0, outcome.results.first.similarity, 1e-2
      assert_nil outcome.results.first.lexical_score
      assert_equal 0, outcome.stale_count
    end
  end

  test "hybrid mode exposes both signals and unknown modes fall back to lexical" do
    with_provider_configuration("openrouter") do
      add_item(title: "Retrieval notes", text: ("sqlite retrieval " * 40) + ("sqlite alone " * 40))
      Ai::Knowledge::Embedder.call(collection: @collection, model_id: MODEL_ID, client: FakeEmbeddingClient.new)

      hybrid = Ai::Knowledge::Search.call(
        collection: @collection,
        query: "sqlite retrieval",
        mode: "hybrid",
        client: FakeEmbeddingClient.new
      )
      assert_equal "hybrid", hybrid.mode
      assert_operator hybrid.results.first.lexical_score, :>, 0
      assert_operator hybrid.results.first.similarity, :>, 0

      unknown = Ai::Knowledge::Search.call(collection: @collection, query: "sqlite retrieval", mode: "magic")
      assert_equal "lexical", unknown.mode
      assert_equal "lexical", unknown.requested_mode
    end
  end

  test "blank queries return no evidence and never embed the query" do
    with_provider_configuration("openrouter") do
      add_item(title: "Retrieval notes", text: ("sqlite retrieval " * 40) + ("sqlite alone " * 40))
      Ai::Knowledge::Embedder.call(collection: @collection, model_id: MODEL_ID, client: FakeEmbeddingClient.new)
      client = FakeEmbeddingClient.new

      outcome = Ai::Knowledge::Search.call(collection: @collection, query: "   ", mode: "hybrid", client: client)

      assert_empty outcome.results
      assert_equal "hybrid", outcome.mode
      assert_empty client.calls
    end
  end
end

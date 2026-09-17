require "test_helper"

class Ai::Knowledge::RetrieverTest < ActiveSupport::TestCase
  test "returns explainable lexical matches from ready sources" do
    collection = create_project(name: "Retrieval project").knowledge_collections.create!(name: "Engineering notes")
    matching_item = collection.knowledge_items.create!(
      title: "SQLite retrieval notes",
      content_text: "SQLite stores local evidence for deterministic retrieval."
    )
    Ai::Knowledge::Ingestor.call(matching_item)

    other_item = collection.knowledge_items.create!(
      title: "Provider roadmap",
      content_text: "Provider embeddings and reranking remain deferred."
    )
    Ai::Knowledge::Ingestor.call(other_item)

    failed_item = collection.knowledge_items.create!(
      title: "Failed source",
      content_text: "SQLite retrieval should not be searchable while failed.",
      ingestion_status: :failed
    )
    failed_item.knowledge_chunks.create!(position: 0, content_text: failed_item.content_text, char_start: 0, char_end: failed_item.content_text.length)

    results = Ai::Knowledge::Retriever.search(collection: collection, query: "SQLite retrieval")

    assert_equal matching_item.id, results.first.chunk.knowledge_item_id
    assert_equal %w[sqlite retrieval], results.first.matched_terms
    assert_equal 0.7833, results.first.score
    refute results.any? { |result| result.chunk.knowledge_item_id == failed_item.id }
  end

  test "returns an empty result for blank queries and caps the result count" do
    collection = create_project(name: "Empty retrieval project").knowledge_collections.create!(name: "Notes")

    assert_empty Ai::Knowledge::Retriever.search(collection: collection, query: "  ")
    assert_operator Ai::Knowledge::Retriever::MAX_LIMIT, :<, 100
  end

  test "matches complete tokens instead of arbitrary substrings" do
    collection = create_project(name: "Token retrieval project").knowledge_collections.create!(name: "Notes")
    item = collection.knowledge_items.create!(title: "Partial word", content_text: "This sentence is partial.")
    Ai::Knowledge::Ingestor.call(item)

    assert_empty Ai::Knowledge::Retriever.search(collection: collection, query: "art")
  end

  test "semantic mode ranks chunks by cosine similarity" do
    collection, _item = semantic_fixture

    results = Ai::Knowledge::Retriever.search(
      collection: collection,
      query: "sqlite retrieval",
      mode: "semantic",
      query_vector: [ 1.0, 1.0, 0.0, 0.0, 0.0, 0.0 ],
      model_id: "test-embed"
    )

    assert_operator results.length, :>=, 2
    assert_equal "Both terms", results.first.chunk.knowledge_item.title
    assert_in_delta 1.0, results.first.score, 1e-3
    assert_in_delta 1.0, results.first.similarity, 1e-3
    assert_nil results.first.lexical_score
    assert_operator results.first.similarity, :>=, results.last.similarity
    assert_in_delta 0.7071, results.last.similarity, 1e-3
  end

  test "semantic mode requires a query vector and model id" do
    collection = create_project(name: "Missing vector project").knowledge_collections.create!(name: "Notes")

    assert_raises(ArgumentError) do
      Ai::Knowledge::Retriever.search(collection: collection, query: "sqlite", mode: "semantic", model_id: "test-embed")
    end
    assert_raises(ArgumentError) do
      Ai::Knowledge::Retriever.search(collection: collection, query: "sqlite", mode: "semantic", query_vector: [ 1.0 ])
    end
  end

  test "hybrid mode keeps both score components visible" do
    collection, _item = semantic_fixture

    results = Ai::Knowledge::Retriever.search(
      collection: collection,
      query: "sqlite retrieval",
      mode: "hybrid",
      query_vector: [ 1.0, 1.0, 0.0, 0.0, 0.0, 0.0 ],
      model_id: "test-embed"
    )

    top = results.first
    assert_equal "Both terms", top.chunk.knowledge_item.title
    assert_equal top.similarity.round(4), top.similarity
    assert_operator top.lexical_score, :>, 0
    assert_equal %w[sqlite retrieval], top.matched_terms
    assert_operator results.length, :>=, 2
  end

  test "hybrid mode falls back to lexical evidence when no vector is supplied" do
    collection = create_project(name: "Hybrid fallback project").knowledge_collections.create!(name: "Notes")
    item = collection.knowledge_items.create!(title: "Lexical only", content_text: "SQLite retrieval evidence lives here.")
    Ai::Knowledge::Ingestor.call(item)

    results = Ai::Knowledge::Retriever.search(collection: collection, query: "sqlite retrieval", mode: "hybrid")

    assert_equal 1, results.length
    assert_nil results.first.similarity
    assert_operator results.first.lexical_score, :>, 0
  end

  test "skips embeddings whose checksum no longer matches the chunk" do
    collection, item = semantic_fixture
    stale = collection.knowledge_embeddings.for_model("test-embed").first
    stale.update!(content_checksum: "stale-checksum")

    retriever = Ai::Knowledge::Retriever.new(
      collection: collection,
      query: "sqlite",
      limit: 8,
      mode: "semantic",
      query_vector: [ 1.0, 1.0, 0.0, 0.0, 0.0, 0.0 ],
      model_id: "test-embed"
    )
    results = retriever.search

    expected = item.knowledge_chunks.count { |chunk| FakeEmbeddingClient.new.vector_for(chunk.content_text).any?(&:positive?) }

    assert_equal 1, retriever.stale_count
    assert_equal expected - 1, results.length
  end

  private

  def semantic_fixture
    project = create_project(name: "Semantic retrieval project")
    collection = project.knowledge_collections.create!(name: "Notes")
    item = collection.knowledge_items.create!(
      title: "Both terms",
      content_text: ("sqlite without the other term " * 40) + ("sqlite retrieval " * 60)
    )
    Ai::Knowledge::Ingestor.call(item)

    item.knowledge_chunks.each do |chunk|
      KnowledgeEmbedding.create!(
        knowledge_chunk: chunk,
        provider: "openrouter",
        model_id: "test-embed",
        dimensions: 6,
        vector: Ai::Knowledge::VectorStore.default.encode(FakeEmbeddingClient.new.vector_for(chunk.content_text)),
        content_checksum: chunk.content_checksum
      )
    end

    [ collection, item ]
  end
end

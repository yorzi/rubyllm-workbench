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
end

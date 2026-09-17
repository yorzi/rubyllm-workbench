require "test_helper"

class KnowledgeEmbeddingTest < ActiveSupport::TestCase
  setup do
    @project = create_project(name: "Embedding record project")
    @collection = @project.knowledge_collections.create!(name: "Notes")
    @item = @collection.knowledge_items.create!(
      title: "Retrieval notes",
      content_text: "SQLite retrieval evidence keeps local search inspectable."
    )
    Ai::Knowledge::Ingestor.call(@item)
    @chunk = @item.knowledge_chunks.first
  end

  test "stores one vector per chunk and embedding model" do
    embedding = KnowledgeEmbedding.create!(
      knowledge_chunk: @chunk,
      provider: "openrouter",
      model_id: "test-embed",
      dimensions: 3,
      vector: Ai::Knowledge::VectorStore.default.encode([ 0.1, 0.2, 0.3 ]),
      content_checksum: @chunk.content_checksum
    )

    assert_equal "ready", embedding.status
    assert_equal 3, embedding.vector_values.length
    assert embedding.dimensions_match?
    assert_equal @collection.id, @collection.reload.knowledge_embeddings.first.knowledge_chunk.knowledge_item.knowledge_collection_id
  end

  test "rejects a second row for the same chunk and model" do
    KnowledgeEmbedding.create!(
      knowledge_chunk: @chunk,
      provider: "openrouter",
      model_id: "test-embed",
      dimensions: 3,
      vector: Ai::Knowledge::VectorStore.default.encode([ 0.1, 0.2, 0.3 ]),
      content_checksum: @chunk.content_checksum
    )

    duplicate = KnowledgeEmbedding.new(
      knowledge_chunk: @chunk,
      provider: "openrouter",
      model_id: "test-embed",
      dimensions: 3,
      vector: Ai::Knowledge::VectorStore.default.encode([ 0.9, 0.9, 0.9 ]),
      content_checksum: @chunk.content_checksum
    )

    assert_not duplicate.save
    assert_includes duplicate.errors.full_messages.to_sentence, "taken"
  end

  test "requires dimensions, provider and non-empty vectors" do
    embedding = KnowledgeEmbedding.new(knowledge_chunk: @chunk, model_id: "test-embed")

    assert_not embedding.save
    assert_includes embedding.errors.attribute_names, :dimensions
    assert_includes embedding.errors.attribute_names, :vector
  end

  test "destroying a chunk removes its embedding rows" do
    KnowledgeEmbedding.create!(
      knowledge_chunk: @chunk,
      provider: "openrouter",
      model_id: "test-embed",
      dimensions: 3,
      vector: Ai::Knowledge::VectorStore.default.encode([ 0.1, 0.2, 0.3 ]),
      content_checksum: @chunk.content_checksum
    )

    assert_difference -> { KnowledgeEmbedding.count }, -1 do
      @chunk.destroy!
    end
  end
end

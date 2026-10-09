require "test_helper"

class KnowledgeCollectionTest < ActiveSupport::TestCase
  test "belongs to a project and scopes its sources" do
    project = create_project(name: "Knowledge collection project")
    collection = project.knowledge_collections.create!(name: "Product notes")

    assert_equal project, collection.project
    assert_equal [], collection.knowledge_items.to_a
    assert_equal [ collection ], project.knowledge_collections.to_a
  end

  test "requires a bounded name" do
    project = create_project(name: "Invalid knowledge collection project")
    collection = project.knowledge_collections.new(name: "")

    assert_not collection.valid?
    assert_includes collection.errors[:name], "can't be blank"
  end

  test "embedding coverage follows the selected provider for a shared model identifier" do
    collection = create_project(name: "Provider coverage project").knowledge_collections.create!(
      name: "Notes", embedding_model_id: "shared-embed", embedding_provider: "openrouter"
    )
    %w[openai openrouter].each do |provider|
      item = collection.knowledge_items.create!(title: provider, content_text: "Embedding coverage for #{provider}.")
      Ai::Knowledge::Ingestor.call(item)
      chunk = item.knowledge_chunks.first
      chunk.knowledge_embeddings.create!(provider: provider, model_id: "shared-embed", dimensions: 2,
        vector: Ai::Knowledge::VectorStore.default.encode([ 1.0, 0.0 ]), content_checksum: chunk.content_checksum)
    end

    assert_equal 1, collection.embedded_chunk_count
    assert_equal 1, collection.embedded_chunk_count(model_id: "shared-embed", provider: "openai")
    assert_equal 0, collection.embedded_chunk_count(model_id: "shared-embed", provider: "cohere")
    assert collection.semantic_searchable?
    refute collection.semantic_searchable?(model_id: "shared-embed", provider: "cohere")
  end
end

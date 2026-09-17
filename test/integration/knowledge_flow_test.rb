require "test_helper"

class KnowledgeFlowTest < ActionDispatch::IntegrationTest
  EMBEDDING_MODEL_ID = "openai/text-embedding-3-small"

  test "creates a collection, ingests text, and searches inspectable evidence" do
    post projects_path, params: { project: { name: "Knowledge flow project", description: "Test" } }
    assert_response :redirect

    project = Project.find_by!(slug: "knowledge-flow-project")
    get project_knowledge_collections_path(project)
    assert_response :success
    assert_includes response.body, "New collection"

    post project_knowledge_collections_path(project), params: {
      knowledge_collection: { name: "Engineering notes", description: "Local source set" }
    }
    assert_response :redirect

    collection = project.knowledge_collections.last
    post project_knowledge_collection_items_path(project, collection), params: {
      knowledge_item: {
        title: "Architecture notes",
        source_reference: "architecture-001",
        content_text: "SQLite keeps local retrieval inspectable. This source is stored with offsets."
      }
    }
    assert_response :redirect
    assert collection.knowledge_items.last.ready?

    get project_knowledge_collection_path(project, collection), params: { q: "SQLite retrieval" }
    assert_response :success
    assert_includes response.body, "Search evidence"
    assert_includes response.body, "lexical-v1"
    assert_includes response.body, "Architecture notes"
    assert_includes response.body, "local retrieval inspectable"
    assert_includes response.body, "chars 0–"
  end

  test "embeds a collection and searches semantic evidence through the workspace" do
    with_provider_configuration("openrouter") do
      project = create_project(name: "Semantic knowledge project")
      collection = project.knowledge_collections.create!(name: "Engineering notes")
      collection.knowledge_items.create!(
        title: "Retrieval notes",
        content_text: ("sqlite retrieval " * 40) + ("sqlite alone " * 40)
      ).tap { |item| Ai::Knowledge::Ingestor.call(item) }

      get project_knowledge_collection_path(project, collection)
      assert_response :success
      assert_includes response.body, "Embeddings"
      assert_includes response.body, "Embed collection"

      client = FakeEmbeddingClient.new
      with_embedding_client(client) do
        post project_knowledge_collection_embeddings_path(project, collection),
          params: { embedding: { model_id: EMBEDDING_MODEL_ID } }
        assert_response :redirect

        get project_knowledge_collection_path(project, collection), params: { q: "sqlite retrieval", mode: "semantic" }
        assert_response :success
      end

      collection.reload
      assert_equal EMBEDDING_MODEL_ID, collection.embedding_model_id
      assert_equal "ready", collection.embedding_status
      assert_equal collection.chunk_count, collection.embedded_chunk_count

      assert_includes response.body, "semantic"
      assert_includes response.body, "cosine"
      assert_includes response.body, "sqlite_application_cosine"

      with_embedding_client(FakeEmbeddingClient.new) do
        delete project_knowledge_collection_embeddings_path(project, collection)
        assert_response :redirect
      end

      assert_equal 0, collection.reload.knowledge_embeddings.count
      assert_equal "none", collection.embedding_status
    end
  end

  test "semantic search degrades to lexical evidence in the UI when embeddings are missing" do
    with_provider_configuration("openrouter") do
      project = create_project(name: "Degraded knowledge project")
      collection = project.knowledge_collections.create!(name: "Notes")
      collection.knowledge_items.create!(title: "Retrieval notes", content_text: "SQLite retrieval evidence lives here.")
        .tap { |item| Ai::Knowledge::Ingestor.call(item) }

      get project_knowledge_collection_path(project, collection), params: { q: "sqlite retrieval", mode: "semantic" }

      assert_response :success
      assert_includes response.body, "Semantic retrieval was unavailable"
      assert_includes response.body, "No embedding model is selected"
    end
  end

  test "does not cross project collection boundaries" do
    project = create_project(name: "Knowledge owner project")
    other_project = create_project(name: "Other knowledge project")
    collection = other_project.knowledge_collections.create!(name: "Private notes")

    get project_knowledge_collection_path(project, collection)

    assert_response :not_found
  end
end

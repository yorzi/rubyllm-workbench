require "test_helper"

class KnowledgeFlowTest < ActionDispatch::IntegrationTest
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

  test "does not cross project collection boundaries" do
    project = create_project(name: "Knowledge owner project")
    other_project = create_project(name: "Other knowledge project")
    collection = other_project.knowledge_collections.create!(name: "Private notes")

    get project_knowledge_collection_path(project, collection)

    assert_response :not_found
  end
end

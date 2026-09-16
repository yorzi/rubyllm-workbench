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
end

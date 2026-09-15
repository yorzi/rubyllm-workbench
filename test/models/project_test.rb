require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  test "derives a URL-safe slug from the project name" do
    project = Project.create!(name: "Rails AI Lab")

    assert_equal "rails-ai-lab", project.slug
    assert_equal "rails-ai-lab", project.to_param
  end

  test "rejects duplicate slugs" do
    Project.create!(name: "First", slug: "shared")
    duplicate = Project.new(name: "Second", slug: "shared")

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
  end

  test "requires a name and a URL-safe slug" do
    project = Project.new(name: "", slug: "Not a slug")

    assert_not project.valid?
    assert_includes project.errors[:name], "can't be blank"
    assert project.errors[:slug].any?
  end
end

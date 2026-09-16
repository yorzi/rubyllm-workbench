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

  test "defaults new tool Runs to sequential execution and preserves settings" do
    project = Project.create!(name: "Tool settings project", settings_json: { "theme" => "light" })

    assert_equal "sequential", project.tool_execution_mode

    project.update_tool_execution_mode!("parallel")

    assert_equal "parallel", project.reload.tool_execution_mode
    assert_equal "light", project.settings_json.fetch("theme")
    assert_equal "parallel", project.settings_json.dig("tools", "execution_mode")
  end

  test "rejects an unknown tool execution mode" do
    project = Project.create!(name: "Invalid tool settings project")

    assert_raises(ArgumentError) { project.update_tool_execution_mode!("unbounded") }
    assert_equal "sequential", project.reload.tool_execution_mode
  end
end

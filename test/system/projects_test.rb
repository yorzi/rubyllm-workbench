require "application_system_test_case"

class ProjectsTest < ApplicationSystemTestCase
  test "creates a Project from the local workbench" do
    visit root_path
    wait_for_turbo

    assert_selector "h1", text: "Projects"
    fill_in "Name", with: "Browser smoke project"
    click_button "Create project"

    assert_text "Browser smoke project"
    assert_current_path project_path(Project.find_by!(name: "Browser smoke project"))
  end
end

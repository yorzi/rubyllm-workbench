require "application_system_test_case"
require_relative "../support/read_only_demo_helpers"

class ReadOnlyDemoSystemTest < ApplicationSystemTestCase
  include ReadOnlyDemoHelpers

  test "visitors inspect evidence and lexical sources on desktop and 390px" do
    project = Message.suppressing_turbo_broadcasts { Workbench::DemoTour.build! }
    with_demo_mode do
      visit project_path(project)
      wait_for_turbo
      assert_text "Synthetic read-only demo"
      assert_no_link "New chat"
      visit run_path(project.runs.find_by!(operation: "agent"))
      assert_link "Download reproduction JSON"
      assert_no_selector "form[method='post']"
      assert_no_selector "turbo-cable-stream-source"
      assert_no_horizontal_overflow

      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
      visit project_evaluation_dataset_path(project, project.evaluation_datasets.first)
      wait_for_turbo
      assert_equal 390, page.evaluate_script("window.innerWidth")
      assert_text "Synthetic comparison"
      assert_text "Actual JSON"
      assert_no_selector "form[method='post']"
      click_link "How this works"
      within "turbo-frame#learning-panel" do
        assert_text "How evaluations work"
      end
      assert_no_horizontal_overflow

      visit project_knowledge_collection_path(project, project.knowledge_collections.first)
      wait_for_turbo
      fill_in "Query", with: "database jobs"
      click_button "Search"
      assert_text "Solid Queue"
      assert_no_selector "select[name='mode']"
      assert_no_selector "form[method='post']"
      assert_no_horizontal_overflow
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  private

  def assert_no_horizontal_overflow
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"), "page overflows horizontally"
  end
end

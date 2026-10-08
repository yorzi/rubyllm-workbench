require "application_system_test_case"

class LearningTourTest < ApplicationSystemTestCase
  test "the synthetic tour explains durable Agents and evaluations on a narrow screen" do
    project = Workbench::DemoTour.build!
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)

    visit project_agent_definitions_path(project)
    wait_for_turbo
    assert_equal 390, page.evaluate_script("window.innerWidth")
    click_button "Navigation"
    within "nav[aria-label='Primary']" do
      assert_link "Evaluations"
    end
    click_button "Navigation"
    click_link "How this works"
    within "turbo-frame#learning-panel" do
      assert_text "How durable Agents work"
      assert_selector "figure[data-learning-flow='agent_execution']"
      assert_text "Lease lost"
    end
    assert_no_horizontal_overflow
    assert_operator page.evaluate_script("document.querySelector('[data-learning-topic]').getBoundingClientRect().top"), :<, 50
    save_screenshot Rails.root.join("tmp/screenshots/agent-learning-mobile.png")

    visit project_evaluation_datasets_path(project)
    wait_for_turbo
    click_link "How this works"
    within "turbo-frame#learning-panel" do
      assert_text "How evaluations work"
      assert_selector "figure[data-learning-flow='evaluation_workflow']"
      assert_text "expected answers"
    end
    assert_no_horizontal_overflow

    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
    visit run_path(project.runs.find_by!(operation: "agent"))
    assert_no_selector "button", text: "Navigation"
    assert_text "Synthetic demo record"
    assert_link "Download reproduction JSON"
    assert_no_horizontal_overflow
    save_screenshot Rails.root.join("tmp/screenshots/demo-run-desktop.png")
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  private

  def assert_no_horizontal_overflow
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth"), "page overflows horizontally"
  end
end

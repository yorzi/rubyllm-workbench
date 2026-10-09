require "application_system_test_case"

class GroundedAnswerSystemTest < ApplicationSystemTestCase
  test "a visitor evaluates a saved case without another model request" do
    corpus = Workbench::KnowledgeCaseStudy.import!
    example = corpus.cases.find { |entry| entry.fetch("key") == "missing-billing" }
    model = RubyLLM.models.chat_models.all.find { |entry| entry.provider == "openrouter" && entry.supports?(:structured_output) }
    with_provider_configuration("openrouter") do
      run = Ai::Knowledge::GroundedAnswer.enqueue(collection: corpus.collection,
        question: example.fetch("question"), model_reference: "openrouter|#{model.id}")
      GroundedAnswerJob.perform_now(run.id)
      visit run_path(run)
      assert_text "Evaluate this saved answer"
      click_button "Run native assertions · no API request"
      assert_selector "#native-evaluation-heading"
      evaluation = corpus.project.runs.where(operation: "native_evaluation").sole
      NativeEvaluationJob.perform_now(evaluation.id)
      visit run_path(evaluation)
      assert_text "Native result: passed"
      assert_text "answer cost included: false"
      assert_empty evaluation.attempts
      assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
      visit run_path(evaluation)
      assert_text "Native result: passed"
      assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
      click_link "Original answer Run ##{run.id}"
      assert_selector "#grounded-answer-heading"
      assert_text "Evaluate this saved answer"
      assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "a visitor creates a local refusal and inspects frozen citations on desktop and mobile" do
    corpus = Workbench::KnowledgeCaseStudy.import!
    model = RubyLLM.models.chat_models.all.find { |entry| entry.provider == "openrouter" && entry.supports?(:structured_output) }
    with_provider_configuration("openrouter") do
      visit project_knowledge_collection_path(corpus.project, corpus.collection)
      wait_for_turbo
      assert_text "Answer with sources"
      fill_in "Question about these sources", with: "quasarxyz"
      select "openrouter / #{model.id}", from: "Answer model"
      begin
        # Preserve real enqueue behavior while checking an in-flight redirect.
        # Hosted runners can exceed Capybara's default two-second wait.
        enqueue = Ai::Knowledge::GroundedAnswer.method(:enqueue)
        Ai::Knowledge::GroundedAnswer.define_singleton_method(:enqueue) do |**arguments|
          sleep 2.25
          enqueue.call(**arguments)
        end
        click_button "Create source answer"
        assert_selector "#grounded-answer-heading", wait: 10
      ensure
        Ai::Knowledge::GroundedAnswer.define_singleton_method(:enqueue, enqueue) if enqueue
        # Let any in-flight request finish before the test transaction closes.
        page.has_selector?("#grounded-answer-heading", wait: 10)
      end
      assert_text "Answer queued or running."
      run = corpus.project.runs.sole
      GroundedAnswerJob.perform_now(run.id)
      visit run_path(run)
      assert_text "Insufficient evidence"
      assert_text "No model request was made."
      assert_empty run.attempts

      cited = Ai::Knowledge::GroundedAnswer.enqueue(collection: corpus.collection,
        question: "validates title", model_reference: "openrouter|#{model.id}")
      evidence = cited.input_snapshot.dig("grounded_answer", "evidence").first
      output = { "status" => "answered", "reason" => "", "claims" => [ {
        "text" => "<script>synthetic escaped claim</script>",
        "citations" => [ { "evidence_id" => "e1", "quote" => "validates :title" } ]
      } ] }
      cited.artifacts.create!(kind: "json", name: "grounded_answer", content_json: output,
        metadata_json: { "report_type" => "grounded_answer", "citation_validation" => "valid" })
      cited.attempts.sole.finish!(status: :succeeded, finished_at: Time.current)
      cited.succeed!(answer_status: "answered")
      visit run_path(cited)
      assert_text "<script>synthetic escaped claim</script>"
      assert_no_selector "section[aria-labelledby='grounded-answer-heading'] script"
      click_link "e1", match: :first
      assert_selector "#grounded-evidence-e1", text: evidence.fetch("source_reference")
      assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")

      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 390, height: 844, deviceScaleFactor: 1, mobile: true)
      visit run_path(cited)
      assert_equal 390, page.evaluate_script("window.innerWidth")
      assert_text "Citation validity does not verify"
      assert_text "Chunk SHA-256:"
      assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
      click_link "How source answers work"
      within "turbo-frame#learning-panel" do
        assert_text "How source answers work"
        assert_text "Freeze the sources"
        assert_text "Quote validation"
      end
      assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
      visit project_knowledge_collection_path(corpus.project, corpus.collection)
      assert_button "Create source answer"
      assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end

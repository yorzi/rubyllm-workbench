require "test_helper"
require_relative "../support/read_only_demo_helpers"

class GroundedAnswerFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ReadOnlyDemoHelpers

  setup do
    @corpus = Workbench::KnowledgeCaseStudy.import!
    @project = @corpus.project
    @collection = @corpus.collection
    @model = RubyLLM.models.chat_models.all.find { |model| model.provider == "openrouter" && model.supports?(:structured_output) }
  end

  test "the controller, real RubyLLM HTTP boundary, ledger and source inspector work together" do
    output = {
      "status" => "answered", "reason" => "", "claims" => [ {
        "text" => "The title is required.", "citations" => [ { "evidence_id" => "e1", "quote" => "validates :title" } ]
      } ]
    }
    received = nil
    request = WebMock.stub_request(:post, "https://openrouter.ai/api/v1/chat/completions").with do |http|
      received = JSON.parse(http.body)
      true
    end.to_return(status: 200, headers: { "content-type" => "application/json" }, body: JSON.generate(
      id: "grounded-http-1", model: @model.id,
      choices: [ { index: 0, message: { role: "assistant", content: JSON.generate(output) }, finish_reason: "stop" } ],
      usage: { prompt_tokens: 90, completion_tokens: 40, total_tokens: 130 }
    ))

    with_provider_configuration("openrouter") do
      perform_enqueued_jobs do
        post project_knowledge_collection_answers_path(@project, @collection), params: {
          knowledge_answer: { question: "validates title presence", model_reference: "openrouter|#{@model.id}" }
        }
      end
    end
    assert_response :see_other
    run = @project.runs.sole
    assert run.succeeded?, run.error_summary
    assert_equal "valid", run.result_summary.fetch("citation_validation")
    assert_equal "grounded_answer", received.dig("response_format", "json_schema", "name")
    assert_equal 2_048, received["max_tokens"] || received["max_completion_tokens"]
    assert_nil received["tools"]
    assert_equal @model.id, received["model"]
    assert_includes received["messages"].first["content"], "untrusted"
    assert_equal 90, run.attempts.sole.input_tokens
    assert run.chat.ruby_llm_usages.exists?
    assert_requested request, times: 1

    follow_redirect!
    assert_response :success
    assert_select "#grounded-answer-heading", text: "Answer with sources"
    assert_select "#grounded-evidence-e1", minimum: 1
    assert_includes response.body, "The title is required."
    assert_includes response.body, "Citation validity does not verify"

    get reproduction_run_path(run)
    exported = JSON.parse(response.body)
    assert_equal run.input_snapshot.dig("grounded_answer", "corpus_checksum"), exported.dig("run", "input_snapshot", "grounded_answer", "corpus_checksum")
    assert_equal run.input_snapshot.dig("grounded_answer", "schema_json"), exported.dig("run", "input_snapshot", "grounded_answer", "schema_json")
    assert_includes response.body, "case-study://mini-notes-rails"
  end

  test "empty evidence, cancellation and invalid model selection are understandable from the UI" do
    with_provider_configuration("openrouter") do
      get project_knowledge_collection_path(@project, @collection)
      assert_select "form[action=?]", project_knowledge_collection_answers_path(@project, @collection)
      perform_enqueued_jobs do
        post project_knowledge_collection_answers_path(@project, @collection), params: {
          knowledge_answer: { question: "quasarxyz", model_reference: "openrouter|#{@model.id}" }
        }
      end
      run = @project.runs.sole
      follow_redirect!
      assert_includes response.body, "Insufficient evidence"
      assert_includes response.body, "No model request was made."
      assert_empty run.attempts

      post project_knowledge_collection_answers_path(@project, @collection), params: {
        knowledge_answer: { question: "title", model_reference: "openrouter|#{@model.id}" }
      }
      queued = @project.runs.recent.first
      get run_path(queued)
      assert_select "form[action=?]", cancel_run_path(queued)
      post cancel_run_path(queued)
      assert queued.reload.cancelled?

      assert_no_difference "Run.count" do
        post project_knowledge_collection_answers_path(@project, @collection), params: {
          knowledge_answer: { question: "title", model_reference: "openrouter|missing" }
        }
      end
      follow_redirect!
      assert_includes response.body, "Choose a configured structured-output model."
    end
  end

  test "a collection from another project is not accepted" do
    other = create_project(name: "Other source owner")
    post project_knowledge_collection_answers_path(other, @collection), params: {
      knowledge_answer: { question: "title", model_reference: "openrouter|#{@model.id}" }
    }
    assert_response :not_found
  end

  test "the RubyLLM before_request boundary prevents a request after cancellation" do
    with_provider_configuration("openrouter") do
      run = Ai::Knowledge::GroundedAnswer.enqueue(collection: @collection,
        question: "title", model_reference: "openrouter|#{@model.id}")
      chat = run.chat
      chat.before_request { |*| Run.find(run.id).cancel! }
      Ai::Knowledge::GroundedAnswerExecutor.new(run.id, chat:).call
      assert run.reload.cancelled?
      assert run.attempts.sole.cancelled?
      assert_empty run.artifacts
      assert_not_requested :post, "https://openrouter.ai/api/v1/chat/completions"
    end
  end

  test "read-only demo cannot submit an answer" do
    with_demo_mode do
      assert_no_difference "Run.count" do
        post project_knowledge_collection_answers_path(@project, @collection), params: "malformed upload",
          headers: { "CONTENT_TYPE" => "multipart/form-data; boundary=broken" }
      end
      assert_response :forbidden
    end
  end
end

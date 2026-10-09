require "test_helper"
require_relative "../support/read_only_demo_helpers"

class NativeEvaluationFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include ReadOnlyDemoHelpers

  setup do
    corpus = Workbench::KnowledgeCaseStudy.import!
    @project, @collection = corpus.project, corpus.collection
    @case = corpus.cases.find { |entry| entry.fetch("key") == "missing-billing" }
    @model = RubyLLM.models.chat_models.all.find { |model| model.provider == "openrouter" && model.supports?(:structured_output) }
    with_provider_configuration("openrouter") do
      @answer = Ai::Knowledge::GroundedAnswer.enqueue(collection: @collection, question: @case.fetch("question"), model_reference: "openrouter|#{@model.id}")
      GroundedAnswerJob.perform_now(@answer.id)
    end
    assert @answer.reload.succeeded?
  end

  test "a saved answer exposes native assertions and independently completed report" do
    with_provider_configuration("openrouter") do
      get run_path(@answer)
      assert_select "#native-evaluation-form-heading", text: "Evaluate this saved answer"
      assert_select "form[action=?]", native_evaluations_run_path(@answer), minimum: 2
      perform_enqueued_jobs do
        post native_evaluations_run_path(@answer), params: { native_evaluation: { case_key: @case.fetch("key"), evaluator_kind: "assertions" } }
      end
    end
    assert_response :see_other
    evaluation = @project.runs.where(operation: "native_evaluation").sole
    assert evaluation.succeeded?, evaluation.error_summary
    assert_empty evaluation.attempts
    assert_equal "passed", evaluation.result_summary["native_status"]
    follow_redirect!
    assert_response :success
    assert_select "#native-evaluation-heading", text: "Native saved-answer evaluation"
    assert_includes response.body, "answer cost included: false"
    assert_includes response.body, "Native result: passed"
    assert_select "a[href=?]", run_path(@answer), text: "Original answer Run ##{@answer.id}"
    get reproduction_run_path(evaluation)
    exported = JSON.parse(response.body)
    assert_equal @answer.id, exported.dig("run", "input_snapshot", "native_evaluation", "answer_run_id")
    assert_empty exported["owned_provider_usages"]
  end

  test "a reviewer failure is a completed native evaluation, with its own model usage" do
    request = WebMock.stub_request(:post, "https://openrouter.ai/api/v1/chat/completions").to_return(
      status: 200, headers: { "content-type" => "application/json" }, body: JSON.generate(
        id: "controller-native-review", model: @model.id,
        choices: [ { index: 0, message: { role: "assistant", content: JSON.generate(
          grounding: { verdict: "fail", reason: "Synthetic reviewer disagreement." },
          source_boundary: { verdict: "unknown", reason: "Cannot inspect hidden actions." }
        ) }, finish_reason: "stop" } ], usage: { prompt_tokens: 37, completion_tokens: 16, cost: 0.002 }
      )
    )
    with_provider_configuration("openrouter") do
      perform_enqueued_jobs do
        post native_evaluations_run_path(@answer), params: { native_evaluation: {
          case_key: @case.fetch("key"), evaluator_kind: "reviewer", model_reference: "openrouter|#{@model.id}" }
        }
      end
    end
    evaluation = @project.runs.where(operation: "native_evaluation").sole
    assert evaluation.succeeded?, evaluation.error_summary
    assert_equal "failed", evaluation.result_summary["native_status"]
    assert_equal 37, evaluation.attempts.sole.input_tokens
    assert_empty @answer.attempts
    get reproduction_run_path(evaluation)
    exported = JSON.parse(response.body)
    assert_equal "chat", exported["owned_provider_usages"].sole["operation"]
    assert_includes exported["accounting_note"], "do not sum both"
    assert_requested request, times: 1
  end

  test "mismatched cases and unsupported Judge models preserve the original Run" do
    [ { case_key: "title-validation", evaluator_kind: "assertions" },
      { case_key: @case.fetch("key"), evaluator_kind: "judge", model_reference: "openrouter|#{@model.id}" } ].each do |attributes|
      assert_no_difference "Run.count" do
        post native_evaluations_run_path(@answer), params: { native_evaluation: attributes }
      end
      assert_redirected_to run_path(@answer)
      assert @answer.reload.succeeded?
    end
  end

  test "native queued cancellation prevents all evaluator requests" do
    with_provider_configuration("openrouter") do
      post native_evaluations_run_path(@answer), params: { native_evaluation: {
        case_key: @case.fetch("key"), evaluator_kind: "reviewer", model_reference: "openrouter|#{@model.id}" }
      }
    end
    evaluation = @project.runs.where(operation: "native_evaluation").sole
    post cancel_run_path(evaluation)
    assert_redirected_to run_path(evaluation)
    NativeEvaluationJob.perform_now(evaluation.id)
    assert evaluation.reload.cancelled?
    assert evaluation.attempts.sole.cancelled?
    assert_empty evaluation.artifacts
    assert_not_requested :post, "https://openrouter.ai/api/v1/chat/completions"
  end

  test "read-only public demo hides evaluators and rejects malformed evaluation submissions" do
    with_demo_mode do
      get run_path(@answer)
      assert_select "#native-evaluation-form-heading", count: 0
      assert_no_difference "Run.count" do
        post native_evaluations_run_path(@answer), params: "malformed upload",
          headers: { "CONTENT_TYPE" => "multipart/form-data; boundary=broken" }
      end
      assert_response :forbidden
    end
  end
end

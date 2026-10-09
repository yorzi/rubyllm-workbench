require "test_helper"

class RequestLoggingPrivacyTest < ActiveSupport::TestCase
  test "search text is filtered from request parameters and the logged URL" do
    request = request_for("/projects/demo-tour/knowledge/1", params: {
      q: "synthetic-private-search", mode: "hybrid", rerank: "true",
      quantity: "2", request_id: "visible-request-id"
    })

    assert_equal "[FILTERED]", request.filtered_parameters.fetch("q")
    assert_not_includes request.filtered_path, "synthetic-private-search"
    assert_includes request.filtered_path, "q=[FILTERED]"
    assert_includes request.filtered_path, "mode=hybrid"
    assert_equal "2", request.filtered_parameters.fetch("quantity")
    assert_equal "visible-request-id", request.filtered_parameters.fetch("request_id")
  end

  test "nested questions reviews and approval notes are filtered without hiding routing choices" do
    request = request_for("/projects/demo-tour/knowledge/1/answers", method: "POST", params: {
      knowledge_answer: { question: "synthetic-private-question", model_reference: "openrouter/example:free", mode: "lexical" },
      evaluation_case_review: { rationale: "synthetic-private-review", verdict: "pass" },
      approval: { note: "synthetic-private-note", decision: "approve" },
      knowledge_collection: { description: "synthetic-private-description" },
      message: { content: "synthetic-private-message" },
      agent_run: { prompt: "synthetic-private-prompt" }
    })

    filtered = request.filtered_parameters
    assert_equal "[FILTERED]", filtered.dig("knowledge_answer", "question")
    assert_equal "[FILTERED]", filtered.dig("evaluation_case_review", "rationale")
    assert_equal "[FILTERED]", filtered.dig("approval", "note")
    assert_equal "[FILTERED]", filtered.dig("knowledge_collection", "description")
    assert_equal "[FILTERED]", filtered.dig("message", "content")
    assert_equal "[FILTERED]", filtered.dig("agent_run", "prompt")
    assert_not_includes filtered.to_json, "synthetic-private-"
    assert_equal "openrouter/example:free", filtered.dig("knowledge_answer", "model_reference")
    assert_equal "lexical", filtered.dig("knowledge_answer", "mode")
    assert_equal "pass", filtered.dig("evaluation_case_review", "verdict")
    assert_equal "approve", filtered.dig("approval", "decision")
  end

  test "serialized dataset and schema inputs and issue draft prose are filtered as whole values" do
    request = request_for("/projects/demo-tour/evaluations", method: "POST", params: {
      evaluation_dataset: { cases_json: '[{"input":"synthetic-private-case"}]' },
      experiment: { schema_json: '{"description":"synthetic-private-schema"}' },
      upstream_candidate: {
        category: "unconfirmed", expected_behavior: "synthetic-private-expectation",
        observed_behavior: "synthetic-private-observation", reproduction_steps: "synthetic-private-reproduction"
      }
    })

    filtered = request.filtered_parameters
    assert_equal "[FILTERED]", filtered.dig("evaluation_dataset", "cases_json")
    assert_equal "[FILTERED]", filtered.dig("experiment", "schema_json")
    assert_equal "[FILTERED]", filtered.dig("upstream_candidate", "expected_behavior")
    assert_equal "[FILTERED]", filtered.dig("upstream_candidate", "observed_behavior")
    assert_equal "[FILTERED]", filtered.dig("upstream_candidate", "reproduction_steps")
    assert_not_includes filtered.to_json, "synthetic-private-"
    assert_equal "unconfirmed", filtered.dig("upstream_candidate", "category")
  end

  private

  def request_for(path, params:, method: "GET")
    environment = if method == "GET"
      Rack::MockRequest.env_for("#{path}?#{params.to_query}")
    else
      Rack::MockRequest.env_for(path, method:, input: params.to_query,
        "CONTENT_TYPE" => "application/x-www-form-urlencoded")
    end
    ActionDispatch::Request.new(Rails.application.env_config.merge(environment))
  end
end

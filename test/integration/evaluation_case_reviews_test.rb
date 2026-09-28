require "test_helper"

class EvaluationCaseReviewsTest < ActionDispatch::IntegrationTest
  setup do
    @project = create_project(name: "Human evaluation review project")
    @dataset = @project.evaluation_datasets.create!(name: "Review cases")
    @revision = @dataset.create_revision!([
      {
        "key" => "review-me",
        "input" => { "prompt" => "sample" },
        "expected_output" => { "answer" => "expected" },
        "rubric" => [
          { "key" => "accuracy", "description" => "Factual accuracy" },
          { "key" => "completeness", "description" => "Requested detail" }
        ]
      }
    ])
    @execution = @project.evaluation_executions.create!(
      evaluation_dataset_revision: @revision,
      provider: "openrouter",
      model_id: "synthetic-model",
      status: :completed,
      case_count: 1,
      requested_by: "test",
      input_snapshot_json: {}
    )
    @case_result = create_case_result(status: :completed, actual_output_json: { "answer" => "different" }, passed: false)
  end

  test "appends human reviews without changing exact-match results or provider metrics" do
    route = review_path
    first_attributes = review_attributes(
      verdict: "needs_work",
      reviewer_label: "  reviewer one  ",
      rationale: "Missed the requested condition.",
      rubric_ratings: { "accuracy" => "partially_meets", "completeness" => "does_not_meet" }
    )

    assert_difference "EvaluationCaseReview.count", 1 do
      post route, params: { evaluation_case_review: first_attributes }
    end

    assert_response :see_other
    first_review = @case_result.evaluation_case_reviews.sole
    assert_equal "reviewer one", first_review.reviewer_label
    assert_equal "needs_work", first_review.verdict
    assert_equal({ "accuracy" => "partially_meets", "completeness" => "does_not_meet" }, first_review.rubric_ratings)
    assert_equal false, @case_result.reload.passed
    metrics_after_first = Ai::EvaluationMetrics.call(@execution)

    assert_difference "EvaluationCaseReview.count", 1 do
      post route, params: {
        evaluation_case_review: review_attributes(
          verdict: "acceptable",
          reviewer_label: "reviewer two",
          rubric_ratings: { "accuracy" => "meets", "completeness" => "not_applicable" }
        )
      }
    end

    assert_response :see_other
    assert_equal [ "needs_work", "acceptable" ], @case_result.evaluation_case_reviews.reload.map(&:verdict)
    assert_equal [
      { "accuracy" => "partially_meets", "completeness" => "does_not_meet" },
      { "accuracy" => "meets", "completeness" => "not_applicable" }
    ], @case_result.evaluation_case_reviews.map(&:rubric_ratings)
    assert_equal "Missed the requested condition.", first_review.reload.rationale
    assert_equal false, @case_result.reload.passed
    assert_equal metrics_after_first, Ai::EvaluationMetrics.call(@execution)

    summaries = @case_result.rubric_rating_summary.index_by { |summary| summary.fetch(:criterion).fetch("key") }
    assert_equal 2, summaries.fetch("accuracy").fetch(:denominator)
    assert_equal({ "meets" => 1, "partially_meets" => 1, "does_not_meet" => 0, "not_applicable" => 0 }, summaries.fetch("accuracy").fetch(:counts))
    assert_equal({ "meets" => 0, "partially_meets" => 0, "does_not_meet" => 1, "not_applicable" => 1 }, summaries.fetch("completeness").fetch(:counts))

    get project_evaluation_dataset_path(@project, @dataset)
    assert_response :success
    assert_includes response.body, "Human review"
    assert_includes response.body, "reviewer one"
    assert_includes response.body, "reviewer two"
    assert_includes response.body, "mismatch"
    assert_includes response.body, "Criterion ratings"
    assert_includes response.body, "Factual accuracy"
    assert_includes response.body, "Meets: 1"
    assert_includes response.body, "Does not meet: 1"
    assert_includes response.body, "not combined into a score"
  end

  test "rejects missing, unexpected and unsupported criterion ratings" do
    invalid_rating_sets = [
      { "accuracy" => "meets" },
      { "accuracy" => "meets", "completeness" => "meets", "extra" => "meets" },
      { "accuracy" => "excellent", "completeness" => "meets" }
    ]

    invalid_rating_sets.each do |ratings|
      assert_no_difference "EvaluationCaseReview.count" do
        post review_path, params: {
          evaluation_case_review: review_attributes(
            verdict: "acceptable",
            reviewer_label: "reviewer",
            rubric_ratings: ratings
          )
        }
      end
      assert_response :see_other
      assert_match "rubric ratings", flash[:alert].downcase
    end
  end

  test "rejects reviews for incomplete cases and cases outside the execution scope" do
    incomplete = create_case_result(case_key: "pending", case_position: 1, status: :queued, actual_output_json: nil, passed: nil)
    path = review_path(case_result: incomplete)

    assert_no_difference "EvaluationCaseReview.count" do
      post path, params: { evaluation_case_review: review_attributes(verdict: "acceptable", reviewer_label: "reviewer") }
    end
    assert_response :see_other
    assert_match "completed structured response", flash[:alert]

    other_project = create_project(name: "Other review project")
    other_dataset = other_project.evaluation_datasets.create!(name: "Other cases")
    other_revision = other_dataset.create_revision!([
      { "key" => "other", "input" => {}, "expected_output" => {} }
    ])
    other_execution = other_project.evaluation_executions.create!(
      evaluation_dataset_revision: other_revision,
      provider: "openrouter",
      model_id: "synthetic-model",
      status: :completed,
      case_count: 1,
      requested_by: "test",
      input_snapshot_json: {}
    )
    other_case = other_execution.evaluation_case_results.create!(
      evaluation_dataset_revision: other_revision,
      case_key: "other",
      case_position: 0,
      input_json: {},
      expected_output_json: {},
      actual_output_json: {},
      status: :completed,
      passed: true
    )

    assert_no_difference "EvaluationCaseReview.count" do
      post review_path(case_result: other_case), params: {
        evaluation_case_review: review_attributes(verdict: "acceptable", reviewer_label: "reviewer")
      }
    end
    assert_response :not_found
  end

  test "review records cannot be edited or deleted, but are removed with their project" do
    review = @case_result.evaluation_case_reviews.create!(
      verdict: "inconclusive",
      reviewer_label: "reviewer",
      rationale: "Need a clearer rubric.",
      rubric_ratings_json: valid_rubric_ratings
    )

    assert_not review.update(rationale: "Changed after the fact.")
    assert_includes review.errors[:base], "Evaluation case reviews are append-only."
    assert_not review.update(rubric_ratings_json: { "accuracy" => "does_not_meet", "completeness" => "does_not_meet" })
    assert_includes review.errors[:base], "Evaluation case reviews are append-only."
    assert_not review.destroy
    assert EvaluationCaseReview.exists?(review.id)
    assert_equal valid_rubric_ratings, review.reload.rubric_ratings

    assert_difference "Project.count", -1 do
      @project.destroy!
    end
    assert_not EvaluationCaseReview.exists?(review.id)
  end

  private

  def create_case_result(case_key: "review-me", case_position: 0, status:, actual_output_json:, passed:)
    @execution.evaluation_case_results.create!(
      evaluation_dataset_revision: @revision,
      case_key:,
      case_position:,
      input_json: { "prompt" => "sample" },
      expected_output_json: { "answer" => "expected" },
      actual_output_json:,
      status:,
      passed:
    )
  end

  def review_path(case_result: @case_result)
    project_evaluation_dataset_execution_case_result_reviews_path(
      @project,
      @dataset,
      case_result.evaluation_execution,
      case_result
    )
  end

  def review_attributes(verdict:, reviewer_label:, rationale: nil, rubric_ratings: valid_rubric_ratings)
    { verdict:, reviewer_label:, rationale:, rubric_ratings: }
  end

  def valid_rubric_ratings
    { "accuracy" => "meets", "completeness" => "meets" }
  end
end

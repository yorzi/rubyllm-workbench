class EvaluationCaseReviewsController < ApplicationController
  before_action :set_project_and_dataset
  before_action :set_execution_and_case_result

  def create
    review = @case_result.evaluation_case_reviews.new(review_params)
    if review.save
      redirect_to project_evaluation_dataset_path(@project, @dataset, anchor: helpers.dom_id(@case_result)),
        notice: "Human review added. Earlier reviews remain in the record.", status: :see_other
    else
      redirect_to project_evaluation_dataset_path(@project, @dataset, anchor: helpers.dom_id(@case_result)),
        alert: review.errors.full_messages.to_sentence, status: :see_other
    end
  end

  private

  def set_project_and_dataset
    @project = Project.find_by!(slug: params[:project_id])
    @dataset = @project.evaluation_datasets.find(params[:evaluation_dataset_id])
  end

  def set_execution_and_case_result
    @execution = @dataset.evaluation_executions.find(params[:execution_id])
    @case_result = @execution.evaluation_case_results.find(params[:case_result_id])
  end

  def review_params
    attributes = params.expect(evaluation_case_review: [
      :verdict,
      :reviewer_label,
      :rationale,
      { rubric_ratings: {} }
    ])
    {
      verdict: attributes[:verdict],
      reviewer_label: attributes[:reviewer_label],
      rationale: attributes[:rationale],
      rubric_ratings_json: attributes[:rubric_ratings]&.to_h || {}
    }
  end
end

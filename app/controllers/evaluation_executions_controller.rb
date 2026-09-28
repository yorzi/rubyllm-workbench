class EvaluationExecutionsController < ApplicationController
  before_action :set_project
  before_action :set_dataset

  def create
    experiment = @project.experiments.find(execution_params.fetch(:experiment_id))
    model_references = Array(execution_params[:model_references]).map(&:to_s).reject(&:blank?)

    if model_references.size >= EvaluationComparison::MIN_MODELS
      comparison = Ai::EvaluationExecutor.enqueue_comparison(
        dataset: @dataset,
        experiment:,
        model_references:,
        judge_model_reference: execution_params[:judge_model_reference]
      )
      if comparison.rejected_count.positive?
        alert = "Comparison ##{comparison.comparison.id} created; the queue accepted #{comparison.queued_count} case job(s) and rejected #{comparison.rejected_count}. Rejected cases remain retryable."
        redirect_to project_evaluation_dataset_path(@project, @dataset), alert:, status: :see_other
      else
        redirect_to project_evaluation_dataset_path(@project, @dataset),
          notice: "Comparison ##{comparison.comparison.id} queued across #{comparison.comparison.evaluation_executions.size} models.", status: :see_other
      end
      return
    end

    model_reference = execution_params[:model_reference].presence || model_references.first
    execution = Ai::EvaluationExecutor.enqueue(
      dataset: @dataset,
      experiment:,
      model_reference:,
      execution_mode: execution_params[:execution_mode].presence || "individual",
      judge_model_reference: execution_params[:judge_model_reference]
    )
    redirect_to project_evaluation_dataset_path(@project, @dataset),
      notice: "Evaluation execution ##{execution.id} queued.", status: :see_other
  rescue ArgumentError, ActiveRecord::RecordNotFound => error
    redirect_to project_evaluation_dataset_path(@project, @dataset), alert: error.message
  end

  def resume
    execution = @dataset.evaluation_executions.find(params[:id])
    result = execution.resume_unstarted!
    if result.rejected_count.positive?
      alert = "Queue accepted #{result.queued_count} case re-enqueue(s) and rejected #{result.rejected_count}; rejected cases remain eligible to retry."
      redirect_to project_evaluation_dataset_path(@project, @dataset), alert:, status: :see_other
    else
      notice = result.queued_count.positive? ? "Queued #{result.queued_count} evaluation case(s) that had not started." : "No unstarted evaluation cases were eligible to resume."
      redirect_to project_evaluation_dataset_path(@project, @dataset), notice:, status: :see_other
    end
  rescue ActiveRecord::RecordNotFound => error
    redirect_to project_evaluation_dataset_path(@project, @dataset), alert: error.message
  end

  def resume_judgments
    execution = @dataset.evaluation_executions.find(params[:id])
    result = execution.resume_unstarted_judgments!
    if result.rejected_count.positive?
      alert = "Queue accepted #{result.queued_count} judge request(s) and rejected #{result.rejected_count}; rejected judgments remain retryable."
      redirect_to project_evaluation_dataset_path(@project, @dataset), alert:, status: :see_other
    else
      notice = result.queued_count.positive? ? "Queued #{result.queued_count} unstarted rubric judge(s)." : "No rejected, unstarted rubric judgments were eligible to resume."
      redirect_to project_evaluation_dataset_path(@project, @dataset), notice:, status: :see_other
    end
  rescue ActiveRecord::RecordNotFound => error
    redirect_to project_evaluation_dataset_path(@project, @dataset), alert: error.message
  end

  def refresh
    execution = @dataset.evaluation_executions.find(params[:id])
    if execution.provider_batch? && execution.running? && execution.provider_batch_id.present?
      begin
        Ai::EvaluationJobEnqueuer.call(EvaluationBatchRefreshJob, execution.id)
        notice = "Provider batch refresh queued. This page will show the latest saved state after it completes."
      rescue StandardError => error
        Rails.logger.warn("Evaluation batch refresh was not queued for execution ##{execution.id}: #{error.class}")
        alert = "Provider batch refresh could not be queued. The saved execution state is unchanged."
      end
    else
      alert = "This provider batch cannot be refreshed yet or a refresh is already in progress."
    end
    redirect_to project_evaluation_dataset_path(@project, @dataset), notice:, alert:, status: :see_other
  rescue ActiveRecord::RecordNotFound => error
    redirect_to project_evaluation_dataset_path(@project, @dataset), alert: error.message
  end

  def close_unknown
    execution = @dataset.evaluation_executions.find(params[:id])
    if execution.close_unresolved_provider_batch!
      notice = "Unresolved evaluation closed locally. A provider request may still be running; no request was replayed."
      redirect_to project_evaluation_dataset_path(@project, @dataset), notice:, status: :see_other
    else
      redirect_to project_evaluation_dataset_path(@project, @dataset), alert: "This evaluation is not eligible for manual closure."
    end
  rescue ActiveRecord::RecordNotFound => error
    redirect_to project_evaluation_dataset_path(@project, @dataset), alert: error.message
  end

  private

  def set_project
    @project = Project.find_by!(slug: params[:project_id])
  end

  def set_dataset
    @dataset = @project.evaluation_datasets.find(params[:evaluation_dataset_id])
  end

  def execution_params
    params.expect(execution: [ :experiment_id, :model_reference, :judge_model_reference, :execution_mode, { model_references: [] } ])
  end
end

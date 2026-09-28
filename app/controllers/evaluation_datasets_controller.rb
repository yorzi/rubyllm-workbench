class EvaluationDatasetsController < ApplicationController
  before_action :set_project
  before_action :set_dataset, only: %i[show edit update]

  def index
    @datasets = @project.evaluation_datasets.order(updated_at: :desc, id: :desc)
  end

  def new
    @dataset = @project.evaluation_datasets.new
    @cases_text = default_cases_json
  end

  def create
    @dataset = @project.evaluation_datasets.new(dataset_params.except(:cases_json))
    @cases_text = dataset_params[:cases_json].to_s
    @project.transaction do
      @dataset.save!
      @dataset.create_revision!(@cases_text)
    end
    redirect_to project_evaluation_dataset_path(@project, @dataset), notice: "Evaluation dataset created.", status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    @revision = error.record if error.record.is_a?(EvaluationDatasetRevision)
    @dataset.errors.add(:base, error.record.errors.full_messages.to_sentence) if @revision
    render :new, status: :unprocessable_entity
  end

  def show
    @revision = @dataset.current_revision_record
    @revision&.case_attachments&.includes(file_attachment: :blob)&.load
    @revisions = @dataset.evaluation_dataset_revisions.order(revision: :desc)
    @experiments = @project.experiments.runnable.order(:name)
    structured_models = Ai::ModelCatalog.new.entries(capability: "structured_output", configured: "true").select(&:interactive?)
    @models = structured_models.first(100)
    @judge_models = structured_models.first(100)
    @batch_models = structured_models.select { |entry| entry.supports?("batch") }.first(100)
    @comparisons = @dataset.evaluation_comparisons.includes(
      :evaluation_dataset_revision,
      evaluation_executions: { evaluation_case_results: {
        run: [ :attempts, :lifecycle_events ],
        evaluation_case_judgment: { run: [ :attempts, :lifecycle_events ] },
        evaluation_case_reviews: [],
        evaluation_dataset_revision: { case_attachments: { file_attachment: :blob } }
      } }
    ).recent.limit(10)
    @executions = @dataset.evaluation_executions.includes(
      :evaluation_dataset_revision,
      evaluation_case_results: {
        run: [ :attempts, :lifecycle_events ],
        evaluation_case_judgment: { run: [ :attempts, :lifecycle_events ] },
        evaluation_case_reviews: [],
        evaluation_dataset_revision: { case_attachments: { file_attachment: :blob } }
      }
    ).where(evaluation_comparison_id: nil).recent.limit(20)
    metric_executions = @comparisons.flat_map(&:evaluation_executions) + @executions.to_a
    @evaluation_metrics = metric_executions.index_by(&:id).transform_values do |execution|
      Ai::EvaluationMetrics.call(execution)
    end
  end

  def edit
    @revision = @dataset.current_revision_record
    @cases_text = JSON.pretty_generate(@revision&.cases_json || [])
  end

  def update
    @cases_text = dataset_params[:cases_json].to_s
    @project.transaction do
      @dataset.update!(dataset_params.except(:cases_json))
      new_cases = JSON.parse(@cases_text)
      current_cases = @dataset.current_revision_record&.cases_json
      @dataset.create_revision!(new_cases) unless current_cases == new_cases
    end
    redirect_to project_evaluation_dataset_path(@project, @dataset), notice: "Evaluation dataset saved as a new immutable revision.", status: :see_other
  rescue JSON::ParserError => error
    @revision = @dataset.current_revision_record
    @dataset.errors.add(:base, "Cases must be valid JSON: #{error.message}")
    render :edit, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => error
    @revision = error.record if error.record.is_a?(EvaluationDatasetRevision)
    @dataset.errors.add(:base, error.record.errors.full_messages.to_sentence) if @revision
    render :edit, status: :unprocessable_entity
  end

  private

  def set_project
    @project = Project.find_by!(slug: params[:project_id])
  end

  def set_dataset
    @dataset = @project.evaluation_datasets.find(params[:id])
  end

  def dataset_params
    params.expect(evaluation_dataset: [ :name, :description, :cases_json ])
  end

  def default_cases_json
    JSON.pretty_generate([
      { "key" => "case-1", "tags" => [ "smoke" ], "input" => { "text" => "Replace with an evaluation input." }, "expected_output" => { "summary" => "Expected summary", "confidence" => 1 } }
    ])
  end
end

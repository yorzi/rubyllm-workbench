class ExperimentsController < ApplicationController
  before_action :set_project
  before_action :set_experiment, only: %i[show edit update]

  def index
    @experiments = @project.experiments.order(updated_at: :desc, id: :desc)
  end

  def new
    @experiment = @project.experiments.new
    @schema_text = Ai::SchemaDefinition.default_json
  end

  def create
    @experiment = @project.experiments.new
    if assign_definition_attributes
      @experiment.save!
      redirect_to project_experiment_path(@project, @experiment), status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid
    @schema_text ||= JSON.pretty_generate(@experiment.schema_json || {})
    render :new, status: :unprocessable_entity
  end

  def show
    @models = structured_models
    @default_model_ids = default_model_ids
    @executions = @experiment.experiment_executions.recent.includes(
      runs: [ :attempts, :artifacts, :chat ]
    )
  end

  def edit
    @schema_text = JSON.pretty_generate(@experiment.schema_json)
  end

  def update
    if assign_definition_attributes && @experiment.save
      redirect_to project_experiment_path(@project, @experiment), status: :see_other
    else
      @schema_text ||= JSON.pretty_generate(@experiment.schema_json || {})
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_project
    @project = Project.find_by!(slug: params[:project_id])
  end

  def set_experiment
    @experiment = @project.experiments.find(params[:id])
  end

  def experiment_params
    params.expect(experiment: [ :name, :description, :system_prompt, :input_prompt, :schema_json ])
  end

  def assign_definition_attributes
    attributes = experiment_params.to_h
    raw_schema = attributes.delete("schema_json")
    raw_schema = attributes.delete(:schema_json) if raw_schema.nil?
    @schema_text = raw_schema.to_s
    definition = Ai::SchemaDefinition.parse(raw_schema)
    @experiment.assign_attributes(attributes.merge("schema_json" => definition.document))
    true
  rescue Ai::SchemaDefinition::DefinitionError => error
    @experiment.assign_attributes(attributes || {})
    @experiment.errors.add(:schema_json, error.message)
    false
  end

  def structured_models
    model_catalog.entries(capability: "structured_output", configured: "true").select(&:interactive?).first(100)
  end

  def default_model_ids
    free_models = @models.select do |entry|
      entry.provider == "openrouter" && (entry.id == "openrouter/free" || entry.id.to_s.end_with?(":free"))
    end
    preferred = free_models.size >= 2 ? free_models.first(2) : @models.first(2)
    preferred.map { |entry| "#{entry.provider}|#{entry.id}" }
  end
end

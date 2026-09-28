class AgentDefinitionsController < ApplicationController
  before_action :set_project
  before_action :sync_tool_registry
  before_action :set_agent_definition, only: %i[show edit update destroy]

  def index
    @agent_definitions = @project.agent_definitions.order(updated_at: :desc, id: :desc)
  end

  def show
    @local_tools_model_eligible = Ai::AgentModelEligibility.new.eligible?(
      provider: @agent_definition.provider,
      model_id: @agent_definition.model_id,
      tool_keys: @agent_definition.tool_keys
    )
  end

  def new
    @agent_definition = @project.agent_definitions.new
    prepare_form
  end

  def create
    @agent_definition = @project.agent_definitions.new
    assign_definition_attributes

    if @agent_definition.save
      redirect_to project_agent_definition_path(@project, @agent_definition),
        notice: "Agent definition created.", status: :see_other
    else
      prepare_form
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    prepare_form
  end

  def update
    assign_definition_attributes

    if @agent_definition.save
      redirect_to project_agent_definition_path(@project, @agent_definition),
        notice: "Agent definition saved as revision #{@agent_definition.revision}.", status: :see_other
    else
      prepare_form
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @agent_definition.destroy!
    redirect_to project_agent_definitions_path(@project),
      notice: "Agent definition deleted.", status: :see_other
  end

  private

  def set_project
    @project = Project.find_by!(slug: params[:project_id])
  end

  def sync_tool_registry
    Ai::ToolRegistry.sync_project!(@project)
  end

  def set_agent_definition
    @agent_definition = @project.agent_definitions.find(params[:id])
  end

  def prepare_form
    @available_tools = @project.tool_definitions.enabled.order(:name, :key)
  end

  def agent_definition_params
    params.expect(agent_definition: [
      :name,
      :provider,
      :model_id,
      :instructions,
      { tool_keys: [], provider_tools: [], options: [ :temperature, :max_output_tokens ] }
    ])
  end

  def assign_definition_attributes
    attributes = agent_definition_params.to_h.deep_stringify_keys
    attributes["tool_keys"] = attributes.delete("tool_keys") || [] if attributes.key?("tool_keys") || @agent_definition.new_record?
    attributes["provider_tools"] = attributes.delete("provider_tools") || [] if attributes.key?("provider_tools") || @agent_definition.new_record?
    attributes["options"] = attributes.delete("options") || {} if attributes.key?("options") || @agent_definition.new_record?
    @agent_definition.assign_attributes(attributes)
  end
end

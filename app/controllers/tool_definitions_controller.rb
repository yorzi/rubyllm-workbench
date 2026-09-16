class ToolDefinitionsController < ApplicationController
  before_action :set_project
  before_action :sync_registry

  def index
    @tool_definitions = @project.tool_definitions.order(:name, :key)
  end

  def update_settings
    @project.update_tool_execution_mode!(tool_settings_params.fetch(:execution_mode))
    redirect_to project_tool_definitions_path(@project),
      notice: "Tool execution mode is #{@project.tool_execution_mode}.",
      status: :see_other
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    message = error.respond_to?(:record) ? error.record.errors.full_messages.to_sentence : error.message
    redirect_to project_tool_definitions_path(@project), alert: message
  end

  def update
    @tool_definition = @project.tool_definitions.find(params[:id])
    @tool_definition.update!(enabled: tool_definition_params.fetch(:enabled) == "1")
    redirect_to project_tool_definitions_path(@project), notice: "#{@tool_definition.name} is #{@tool_definition.enabled? ? 'enabled' : 'disabled'}.", status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    redirect_to project_tool_definitions_path(@project), alert: error.record.errors.full_messages.to_sentence
  end

  private

  def set_project
    @project = Project.find_by!(slug: params[:project_id])
  end

  def sync_registry
    Ai::ToolRegistry.sync_project!(@project)
  end

  def tool_definition_params
    params.expect(tool_definition: [ :enabled ])
  end

  def tool_settings_params
    params.expect(tool_settings: [ :execution_mode ])
  end
end

class AgentRunsController < ApplicationController
  before_action :set_project
  before_action :set_agent_definition

  def create
    run = Ai::AgentRunExecutor.enqueue(agent_definition: @agent_definition, prompt: run_params.fetch(:prompt))
    redirect_to run_path(run), notice: "Agent Run ##{run.id} queued.", status: :see_other
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to project_agent_definition_path(@project, @agent_definition), alert: error.message
  end

  private

  def set_project
    @project = Project.find_by!(slug: params[:project_id])
  end

  def set_agent_definition
    @agent_definition = @project.agent_definitions.find(params[:agent_definition_id])
  end

  def run_params
    params.expect(agent_run: [ :prompt ])
  end
end

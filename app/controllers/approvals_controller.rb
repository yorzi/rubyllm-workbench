class ApprovalsController < ApplicationController
  before_action :set_project
  before_action :set_chat

  def update
    @invocation = @chat.tool_invocations.includes(:approval, :tool_definition, :run).find(params[:id])
    Ai::ApprovalService.decide!(
      invocation: @invocation,
      decision: approval_params.fetch(:decision),
      note: approval_params[:note]
    )
    redirect_to project_chat_path(@project, @chat), notice: "Tool decision recorded; Run ##{@invocation.run_id} queued to continue.", status: :see_other
  rescue ActiveRecord::RecordNotFound, ArgumentError => error
    redirect_to project_chat_path(@project, @chat), alert: error.message
  end

  private

  def set_project
    @project = Project.find_by!(slug: params[:project_id])
  end

  def set_chat
    @chat = @project.chats.find(params[:chat_id])
  end

  def approval_params
    params.expect(approval: [ :decision, :note ])
  end
end

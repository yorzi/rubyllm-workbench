class ProjectsController < ApplicationController
  def index
    @projects = Project.order(:name)
    @project = Project.new
  end

  def create
    @project = Project.new(project_params)

    if @project.save
      redirect_to project_path(@project), status: :see_other
    else
      @projects = Project.order(:name)
      render :index, status: :unprocessable_entity
    end
  end

  def show
    @project = Project.find_by!(slug: params[:id])
    @chats = @project.chats.includes(:messages).order(updated_at: :desc).limit(8)
    @runs = @project.runs.includes(:chat, :attempts).recent.limit(8)
  end

  private

  def project_params
    params.expect(project: [ :name, :slug, :description ])
  end
end

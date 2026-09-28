class VideoRunsController < ApplicationController
  before_action :set_project
  before_action :set_chat

  def new
    load_video_models
  end

  def create
    run = Ai::VideoRunExecutor.enqueue(
      chat: @chat,
      prompt: video_run_params.fetch(:prompt),
      model_reference: video_run_params.fetch(:model_reference)
    )
    redirect_to run_path(run), notice: "Video Run ##{run.id} queued.", status: :see_other
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    load_video_models
    @error = error.message
    render :new, status: :unprocessable_entity
  end

  private

  def set_project
    @project = Project.find_by!(slug: params[:project_id])
  end

  def set_chat
    @chat = @project.chats.find(params[:chat_id])
  end

  def load_video_models
    @media_models = Ai::MediaCatalog.entries(operation: "video")
  end

  def video_run_params
    params.expect(video_run: [ :prompt, :model_reference ])
  end
end

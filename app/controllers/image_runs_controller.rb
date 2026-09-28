class ImageRunsController < ApplicationController
  before_action :set_project
  before_action :set_chat

  def new
    load_image_models
  end

  def create
    run = Ai::ImageRunExecutor.enqueue(
      chat: @chat,
      prompt: image_run_params.fetch(:prompt),
      model_reference: image_run_params.fetch(:model_reference)
    )
    redirect_to run_path(run), notice: "Image Run ##{run.id} queued.", status: :see_other
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    load_image_models
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

  def load_image_models
    @media_models = Ai::MediaCatalog.entries(operation: "image")
  end

  def image_run_params
    params.expect(image_run: [ :prompt, :model_reference ])
  end
end

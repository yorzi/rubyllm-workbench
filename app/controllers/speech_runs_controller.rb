class SpeechRunsController < ApplicationController
  before_action :set_project
  before_action :set_chat
  before_action :set_message

  def new
    load_speech_models
    render :new
  end

  def create
    run = Ai::SpeechRunExecutor.enqueue(
      message: @message,
      model_reference: speech_run_params.fetch(:model_reference),
      voice: speech_run_params[:voice]
    )
    redirect_to run_path(run), notice: "Speech Run ##{run.id} queued.", status: :see_other
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    load_speech_models
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

  def set_message
    @message = @chat.messages.find(params[:message_id])
    raise ActiveRecord::RecordNotFound unless @message.role == "assistant" && @message.content.present?
  end

  def load_speech_models
    @speech_models = Ai::SpeechCatalog.entries
  end

  def speech_run_params
    params.expect(speech_run: [ :model_reference, :voice ])
  end
end

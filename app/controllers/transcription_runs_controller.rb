class TranscriptionRunsController < ApplicationController
  before_action :set_project
  before_action :set_chat

  def new
    load_transcription_models
  end

  def create
    run = Ai::TranscriptionRunExecutor.enqueue(
      chat: @chat,
      audio_upload: transcription_run_params[:audio_file],
      model_reference: transcription_run_params.fetch(:model_reference)
    )
    redirect_to run_path(run), notice: "Transcription Run ##{run.id} queued.", status: :see_other
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    load_transcription_models
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

  def load_transcription_models
    @media_models = Ai::MediaCatalog.entries(operation: "transcription")
  end

  def transcription_run_params
    params.expect(transcription_run: [ :audio_file, :model_reference ])
  end
end

class ChatsController < ApplicationController
  before_action :set_project

  def new
    @chat = @project.chats.new
    @selected_model = requested_model
    all_models = model_catalog.entries
    @models = all_models.first(180)
    selected_entry = all_models.find do |entry|
      entry.id == @selected_model&.id && entry.provider == @selected_model&.provider
    end
    @models.unshift(selected_entry) if selected_entry && !@models.include?(selected_entry)
  end

  def create
    @chat = @project.chats.new(title: chat_params[:title].presence)
    provider, model_id = chat_params.fetch(:model).to_s.split("|", 2)
    raise ArgumentError, "Choose a model." if provider.blank? || model_id.blank?

    model = model_catalog.find!(model_id, provider: provider)
    @chat.model = model

    if @chat.save
      redirect_to project_chat_path(@project, @chat), status: :see_other
    else
      @selected_model = model
      @models = model_catalog.entries.first(180)
      render :new, status: :unprocessable_entity
    end
  rescue RubyLLM::ModelNotFoundError, ArgumentError => error
    @chat ||= @project.chats.new
    @chat.errors.add(:model_id, "is not available in the RubyLLM registry (#{error.message})")
    @selected_model = requested_model
    @models = model_catalog.entries.first(180)
    render :new, status: :unprocessable_entity
  end

  def show
    @chat = @project.chats.includes(:messages, :runs).find(params[:id])
    @messages = @chat.messages
    @runs = @chat.runs.includes(:attempts).recent.limit(10)
    @latest_run = @runs.first
    prepare_tool_inspection
    @model_entry = model_catalog.entries.find do |entry|
      entry.id == @chat.model_id && entry.provider == @chat.provider
    end
    @provider_configured = @model_entry&.configured
    @image_models_available = Ai::MediaCatalog.entries(operation: "image").any?
    @transcription_models_available = Ai::MediaCatalog.entries(operation: "transcription").any?
    @video_models_available = Ai::MediaCatalog.entries(operation: "video").any?
    @speech_models_available = Ai::SpeechCatalog.entries.any?
  end

  def destroy
    @chat = @project.chats.find(params[:id])
    @chat.destroy!
    redirect_to project_path(@project), status: :see_other
  end

  private

  def set_project
    @project = Project.find_by!(slug: params[:project_id])
  end

  def chat_params
    params.expect(chat: [ :title, :model ])
  end

  def requested_model
    return if params[:model_id].blank?

    model_catalog.find!(params[:model_id], provider: params[:provider])
  rescue RubyLLM::ModelNotFoundError, ArgumentError
    nil
  end

  def prepare_tool_inspection
    @tool_invocations = []
    @pending_tool_invocations = []
    return unless @latest_run

    Ai::ToolInvocationRecorder.new(run: @latest_run, chat: @chat).sync!
    @tool_invocations = @latest_run.tool_invocations.includes(:approval, :tool_definition).recent.to_a
    @pending_tool_invocations = @tool_invocations.select(&:approval_pending?)
  rescue ActiveRecord::RecordNotFound, KeyError
    @tool_invocations = []
    @pending_tool_invocations = []
  end
end

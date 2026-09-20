class MessagesController < ApplicationController
  before_action :set_project
  before_action :set_chat

  def create
    prompt = message_params.fetch(:content).to_s.strip
    if prompt.blank?
      redirect_to project_chat_path(@project, @chat), alert: "Enter a message before running the model."
      return
    end

    model_entry = model_catalog.entries.find do |entry|
      entry.id == @chat.model_id && entry.provider == @chat.provider
    end
    unless model_entry&.configured
      missing = model_entry&.missing_configuration&.join(", ").presence || "provider configuration"
      redirect_to project_chat_path(@project, @chat), alert: "This model is not runnable yet. Configure #{missing} first."
      return
    end

    web_search = ActiveModel::Type::Boolean.new.cast(message_params[:web_search])
    provider_tools = web_search ? [ "web_search" ] : []
    @run = Ai::RunExecutor.enqueue(chat: @chat, project: @project, prompt: prompt, provider_tools:)
    redirect_to project_chat_path(@project, @chat), notice: "Run ##{@run.id} queued.", status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    redirect_to project_chat_path(@project, @chat), alert: error.record.errors.full_messages.to_sentence
  end

  private

  def set_project
    @project = Project.find_by!(slug: params[:project_id])
  end

  def set_chat
    @chat = @project.chats.find(params[:chat_id])
  end

  def message_params
    params.expect(message: [ :content, :web_search ])
  end
end

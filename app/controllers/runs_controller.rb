class RunsController < ApplicationController
  def index
    @status_options = Run.statuses.keys
    @provider_options = Chat.joins(:model).where.not(ruby_llm_models: { provider: [ nil, "" ] }).distinct.order("ruby_llm_models.provider ASC").pluck("ruby_llm_models.provider")
    @query = params[:q].to_s.strip
    @status = params[:status].to_s if Run.statuses.key?(params[:status].to_s)
    @provider = params[:provider].to_s if @provider_options.include?(params[:provider].to_s)

    scope = Run.includes(:project, :chat, :attempts).recent
    scope = scope.where(status: @status) if @status
    scope = scope.joins(chat: :model).where(ruby_llm_models: { provider: @provider }) if @provider

    if @query.present?
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      scope = scope.joins(:project, chat: :model).where(
        "projects.name LIKE :pattern OR chats.title LIKE :pattern OR ruby_llm_models.provider LIKE :pattern OR ruby_llm_models.model_id LIKE :pattern OR CAST(runs.id AS TEXT) LIKE :pattern",
        pattern: pattern
      )
    end

    @total_count = scope.unscope(:order).distinct.count
    @runs = scope.limit(100)
  end

  def show
    @run = Run.includes(:project, :chat, :attempts).find(params[:id])
    @messages = @run.chat.messages
    @latest_assistant_message = @messages.reverse.find { |message| message.role.to_s == "assistant" }
  end
end

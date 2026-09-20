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
    @run = Run.includes(:project, :chat, :attempts, :artifacts, :experiment, :experiment_execution, :lifecycle_events).find(params[:id])
    Ai::ToolInvocationRecorder.new(run: @run, chat: @run.chat).sync!
    @tool_invocations = @run.tool_invocations.includes(:approval, :tool_definition).recent.to_a
    @lifecycle_events = @run.lifecycle_events.chronological.to_a
    @messages = @run.chat.messages
    source_message_id = @run.result_summary["source_message_id"]
    @source_assistant_message = if source_message_id.present?
      @run.chat.messages.find_by(id: source_message_id, role: "assistant")
    end
    @structured_artifact = @run.artifacts.reverse.find { |artifact| artifact.kind == "json" }
    @citation_artifacts = @run.artifacts.reverse.select { |artifact| artifact.kind == "citation_set" }
  end
end

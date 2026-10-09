class RunsController < ApplicationController
  def index
    @status_options = Run.statuses.keys
    @provider_options = Chat.where(project: visible_projects).joins(:model).where.not(ruby_llm_models: { provider: [ nil, "" ] }).distinct.order("ruby_llm_models.provider ASC").pluck("ruby_llm_models.provider")
    @query = params[:q].to_s.strip
    @status = params[:status].to_s if Run.statuses.key?(params[:status].to_s)
    @provider = params[:provider].to_s if @provider_options.include?(params[:provider].to_s)

    scope = visible_runs.includes(:project, :chat, :attempts).recent
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
    Ai::ToolInvocationRecorder.new(run: @run, chat: @run.chat).sync! unless demo_mode?
    @tool_invocations = @run.tool_invocations.includes(:approval, :tool_definition).recent.to_a
    @lifecycle_events = @run.lifecycle_events.chronological.to_a
    @messages = @run.chat.messages
    source_message_id = @run.result_summary["source_message_id"]
    @source_assistant_message = if source_message_id.present?
      @run.chat.messages.find_by(id: source_message_id, role: "assistant")
    end
    @structured_artifact = @run.artifacts.reverse.find { |artifact| artifact.kind == "json" }
    @citation_artifacts = @run.artifacts.reverse.select { |artifact| artifact.kind == "citation_set" }
    @agent_research_report = @run.artifacts.find do |artifact|
      artifact.kind == "report" && artifact.metadata_json["report_type"] == Ai::AgentResearchReportRecorder::REPORT_TYPE
    end
    if @agent_research_report
      citation_ids = Array(@agent_research_report.content_json["citation_artifact_ids"]).map(&:to_i)
      @agent_research_citations = @citation_artifacts.select { |artifact| citation_ids.include?(artifact.id) }
    else
      @agent_research_citations = []
    end
    @image_artifacts = @run.artifacts.select { |artifact| artifact.kind == "image" && artifact.media_file.attached? }
    @video_artifacts = @run.artifacts.select { |artifact| artifact.kind == "video" && artifact.media_file.attached? }
    @transcript_artifacts = @run.artifacts.reverse.select { |artifact| artifact.kind == "transcript" }
    @upstream_candidates = @run.artifacts.select do |artifact|
      artifact.kind == "report" && artifact.metadata_json["report_type"] == "upstream_candidate"
    end.sort_by(&:created_at).reverse
  end

  def reproduction
    run = Run.includes(:attempts, :artifacts, :lifecycle_events, tool_invocations: :approval).find(params[:id])
    bundle = Ai::RunReproductionExporter.call(run)
    response.headers["Cache-Control"] = "private, no-store"
    send_data JSON.pretty_generate(bundle),
      filename: "run-#{run.id}-reproduction.json",
      type: "application/json; charset=utf-8",
      disposition: "attachment"
  end

  def events
    run = Run.find(params[:id])
    bundle = Ai::RunReproductionExporter.new(run).events
    response.headers["Cache-Control"] = "private, no-store"
    send_data JSON.pretty_generate(bundle),
      filename: "run-#{run.id}-events.json",
      type: "application/json; charset=utf-8",
      disposition: "attachment"
  end

  def upstream_candidates
    run = Run.find(params[:id])
    Ai::UpstreamCandidateRecorder.call(run:, attributes: upstream_candidate_params)
    redirect_to run_path(run, anchor: "upstream-candidates"), notice: "Upstream candidate saved as an append-only report.", status: :see_other
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to run_path(params[:id], anchor: "upstream-candidates"), alert: error.message
  end

  def upstream_issue_draft
    run = Run.find(params[:id])
    artifact = run.artifacts.find_by!(id: params[:artifact_id], kind: "report")
    raise ActiveRecord::RecordNotFound unless artifact.metadata_json["report_type"] == "upstream_candidate"

    response.headers["Cache-Control"] = "private, no-store"
    send_data Ai::UpstreamIssueDraft.call(artifact),
      filename: "run-#{run.id}-upstream-candidate-#{artifact.id}.md",
      type: "text/markdown; charset=utf-8",
      disposition: "attachment"
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def cancel
    run = Run.find(params[:id])
    raise ActiveRecord::RecordNotFound unless run.operation.in?(%w[agent image speech transcription video grounded_answer])

    run.cancel!
    redirect_to run_path(run), notice: "Run ##{run.id} cancelled.", status: :see_other
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  private

  def upstream_candidate_params
    params.expect(upstream_candidate: [ :category, :title, :expected_behavior, :observed_behavior, :reproduction_steps, :regression_test_reference ])
  end
end

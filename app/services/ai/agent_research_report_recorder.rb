module Ai
  class AgentResearchReportRecorder
    REPORT_TYPE = "agent_research_report"

    def self.call(run:, message:)
      new(run:, message:).call
    end

    def initialize(run:, message:)
      @run = run
      @message = message
    end

    def call
      @run.with_lock { record_report }
    end

    private

    def record_report
      raise ArgumentError, "Research reports can only be attached to Agent Runs." unless @run.operation == "agent"

      message = @run.chat.messages.find_by(id: @message&.id, role: "assistant")
      raise ArgumentError, "The Agent Run has no saved assistant message for its final report." unless message

      existing = @run.artifacts.where(kind: "report").find do |artifact|
        metadata = artifact.metadata_json.to_h
        metadata["report_type"] == REPORT_TYPE && metadata["source_message_id"].to_s == message.id.to_s
      end
      return existing if existing

      definition = @run.input_snapshot.fetch("agent_definition").deep_stringify_keys
      attempt = @run.attempts.order(:sequence, :id).last
      citation_artifacts = @run.artifacts.where(kind: "citation_set").order(:created_at, :id).to_a
      citation_artifact_ids = citation_artifacts.map(&:id)
      provider = attempt&.provider || @run.chat.provider
      model_id = attempt&.model_id || @run.chat.model_id
      agent = definition.slice("id", "name", "revision")
      content = {
        "schema_version" => 1,
        "report_type" => REPORT_TYPE,
        "answer" => message.content.to_s,
        "source_message_id" => message.id,
        "citation_artifact_ids" => citation_artifact_ids,
        "agent" => agent,
        "provider" => provider.to_s,
        "model_id" => model_id.to_s
      }

      @run.artifacts.create!(
        attempt:,
        kind: "report",
        name: "Research report · #{agent.fetch('name')}",
        content_text: message.content.to_s,
        content_json: content,
        metadata_json: {
          "report_type" => REPORT_TYPE,
          "source_message_id" => message.id,
          "citation_artifact_ids" => citation_artifact_ids,
          "agent_definition_id" => agent["id"],
          "agent_revision" => agent["revision"],
          "provider" => provider.to_s,
          "model_id" => model_id.to_s
        }
      )
    end
  end
end

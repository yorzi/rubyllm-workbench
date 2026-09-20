module Ai
  module Tools
    class SaveRunNote < RubyLLM::Tool
      description "Save a bounded note as a report Artifact attached to the current Run."
      parameter :note, type: :string, description: "The note to save, up to 2,000 characters."
      requires_approval

      def self.tool_name
        "save_run_note"
      end

      def self.parallel_safe?
        false
      end

      def initialize(project:, run: nil)
        @project = project
        @run = run
      end

      def execute(note:, tool_call: nil)
        raise ArgumentError, "This tool requires a Run context." unless @run
        raise ArgumentError, "This tool requires a persisted tool call." if tool_call&.id.blank?

        normalized_note = note.to_s.strip
        raise ArgumentError, "The note cannot be blank." if normalized_note.blank?
        raise ArgumentError, "The note is too long." if normalized_note.length > 2_000

        artifact = nil
        @run.with_lock do
          if (token = Ai::ExecutionContext.agent_execution_token).present?
            @run.reload
            @run.assert_agent_execution_lease!(
              token:,
              generation: Ai::ExecutionContext.agent_execution_generation
            )
          end

          artifact = @run.artifacts.create_or_find_by!(source_tool_call_id: tool_call.id) do |record|
            record.assign_attributes(
              attempt: @run.attempts.order(:sequence, :id).last,
              kind: "report",
              name: "Tool note",
              content_text: normalized_note,
              metadata_json: {
                "tool_key" => name,
                "tool_call_id" => tool_call.id,
                "project_id" => @project.id,
                "run_id" => @run.id
              }
            )
          end
        end
        unless artifact.content_text == normalized_note
          raise ArgumentError, "This tool call id is already associated with a different note."
        end

        {
          "status" => "saved",
          "artifact_id" => artifact.id,
          "note" => normalized_note
        }
      end
    end
  end
end

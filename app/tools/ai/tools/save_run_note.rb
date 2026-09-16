module Ai
  module Tools
    class SaveRunNote < RubyLLM::Tool
      description "Save a bounded note as a report Artifact attached to the current Run."
      parameter :note, type: :string, description: "The note to save, up to 2,000 characters."
      requires_approval

      def self.tool_name
        "save_run_note"
      end

      def initialize(project:, run: nil)
        @project = project
        @run = run
      end

      def execute(note:)
        raise ArgumentError, "This tool requires a Run context." unless @run

        normalized_note = note.to_s.strip
        raise ArgumentError, "The note cannot be blank." if normalized_note.blank?
        raise ArgumentError, "The note is too long." if normalized_note.length > 2_000

        artifact = @run.artifacts.create!(
          attempt: @run.attempts.order(:sequence, :id).last,
          kind: "report",
          name: "Tool note",
          content_text: normalized_note,
          metadata_json: {
            "tool_key" => name,
            "project_id" => @project.id,
            "run_id" => @run.id
          }
        )

        {
          "status" => "saved",
          "artifact_id" => artifact.id,
          "note" => normalized_note
        }
      end
    end
  end
end

module Ai
  class ToolRegistry
    Definition = Data.define(:key, :tool_class) do
      def name
        tool_class.tool_name
      end

      def description
        tool_class.description.to_s
      end

      def approval_policy
        tool_class.requires_approval? ? "always" : "never"
      end

      def approval_required?
        approval_policy == "always"
      end

      def parallel_safe?
        tool_class.respond_to?(:parallel_safe?) && tool_class.parallel_safe?
      end

      def schema(project: nil, run: nil)
        tool_class.new(project:, run:).parameters_schema || {}
      end

      def instantiate(project:, run: nil)
        tool_class.new(project:, run:)
      end
    end

    DEFINITIONS = [
      Definition.new(key: "project_snapshot", tool_class: Ai::Tools::ProjectSnapshot),
      Definition.new(key: "save_run_note", tool_class: Ai::Tools::SaveRunNote)
    ].freeze

    class << self
      def entries
        DEFINITIONS
      end

      def fetch(key)
        entries.find { |entry| entry.key == key.to_s }
      end

      def fetch!(key)
        fetch(key) || raise(KeyError, "Unknown registered tool: #{key}")
      end

      def sync_project!(project)
        project.transaction do
          entries.each do |entry|
            record = project.tool_definitions.find_or_initialize_by(key: entry.key)
            record.assign_attributes(
              name: entry.name,
              description: entry.description,
              class_identifier: entry.key,
              schema_json: entry.schema(project: project),
              approval_policy: entry.approval_policy
            )
            record.enabled = true if record.new_record?
            record.save!
          end
        end
        project.tool_definitions
      end

      def snapshot(project)
        sync_project!(project)
        project.tool_definitions.enabled.order(:key).map do |definition|
          {
            "key" => definition.key,
            "name" => definition.name,
            "description" => definition.description,
            "schema" => definition.schema_json,
            "approval_policy" => definition.approval_policy,
            "parallel_safe" => definition.parallel_safe?
          }
        end
      end
    end
  end
end

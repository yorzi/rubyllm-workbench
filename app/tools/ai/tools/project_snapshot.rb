module Ai
  module Tools
    class ProjectSnapshot < RubyLLM::Tool
      description "Read the current project's non-secret name, description, and local record counts."

      def self.tool_name
        "project_snapshot"
      end

      def self.parallel_safe?
        true
      end

      def initialize(project:, run: nil)
        @project = project
        @run = run
      end

      def execute
        {
          "project" => {
            "name" => @project.name,
            "slug" => @project.slug,
            "description" => @project.description
          },
          "counts" => {
            "chats" => @project.chats.count,
            "experiments" => @project.experiments.count,
            "runs" => @project.runs.count
          }
        }
      end
    end
  end
end

module Ai
  class ChatTooling
    def self.snapshot(project)
      Ai::ToolRegistry.snapshot(project)
    end

    def initialize(chat:, project:, run: nil)
      @chat = chat
      @project = project
      @run = run
    end

    def configure
      return @chat unless @chat.respond_to?(:with_tools)

      @chat.with_tools(nil)
      @chat.with_tools(*tool_definitions.map { |definition| definition.tool_instance(run: @run) })
      @chat
    end

    def tool_definitions
      keys = snapshot_keys
      return ToolDefinition.none if keys.empty?

      definitions = @project.tool_definitions.where(key: keys).to_a
      definitions.sort_by { |definition| keys.index(definition.key) || keys.length }
    end

    private

    def snapshot_keys
      snapshot = @run&.input_snapshot&.fetch("tools", []) || []
      Array(snapshot).filter_map do |entry|
        entry.is_a?(Hash) ? (entry["key"] || entry[:key]).to_s.presence : entry.to_s.presence
      end
    end
  end
end

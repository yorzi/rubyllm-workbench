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

      @chat.with_provider_tools(nil) if @chat.respond_to?(:with_provider_tools)
      @chat.with_tools(nil)
      @chat.with_tools(*tool_definitions.map { |definition| definition.tool_instance(run: @run) })
      apply_provider_tools
      apply_tool_options
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

    def apply_tool_options
      return unless @chat.respond_to?(:with_tool_options)

      @chat.with_tool_options(**Ai::ToolExecutionPolicy.ruby_llm_options(@run&.input_snapshot&.fetch("tool_options", nil)))
    end

    def apply_provider_tools
      return unless @chat.respond_to?(:with_provider_tools)

      provider_tool_keys.each do |key|
        @chat.with_provider_tools(key.to_sym)
      end
    end

    def provider_tool_keys
      Array(@run&.input_snapshot&.fetch("provider_tools", [])).filter_map do |entry|
        entry.to_s.presence if entry.to_s == "web_search"
      end
    end
  end
end

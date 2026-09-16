module Ai
  class ToolExecutionPolicy
    MODES = %w[sequential parallel].freeze

    class << self
      def snapshot(project:, chat:)
        new(project:, chat:).snapshot
      end

      def ruby_llm_options(snapshot)
        mode = snapshot_value(snapshot, "effective_mode")
        return { calls: :many, concurrency: :threads } if mode == "parallel"

        { calls: :one, concurrency: false }
      end

      private

      def snapshot_value(snapshot, key)
        values = snapshot.respond_to?(:to_h) ? snapshot.to_h : {}
        values[key] || values[key.to_sym]
      end
    end

    def initialize(project:, chat:)
      @project = project
      @chat = chat
    end

    def snapshot
      requested_mode = @project.tool_execution_mode
      capability = parallel_capability(requested_mode)
      definitions = enabled_tool_definitions
      effective_mode, fallback_reason = resolve_effective_mode(requested_mode, capability, definitions)

      {
        "requested_mode" => requested_mode,
        "effective_mode" => effective_mode,
        "calls" => effective_mode == "parallel" ? "many" : "one",
        "concurrency" => effective_mode == "parallel" ? "threads" : "none",
        "parallel_tool_calls_capability" => capability,
        "fallback_reason" => fallback_reason
      }.compact
    end

    private

    def enabled_tool_definitions
      @project.tool_definitions.enabled.order(:key).to_a
    end

    def resolve_effective_mode(requested_mode, capability, definitions)
      return [ "sequential", nil ] unless requested_mode == "parallel"
      return [ "sequential", "no_enabled_tools" ] if definitions.empty?
      return [ "sequential", "model_capability_missing" ] if capability == "missing"
      return [ "sequential", "model_capability_unknown" ] unless capability == "supported"
      return [ "sequential", "tool_not_parallel_safe" ] unless definitions.all?(&:parallel_safe?)

      [ "parallel", nil ]
    end

    def parallel_capability(requested_mode)
      return "not_requested" unless requested_mode == "parallel"
      return "unknown" unless @chat.respond_to?(:model)

      model = @chat.model
      return "unknown" unless model&.respond_to?(:supports?)

      model.supports?(:parallel_tool_calls) ? "supported" : "missing"
    rescue StandardError
      "unknown"
    end
  end
end

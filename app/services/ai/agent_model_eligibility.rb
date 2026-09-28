module Ai
  class AgentModelEligibility
    CAPABILITY = "function_calling".freeze
    ERROR_MESSAGE = [
      "Local tools require a model listed in RubyLLM's chat registry with declared function_calling support.",
      "Registry metadata does not verify live provider acceptance."
    ].join(" ").freeze

    def initialize(catalog: ModelCatalog.new)
      @catalog = catalog
    end

    def eligible?(provider:, model_id:, tool_keys:)
      return true unless Array(tool_keys).any? { |key| key.to_s.present? }

      entry = @catalog.find_entry(model_id.to_s, provider: provider.to_s)
      entry&.supports?(CAPABILITY) == true
    end

    def ensure_eligible!(provider:, model_id:, tool_keys:)
      return true if eligible?(provider:, model_id:, tool_keys:)

      raise ArgumentError, ERROR_MESSAGE
    end
  end
end

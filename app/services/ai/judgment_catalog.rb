module Ai
  class JudgmentCatalog
    # RubyLLM 2.1's typed Judge uses a decision protocol. Chat Completions models
    # with structured output (including OpenRouter) are not decision models.
    PROVIDERS = %w[typesafe openai ollama ollama_cloud].freeze

    def self.entries(config: RubyLLM.config, configured: nil)
      models = RubyLLM.models.all.select do |model|
        PROVIDERS.include?(model.provider.to_s) && model.type == :judgment
      end
      Ai::ModelCatalog.new(models:, config:).entries(configured:)
    end
  end
end

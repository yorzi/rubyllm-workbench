module Ai
  class SpeechCatalog
    CAPABILITY = "speech_generation".freeze

    def self.entries(models: nil, config: RubyLLM.config, query: nil, provider: nil, configured: nil)
      speech_models = Array(models || RubyLLM.models.all).select do |model|
        Array(model.capabilities).map(&:to_s).include?(CAPABILITY)
      end

      Ai::ModelCatalog.new(models: speech_models, config: config)
        .entries(query: query, provider: provider, configured: configured)
    end

    def self.configured_entries(models: nil, config: RubyLLM.config)
      entries(models: models, config: config, configured: true)
    end

    def self.find(model_id, provider: nil, models: nil, config: RubyLLM.config)
      return if model_id.blank?

      matches = entries(models: models, config: config).select { |entry| entry.id.to_s == model_id.to_s }
      matches = matches.select { |entry| entry.provider == provider.to_s } if provider.present?
      matches.first
    end
  end
end

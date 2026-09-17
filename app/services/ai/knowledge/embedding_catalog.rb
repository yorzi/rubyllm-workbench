module Ai
  module Knowledge
    # Lists embedding-capable models and whether their provider is configured.
    #
    # Semantic retrieval must not silently fall back to a half-working path:
    # callers gate on `available?` and surface an explicit reason when the
    # selected embedding model is missing, unconfigured or not embedding
    # capable.
    class EmbeddingCatalog
      def self.entries(models: nil, config: RubyLLM.config, query: nil, provider: nil, configured: nil)
        catalog_models = Array(models || RubyLLM.models.embedding_models.all)
        Ai::ModelCatalog.new(models: catalog_models, config: config)
          .entries(query: query, provider: provider, configured: configured)
      end

      def self.configured_entries(models: nil, config: RubyLLM.config)
        entries(models: models, config: config, configured: true)
      end

      def self.find(model_id, provider: nil, models: nil, config: RubyLLM.config)
        return nil if model_id.blank?

        matches = entries(models: models, config: config).select { |entry| entry.id.to_s == model_id.to_s }
        matches = matches.select { |entry| entry.provider == provider.to_s } if provider.present?
        matches.first
      end

      def self.availability(model_id, models: nil, config: RubyLLM.config)
        return Availability.new(available: false, reason: "No embedding model is selected.", entry: nil) if model_id.blank?

        entry = find(model_id, models: models, config: config)
        return Availability.new(available: false, reason: "Embedding model #{model_id} is not in the RubyLLM catalog.", entry: nil) if entry.nil?
        return Availability.new(available: false, reason: "#{entry.provider_name} is not configured.", entry: entry) unless entry.configured

        Availability.new(available: true, reason: nil, entry: entry)
      end

      Availability = Data.define(:available, :reason, :entry)
    end
  end
end

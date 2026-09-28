module Ai
  class MediaCatalog
    OPERATIONS = {
      "image" => "image_generation",
      "transcription" => "transcription"
    }.freeze

    def self.entries(operation:, models: nil, config: RubyLLM.config, query: nil, provider: nil, configured: nil)
      unless OPERATIONS.key?(operation.to_s) || operation.to_s == "video"
        raise ArgumentError, "Unsupported media operation: #{operation}"
      end
      compatible_models = Array(models || RubyLLM.models.all).select do |model|
        supports_operation?(model, operation.to_s)
      end

      Ai::ModelCatalog.new(models: compatible_models, config: config)
        .entries(query: query, provider: provider, configured: configured)
    end

    def self.find(operation:, model_id:, provider: nil, models: nil, config: RubyLLM.config)
      return if model_id.blank?

      entries(operation:, models:, config:).find do |entry|
        entry.id.to_s == model_id.to_s && (provider.blank? || entry.provider == provider.to_s)
      end
    end

    def self.supports_operation?(model, operation)
      return Array(model.capabilities).map(&:to_s).include?(OPERATIONS.fetch(operation)) if OPERATIONS.key?(operation)

      model.type.to_s == "video" && Array(model.modalities&.output).map(&:to_s).include?("video")
    end
    private_class_method :supports_operation?
  end
end

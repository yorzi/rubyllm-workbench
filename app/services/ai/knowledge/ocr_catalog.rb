module Ai
  module Knowledge
    # Lists OCR-capable models and whether their provider is configured.
    #
    # Text-like attachments are extracted locally; anything else needs a
    # provider OCR model. When none is configured the extractor says so instead
    # of pretending a binary file was read.
    class OcrCatalog
      CAPABILITY = "ocr".freeze

      def self.entries(models: nil, config: RubyLLM.config, query: nil, provider: nil, configured: nil)
        catalog_models = Array(models || ocr_models)
        Ai::ModelCatalog.new(models: catalog_models, config: config)
          .entries(query: query, provider: provider, configured: configured)
      end

      def self.configured_entries(models: nil, config: RubyLLM.config)
        entries(models: models, config: config, configured: true)
      end

      def self.ocr_models
        RubyLLM.models.all.select { |model| Array(model.capabilities).include?(CAPABILITY) }
      end

      def self.find(model_id, provider: nil, models: nil, config: RubyLLM.config)
        return nil if model_id.blank?

        matches = entries(models: models, config: config).select { |entry| entry.id.to_s == model_id.to_s }
        matches = matches.select { |entry| entry.provider == provider.to_s } if provider.present?
        matches.first
      end

      def self.availability(model_id, models: nil, config: RubyLLM.config)
        return Availability.new(available: false, reason: "No OCR model is selected.", entry: nil) if model_id.blank?

        entry = find(model_id, models: models, config: config)
        return Availability.new(available: false, reason: "OCR model #{model_id} is not in the RubyLLM catalog.", entry: nil) if entry.nil?
        return Availability.new(available: false, reason: "#{entry.provider_name} is not configured.", entry: entry) unless entry.configured

        Availability.new(available: true, reason: nil, entry: entry)
      end

      Availability = Data.define(:available, :reason, :entry)
    end
  end
end

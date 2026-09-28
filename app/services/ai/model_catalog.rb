module Ai
  class ModelCatalog
    Descriptor = Struct.new(
      :model,
      :configured,
      :provider_name,
      :missing_configuration,
      keyword_init: true
    ) do
      delegate :id, :name, :provider, :capabilities, :modalities, :context_window,
        :max_output_tokens, :pricing, :unlisted?, :supports?, to: :model

      def interactive?
        !id.to_s.end_with?(":batch")
      end

      def status
        configured ? "configured" : "needs configuration"
      end

      def capability_badges
        model.capabilities.map(&:to_s).uniq.sort
      end
    end

    FILTERABLE_CAPABILITIES = %w[streaming vision function_calling structured_output].freeze

    def initialize(models: nil, config: RubyLLM.config)
      @models = Array(models || RubyLLM.models.chat_models.all)
      @config = config
    end

    def entries(query: nil, provider: nil, capability: nil, configured: nil)
      descriptors = @models.map { |model| descriptor_for(model) }
      descriptors.select! { |entry| matches_query?(entry, query) } if query.present?
      descriptors.select! { |entry| entry.provider == provider.to_s } if provider.present?
      descriptors.select! { |entry| entry.supports?(capability) } if capability.present?

      configured_value = configured_value_for(configured)
      descriptors.select! { |entry| entry.configured == configured_value } unless configured_value.nil?

      descriptors.sort_by { |entry| [ entry.provider_name.to_s, entry.name.to_s, entry.id.to_s ] }
    end

    def find!(model_id, provider: nil)
      RubyLLM.models.find(model_id, provider: provider.presence, config: @config)
    end

    def find_entry(model_id, provider:)
      model = @models.find do |candidate|
        candidate.id == model_id && candidate.provider == provider.to_s
      end
      descriptor_for(model) if model
    end

    def providers
      entries.map { |entry| [ entry.provider, entry.provider_name ] }.uniq.sort_by(&:last)
    end

    private

    def descriptor_for(model)
      provider_class = model.provider_class
      requirements = provider_class ? provider_class.configuration_requirements : []
      missing = requirements.reject { |requirement| @config.public_send(requirement).present? }

      Descriptor.new(
        model: model,
        configured: missing.empty?,
        provider_name: provider_class&.display_name || model.provider.to_s.humanize,
        missing_configuration: missing.map(&:to_s)
      )
    rescue NoMethodError
      Descriptor.new(
        model: model,
        configured: false,
        provider_name: model.provider.to_s.humanize,
        missing_configuration: []
      )
    end

    def matches_query?(entry, query)
      needle = query.to_s.downcase
      [ entry.id, entry.name, entry.provider, entry.provider_name ].compact.any? do |value|
        value.to_s.downcase.include?(needle)
      end
    end

    def configured_value_for(value)
      case value.to_s
      when "true" then true
      when "false" then false
      end
    end
  end
end

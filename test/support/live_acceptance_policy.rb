require "bigdecimal"
require "net/http"

# Test-only limits for deliberate live acceptance. Production configuration is
# untouched; hooks use RubyLLM 2.1's public request callback and options APIs.
class LiveAcceptancePolicy
  class Unavailable < StandardError; end
  class GuardViolation < StandardError; end

  MAX_REQUESTS = 24
  MAX_OUTPUT_TOKENS = 2048
  CATALOG_PATHS = {
    embedding: "/api/v1/embeddings/models",
    rerank: "/api/v1/models?output_modalities=rerank"
  }.freeze

  class << self
    attr_accessor :active

    def catalogs
      @catalogs ||= {}
    end
  end

  module ChatLimits
    def initialize(...)
      super
      policy = LiveAcceptancePolicy.active
      before_request { |payload| policy.guard_chat!(payload) } if policy
    end
  end

  module OneShotLimits
    def embed(...)
      policy = LiveAcceptancePolicy.active
      policy ? policy.one_shot(:embed, ...) : super
    end

    def rerank(...)
      policy = LiveAcceptancePolicy.active
      policy ? policy.one_shot(:rerank, ...) : super
    end
  end

  class RequestBudget
    attr_reader :requests

    def initialize(delegate)
      @delegate = delegate
      @requests = 0
    end

    def instrument(name, payload, &block)
      if name == "request.ruby_llm" && payload[:method].to_s == "post"
        raise GuardViolation, "Live acceptance exceeded #{MAX_REQUESTS} HTTP requests; stop and inspect the report." if @requests >= MAX_REQUESTS
        @requests += 1
      end
      @delegate.instrument(name, payload, &block)
    end
  end

  def initialize(provider:, models:, catalog_fetcher: nil)
    @provider = provider.to_s
    @models = models
    @paid = ENV["LIVE_DOGFOOD_PAID"] == "1"
    @catalog_fetcher = catalog_fetcher || method(:fetch_catalog)
    @checked = []
  end

  def configure!
    raise Unavailable, "Free acceptance supports OpenRouter only; select it explicitly." unless @paid || @provider == "openrouter"
    unless RubyLLM::Provider.resolve(@provider).configured?(RubyLLM.config)
      raise Unavailable, "#{@provider} is not configured; manual acceptance is required."
    end

    RubyLLM.config.max_retries = 0
    RubyLLM.config.request_timeout = 60
    unless RubyLLM.config.instrumenter.is_a?(RequestBudget)
      RubyLLM.config.instrumenter = RequestBudget.new(RubyLLM.config.instrumenter || ActiveSupport::Notifications)
    end
    @initial_request_count = RubyLLM.config.instrumenter.requests
    RubyLLM::Chat.prepend(ChatLimits) unless RubyLLM::Chat < ChatLimits
    # Bound one-shot calls without changing the application's client boundary.
    RubyLLM.singleton_class.prepend(OneShotLimits) unless RubyLLM.singleton_class < OneShotLimits
    self.class.active = self
  end

  def request_count
    return unless @initial_request_count
    RubyLLM.config.instrumenter.requests - @initial_request_count
  end

  def check!(*keys)
    keys.each do |key|
      id = @models.fetch(key).to_s
      begin
        RubyLLM.models.find(id, provider: @provider)
      rescue RubyLLM::ModelNotFoundError
        raise Unavailable, "#{@provider}/#{id} is absent from RubyLLM's registry; manual acceptance is required."
      end
      unless @paid
        raise Unavailable, "#{id} is not an explicit :free model; paid fallback is excluded." unless id.end_with?(":free")
        path = CATALOG_PATHS.fetch(key, "/api/v1/models")
        entry = @catalog_fetcher.call(path).find { |model| model["id"] == id }
        raise Unavailable, "#{id} is absent from the current OpenRouter catalog; manual acceptance is required." unless entry
        prices = entry.fetch("pricing", {})
        unless prices.key?("prompt") && prices.key?("completion") && prices.values.all? { |value| zero_price?(value) }
          raise Unavailable, "#{id} has nonzero or unknown catalog prices; manual acceptance is required."
        end
      end
      @checked |= [ id ]
    end
  end

  def guard_chat!(payload)
    return if @paid
    model = payload[:model] || payload["model"]
    guard_model!(model)
    raise GuardViolation, "Model fallback lists are excluded from free acceptance." if payload.key?(:models) || payload.key?("models")
    tools = Array(payload[:tools]) + Array(payload["tools"])
    unless tools.all? { |tool| (tool[:type] || tool["type"]) == "function" }
      raise GuardViolation, "Hosted tools require manual acceptance with an explicit budget."
    end
    token_keys = %w[max_tokens max_completion_tokens max_output_tokens]
    caps = token_keys.to_h { |key| [ key, payload[key.to_sym] || payload[key] ] }.compact
    caps["max_tokens"] = MAX_OUTPUT_TOKENS if caps.empty?
    %w[model tools plugins provider max_tokens].each { |key| payload.delete(key) }
    payload[:model] = model
    payload[:tools] = tools if tools.any?
    payload[:plugins] = [ { id: "web", enabled: false } ]
    payload[:provider] = { allow_fallbacks: false, max_price: { prompt: 0, completion: 0, request: 0 } }
    token_keys.each { |key| payload.delete(key) }
    caps.each { |key, cap| payload[key.to_sym] = [ cap.to_i, MAX_OUTPUT_TOKENS ].min }
  end

  def one_shot(operation, *args, **options, &block)
    unless @paid
      guard_model!(options[:model])
      raise GuardViolation, "Only OpenRouter is permitted in free acceptance." unless options[:provider].to_s == @provider
      extras = (options[:provider_options] || {}).dup
      if extras.keys.any? { |key| %w[model models plugins tools].include?(key.to_s) }
        raise GuardViolation, "One-shot model overrides and hosted extras are excluded from free acceptance."
      end
      extras.delete("provider")
      options[:provider_options] = extras.merge(
        provider: { allow_fallbacks: false, max_price: { prompt: 0, completion: 0, request: 0 } }
      )
    end
    # The prepended wrapper's super method is the original public operation.
    RubyLLM.method(operation).super_method.call(*args, **options, &block)
  end

  private

  def guard_model!(id)
    raise GuardViolation, "Unchecked model #{id}; refusing a live request." unless @checked.include?(id.to_s)
  end

  def zero_price?(value)
    BigDecimal(value.to_s).zero?
  rescue ArgumentError
    false
  end

  def fetch_catalog(path)
    self.class.catalogs[path] ||= begin
      uri = URI("https://openrouter.ai#{path}")
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 15) { |http| http.get(uri.request_uri) }
      raise Unavailable, "OpenRouter catalog returned HTTP #{response.code}; manual acceptance is required." unless response.is_a?(Net::HTTPSuccess)
      JSON.parse(response.body).fetch("data")
    end
  rescue JSON::ParserError, KeyError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError => error
    raise Unavailable, "OpenRouter catalog could not be checked (#{error.class}); manual acceptance is required."
  end
end

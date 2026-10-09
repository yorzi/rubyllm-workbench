require "test_helper"
require_relative "../support/live_acceptance_policy"

class LiveAcceptancePolicyTest < ActiveSupport::TestCase
  FREE_MODEL = "fixture/model:free".freeze
  ZERO_PRICES = { "prompt" => "0", "completion" => "0" }.freeze
  MethodHandle = Data.define(:super_method)

  class OfflineOperation
    attr_reader :calls

    def initialize
      @calls = []
    end

    def call(*arguments, **options)
      @calls << { arguments: arguments, options: options }
      :offline_result
    end
  end

  class OfflineInstrumenter
    attr_reader :events

    def initialize
      @events = []
    end

    def instrument(name, payload)
      @events << [ name, payload ]
      yield payload if block_given?
    end
  end

  setup do
    @original_paid = ENV["LIVE_DOGFOOD_PAID"]
    @original_active = LiveAcceptancePolicy.active
    @original_config = %i[max_retries request_timeout instrumenter].to_h do |key|
      [ key, RubyLLM.config.public_send(key) ]
    end
    ENV.delete("LIVE_DOGFOOD_PAID")
    LiveAcceptancePolicy.active = nil
    @catalog = [ { "id" => FREE_MODEL, "pricing" => ZERO_PRICES.dup } ]
    @catalog_paths = []
    @registry = Object.new
    @registry.define_singleton_method(:find) { |_id, provider:| provider }
  end

  teardown do
    ENV["LIVE_DOGFOOD_PAID"] = @original_paid
    LiveAcceptancePolicy.active = @original_active
    @original_config.each { |key, value| RubyLLM.config.public_send("#{key}=", value) }
  end

  test "only explicit free suffixes pass the unpaid model selection gate" do
    [ "fixture/model", "fixture/model-free", "fixture/model:free:batch", "fixture/model:FREE", "openrouter/free" ].each do |id|
      policy = build_policy(models: { chat: id })
      error = assert_raises(LiveAcceptancePolicy::Unavailable) { check(policy, :chat) }
      assert_match(/explicit :free/, error.message)
    end
    assert_empty @catalog_paths, "non-free IDs must fail before catalog fetching"
    checked_policy.guard_chat!({ model: FREE_MODEL })
  end

  test "all catalog prices must be known and zero including request surcharges" do
    [ {}, { "prompt" => "0" }, { "prompt" => nil, "completion" => "0" },
      { "prompt" => "0.001", "completion" => "0" },
      ZERO_PRICES.merge("request" => "0.01"), ZERO_PRICES.merge("web_search" => "unknown"),
      ZERO_PRICES.merge("request" => "NaN") ].each do |pricing|
      @catalog.first["pricing"] = pricing
      assert_raises(LiveAcceptancePolicy::Unavailable) { check(build_policy, :chat) }
    end
    @catalog.first["pricing"] = { "prompt" => 0, "completion" => "0.000", "request" => "0e0" }
    assert_nothing_raised { check(build_policy, :chat) }
  end

  test "missing registry or public catalog entries cannot authorize a model" do
    missing = ->(*, **) { raise RubyLLM::ModelNotFoundError, "offline missing model" }
    with_stub(@registry, :find, missing) do
      assert_raises(LiveAcceptancePolicy::Unavailable) { check(build_policy, :chat) }
    end
    assert_empty @catalog_paths
    @catalog.clear
    policy = build_policy
    assert_raises(LiveAcceptancePolicy::Unavailable) { check(policy, :chat) }
    assert_raises(LiveAcceptancePolicy::GuardViolation) { policy.guard_chat!({ model: FREE_MODEL }) }
  end

  test "embedding and rerank use their own public model inventories" do
    policy = build_policy(models: { embedding: FREE_MODEL, rerank: FREE_MODEL })
    check(policy, :embedding, :rerank)
    assert_equal [ "/api/v1/embeddings/models", "/api/v1/models?output_modalities=rerank" ], @catalog_paths
  end

  test "checking one model never authorizes a different model" do
    policy = checked_policy
    assert_raises(LiveAcceptancePolicy::GuardViolation) { policy.guard_chat!({ model: "fixture/other:free" }) }
    assert_raises(LiveAcceptancePolicy::GuardViolation) { policy.guard_chat!({}) }
    assert_nothing_raised { policy.guard_chat!({ "model" => FREE_MODEL }) }
  end

  test "hosted tools and model fallback lists fail before a request" do
    policy = checked_policy
    [ { tools: [ { type: "web_search" } ] }, { "tools" => [ { "type" => "web_search" } ] },
      { tools: [ { type: "function" } ], "tools" => [ { "type" => "web_search" } ] },
      { models: [ "fixture/paid" ] }, { "models" => [] } ].each do |options|
      assert_raises(LiveAcceptancePolicy::GuardViolation) { policy.guard_chat!({ model: FREE_MODEL }.merge(options)) }
    end
    payload = { model: FREE_MODEL, tools: [ { type: "function", function: { name: "project_snapshot" } } ] }
    assert_nothing_raised { policy.guard_chat!(payload) }
  end

  test "free routing overrides unsafe options and removes duplicate JSON keys" do
    payload = { model: FREE_MODEL, "model" => "fixture/paid", provider: { allow_fallbacks: true },
      "provider" => { "allow_fallbacks" => true }, plugins: [ { id: "web" } ],
      "plugins" => [ { "id" => "web" } ], max_tokens: 99_999, "max_tokens" => 88_888,
      tools: [ { type: "function", function: { name: "project_snapshot" } } ], "tools" => [] }
    checked_policy.guard_chat!(payload)
    %w[model tools provider plugins max_tokens].each do |key|
      assert_equal 1, payload.keys.count { |candidate| candidate.to_s == key }, "duplicate #{key} key"
    end
    serialized = JSON.parse(JSON.generate(payload))
    assert_equal FREE_MODEL, serialized.fetch("model")
    assert_equal false, serialized.dig("provider", "allow_fallbacks")
    assert_equal({ "prompt" => 0, "completion" => 0, "request" => 0 }, serialized.dig("provider", "max_price"))
    assert_equal [ { "id" => "web", "enabled" => false } ], serialized.fetch("plugins")
    assert_equal LiveAcceptancePolicy::MAX_OUTPUT_TOKENS, serialized.fetch("max_tokens")
  end

  test "output cap applies by default and preserves smaller requested limits" do
    policy = checked_policy
    [ [ {}, LiveAcceptancePolicy::MAX_OUTPUT_TOKENS ],
      [ { max_tokens: 99_999 }, LiveAcceptancePolicy::MAX_OUTPUT_TOKENS ],
      [ { max_tokens: 17 }, 17 ], [ { "max_tokens" => 23 }, 23 ] ].each do |options, expected|
      payload = { model: FREE_MODEL }.merge(options)
      policy.guard_chat!(payload)
      assert_equal expected, payload.fetch(:max_tokens)
    end
    %w[max_completion_tokens max_output_tokens].each do |key|
      payload = { model: FREE_MODEL, key => 99_999 }
      policy.guard_chat!(payload)
      assert_equal LiveAcceptancePolicy::MAX_OUTPUT_TOKENS, payload.fetch(key.to_sym)
      refute payload.key?(key), "string token limit must not override the safe cap"
    end
  end

  test "one-shot calls reject unchecked models and other providers before delegation" do
    operation = OfflineOperation.new
    with_offline_operation(operation) do
      assert_raises(LiveAcceptancePolicy::GuardViolation) do
        checked_policy.one_shot(:embed, "fixture", model: "fixture/other:free", provider: "openrouter")
      end
      assert_raises(LiveAcceptancePolicy::GuardViolation) do
        checked_policy.one_shot(:embed, "fixture", model: FREE_MODEL, provider: "openai")
      end
    end
    assert_empty operation.calls
  end

  test "one-shot routing is guarded while operation-specific options survive" do
    operation = OfflineOperation.new
    with_offline_operation(operation) do
      result = checked_policy.one_shot(:embed, "fixture", model: FREE_MODEL, provider: "openrouter",
        provider_options: { encoding_format: "float", provider: { allow_fallbacks: true }, "provider" => { "allow_fallbacks" => true } })
      assert_equal :offline_result, result
    end
    options = operation.calls.fetch(0).fetch(:options).fetch(:provider_options)
    assert_equal "float", options.fetch(:encoding_format)
    assert_equal 1, options.keys.count { |key| key.to_s == "provider" }
    assert_equal false, JSON.parse(JSON.generate(options)).dig("provider", "allow_fallbacks")
  end

  test "one-shot provider options cannot replace checked models or add hosted work" do
    operation = OfflineOperation.new
    with_offline_operation(operation) do
      [ { model: "fixture/paid" }, { "model" => "fixture/paid" },
        { models: [ "fixture/paid" ] }, { "models" => [ "fixture/paid" ] },
        { plugins: [ { id: "web" } ] }, { "plugins" => [ { "id" => "web" } ] } ].each do |provider_options|
        assert_raises(LiveAcceptancePolicy::GuardViolation) do
          checked_policy.one_shot(:embed, "fixture", model: FREE_MODEL, provider: "openrouter", provider_options:)
        end
      end
    end
    assert_empty operation.calls
  end

  test "HTTP budget allows the exact limit and refuses every later request before delegation" do
    delegate = OfflineInstrumenter.new
    budget = LiveAcceptancePolicy::RequestBudget.new(delegate)
    dispatched = 0
    LiveAcceptancePolicy::MAX_REQUESTS.times do
      budget.instrument("request.ruby_llm", { method: :post }) { dispatched += 1 }
    end
    2.times do
      assert_raises(LiveAcceptancePolicy::GuardViolation) do
        budget.instrument("request.ruby_llm", { method: :post }) { dispatched += 1 }
      end
    end
    assert_equal LiveAcceptancePolicy::MAX_REQUESTS, dispatched
    assert_equal LiveAcceptancePolicy::MAX_REQUESTS, delegate.events.size
  end

  test "metadata and GET notifications do not consume generation request budget" do
    delegate = OfflineInstrumenter.new
    budget = LiveAcceptancePolicy::RequestBudget.new(delegate)
    (LiveAcceptancePolicy::MAX_REQUESTS + 1).times do
      budget.instrument("request.ruby_llm", { method: :get }) { }
      budget.instrument("chat.ruby_llm", { model: FREE_MODEL }) { }
    end
    LiveAcceptancePolicy::MAX_REQUESTS.times { budget.instrument("request.ruby_llm", { method: :post }) { } }
    assert_raises(LiveAcceptancePolicy::GuardViolation) { budget.instrument("request.ruby_llm", { method: :post }) { } }
  end

  test "only the exact paid flag permits paid models and bypasses free routing constraints" do
    [ nil, "", "0", "false", "true", "yes" ].each do |flag|
      ENV["LIVE_DOGFOOD_PAID"] = flag
      assert_raises(LiveAcceptancePolicy::Unavailable) { check(build_policy(models: { chat: "fixture/paid" }), :chat) }
    end
    ENV["LIVE_DOGFOOD_PAID"] = "1"
    policy = build_policy(models: { chat: "fixture/paid" })
    check(policy, :chat)
    assert_empty @catalog_paths, "paid authorization should not claim zero-price verification"
    payload = { model: "fixture/paid", tools: [ { type: "web_search" } ], models: [ "fixture/other" ] }
    original = payload.deep_dup
    assert_nothing_raised { policy.guard_chat!(payload) }
    assert_equal original, payload
  end

  private

  def build_policy(models: { chat: FREE_MODEL })
    fetcher = lambda do |path|
      @catalog_paths << path
      @catalog
    end
    LiveAcceptancePolicy.new(provider: "openrouter", models:, catalog_fetcher: fetcher)
  end

  def check(policy, *keys)
    registry = @registry
    with_stub(RubyLLM, :models, -> { registry }) { policy.check!(*keys) }
  end

  def checked_policy
    build_policy.tap { |policy| check(policy, :chat) }
  end

  def with_offline_operation(operation, &block)
    with_stub(RubyLLM, :method, ->(*) { MethodHandle.new(super_method: operation) }, &block)
  end

  def with_stub(target, method_name, replacement)
    singleton = target.singleton_class
    owned = singleton.instance_methods(false).include?(method_name)
    original = singleton.instance_method(method_name).bind(target)
    target.define_singleton_method(method_name, replacement)
    yield
  ensure
    if owned
      target.define_singleton_method(method_name, original)
    else
      singleton.remove_method(method_name)
    end
  end
end

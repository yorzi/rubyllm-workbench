require "test_helper"

class Ai::CostNormalizerTest < ActiveSupport::TestCase
  SpeechUsage = Struct.new(:tokens, :cost)
  StoredUsage = Data.define(:tokens, :cost, :total_cost)

  test "preserves a ledger total instead of repricing it from current metadata" do
    tokens = RubyLLM::Tokens.new(input: 10, output: 5)
    model = RubyLLM::Model.new(id: "repriced", provider: "openai", pricing: { text_tokens: { standard: { input_per_million: 999, output_per_million: 999 } } })
    usage = StoredUsage.new(tokens, RubyLLM::Cost.from_h({ total: 0.02 }), BigDecimal("0.02"))

    result = Ai::CostNormalizer.for(usage, model:)

    assert_equal "recorded", result.fetch(:cost_status)
    assert_equal BigDecimal("0.02"), result.fetch(:recorded_cost)
    assert_nil result.fetch(:reported_cost)
    assert_nil result.fetch(:estimated_cost)
  end

  test "retains zero and unknown ledger cost as different outcomes" do
    tokens = RubyLLM::Tokens.new(input: 10)
    [ [ 0, "recorded" ], [ nil, "unknown" ] ].each do |amount, status|
      usage = StoredUsage.new(tokens, RubyLLM::Cost.from_h({}), amount)
      result = Ai::CostNormalizer.for(usage, model: RubyLLM.models.chat_models.all.first)

      assert_equal status, result.fetch(:cost_status)
      amount.nil? ? assert_nil(result.fetch(:recorded_cost)) : assert_equal(amount, result.fetch(:recorded_cost))
      assert_nil result.fetch(:estimated_cost)
    end
  end

  test "a default cache zero without measured usage is unknown while the native row remains intact" do
    tokens = RubyLLM::Tokens.new(cache_write: 0)
    usage = StoredUsage.new(tokens, RubyLLM::Cost.from_h({ cache_write: 0, total: 0 }), BigDecimal("0"))
    result = Ai::CostNormalizer.for(usage)
    assert_equal "unknown", result[:cost_status]
    assert_nil result[:recorded_cost]
    assert_equal BigDecimal("0"), usage.total_cost
    response = SpeechUsage.new(tokens, RubyLLM::Cost.new(tokens:))
    assert_equal "unknown", Ai::CostNormalizer.for(response, model: RubyLLM.models.chat_models.all.first)[:cost_status]
  end

  test "explicit reported zero is retained even without token measurements" do
    tokens = RubyLLM::Tokens.new(reported_cost: 0)
    result = Ai::CostNormalizer.for(SpeechUsage.new(tokens, RubyLLM::Cost.new(tokens:)))
    assert_equal "reported", result[:cost_status]
    assert_equal 0, result[:reported_cost]
  end

  test "keeps the provider-reported total including hosted tool fees" do
    tokens = RubyLLM::Tokens.new(input: 10, output: 5, server_tool_use: { "web_search_requests" => 2 }, reported_cost: 0.02)
    result = Ai::CostNormalizer.for(SpeechUsage.new(tokens, RubyLLM::Cost.new(tokens:)))

    assert_equal "reported", result.fetch(:cost_status)
    assert_equal 0.02, result.fetch(:reported_cost)
  end

  test "estimates speech usage using audio token prices" do
    model = RubyLLM::Model.new(
      id: "test-priced-speech-model",
      name: "Test priced speech model",
      provider: "openai",
      pricing: {
        text_tokens: { standard: { output_per_million: 20 } },
        audio_tokens: { standard: { output_per_million: 3 } }
      }
    )
    usage = SpeechUsage.new(RubyLLM::Tokens.new(output: 100), nil)

    result = Ai::CostNormalizer.for(usage, model:, category: :audio_tokens)

    assert_equal "estimated", result.fetch(:cost_status)
    assert_in_delta 0.0003, result.fetch(:estimated_cost), 0.0000001
  end

  test "keeps text token pricing as the default category" do
    model = RubyLLM::Model.new(
      id: "test-priced-text-model",
      name: "Test priced text model",
      provider: "openai",
      pricing: {
        text_tokens: { standard: { output_per_million: 20 } },
        audio_tokens: { standard: { output_per_million: 3 } }
      }
    )
    usage = SpeechUsage.new(RubyLLM::Tokens.new(output: 100), nil)

    result = Ai::CostNormalizer.for(usage, model:)

    assert_equal "estimated", result.fetch(:cost_status)
    assert_in_delta 0.002, result.fetch(:estimated_cost), 0.0000001
  end
end

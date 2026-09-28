require "test_helper"

class Ai::CostNormalizerTest < ActiveSupport::TestCase
  SpeechUsage = Struct.new(:tokens, :cost)

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

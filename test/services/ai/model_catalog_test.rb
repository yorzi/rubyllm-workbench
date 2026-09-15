require "test_helper"

class Ai::ModelCatalogTest < ActiveSupport::TestCase
  test "exposes provider configuration without exposing credentials" do
    model = RubyLLM.models.chat_models.first
    entry = Ai::ModelCatalog.new(models: [ model ]).entries.first

    assert_equal model.id, entry.id
    assert_equal model.provider, entry.provider
    assert_equal false, entry.configured
    assert_includes entry.missing_configuration, "#{model.provider}_api_key"
    refute_match(/key|token|secret/i, entry.provider_name)
  end

  test "filters by provider, capability, and configuration state" do
    models = RubyLLM.models.chat_models.first(8)
    catalog = Ai::ModelCatalog.new(models: models)

    provider = models.first.provider
    provider_matches = catalog.entries(provider: provider)
    ready_matches = catalog.entries(configured: "true")
    capability_matches = catalog.entries(capability: "streaming")

    assert provider_matches.all? { |entry| entry.provider == provider }
    assert ready_matches.all?(&:configured)
    assert capability_matches.all? { |entry| entry.supports?(:streaming) }
  end
end

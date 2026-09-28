require "test_helper"

class Ai::AgentModelEligibilityTest < ActiveSupport::TestCase
  MODEL_ID = "eligibility-test-model"
  PROVIDER = "anthropic"

  test "allows local tools when the exact chat model declares function calling" do
    eligibility = service_for(capabilities: [ "function_calling" ])

    assert eligibility.eligible?(provider: PROVIDER, model_id: MODEL_ID, tool_keys: [ "project_snapshot" ])
  end

  test "rejects local tools when the exact chat model does not declare function calling" do
    eligibility = service_for(capabilities: [ "streaming" ])

    assert_not eligibility.eligible?(provider: PROVIDER, model_id: MODEL_ID, tool_keys: [ "project_snapshot" ])
    error = assert_raises(ArgumentError) do
      eligibility.ensure_eligible!(provider: PROVIDER, model_id: MODEL_ID, tool_keys: [ "project_snapshot" ])
    end
    assert_includes error.message, "function_calling"
  end

  test "fails closed when the exact provider and model pair is absent" do
    eligibility = service_for(capabilities: [ "function_calling" ])

    assert_not eligibility.eligible?(provider: "openai", model_id: MODEL_ID, tool_keys: [ "project_snapshot" ])
    assert_not eligibility.eligible?(provider: PROVIDER, model_id: "another-model", tool_keys: [ "project_snapshot" ])
  end

  test "does not apply the local-tool gate to provider-hosted tools" do
    eligibility = service_for(capabilities: [])

    assert eligibility.eligible?(provider: PROVIDER, model_id: MODEL_ID, tool_keys: [])
  end

  private

  def service_for(capabilities:)
    model = RubyLLM::Model.new(
      id: MODEL_ID,
      name: "Eligibility Test Model",
      provider: PROVIDER,
      capabilities:,
      modalities: { input: [ "text" ], output: [ "text" ] },
      pricing: {}
    )
    Ai::AgentModelEligibility.new(catalog: Ai::ModelCatalog.new(models: [ model ]))
  end
end

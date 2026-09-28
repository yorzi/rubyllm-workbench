require "test_helper"

class AgentDefinitionTest < ActiveSupport::TestCase
  setup do
    @project = create_project(name: "Agent definition project")
    Ai::ToolRegistry.sync_project!(@project)
  end

  test "snapshots a normalized definition and increments its revision on edits" do
    definition = @project.agent_definitions.create!(
      name: "Researcher",
      provider: chat_model.provider,
      model_id: chat_model.id,
      instructions: "Find reliable sources.",
      tool_keys: %w[project_snapshot project_snapshot],
      provider_tools: [ "web_search" ],
      options: { temperature: "0.4", max_output_tokens: "1200" }
    )

    snapshot = definition.snapshot
    assert_equal [ "project_snapshot" ], snapshot.fetch("tool_keys")
    snapshot.fetch("options")["temperature"] = 1.8
    snapshot.fetch("tool_keys") << "mutated-copy"
    definition.update!(instructions: "Use primary sources.")

    assert_equal 2, definition.reload.revision
    assert_equal 1, snapshot.fetch("revision")
    assert_equal [ "project_snapshot" ], definition.tool_keys
    assert_equal({ "temperature" => 0.4, "max_output_tokens" => 1200 }, definition.snapshot.fetch("options"))
    assert_equal "Find reliable sources.", snapshot.fetch("instructions")
  end

  test "rejects unavailable local tools, unknown provider tools, and unsafe options" do
    definition = @project.agent_definitions.new(
      name: "Invalid agent",
      provider: chat_model.provider,
      model_id: chat_model.id,
      instructions: "Use only supported capabilities.",
      tool_keys: [ "not_registered" ],
      provider_tools: [ "shell" ],
      options: { "api_key" => "must not be accepted" }
    )

    assert_not definition.valid?
    assert definition.errors[:tool_keys].any?
    assert definition.errors[:provider_tools].any?
    assert definition.errors[:options].any?
  end

  test "rejects local tools when the model is missing from the RubyLLM chat registry" do
    definition = @project.agent_definitions.new(
      name: "Unlisted model agent",
      provider: chat_model.provider,
      model_id: "not-in-the-chat-registry",
      instructions: "Use the project snapshot.",
      tool_keys: [ "project_snapshot" ]
    )

    assert_not definition.valid?
    assert_includes definition.errors[:model_id].join(" "), "function_calling"
  end

  test "allows provider tools without local tools through the local capability gate" do
    definition = @project.agent_definitions.new(
      name: "Hosted search agent",
      provider: chat_model.provider,
      model_id: "not-in-the-chat-registry",
      instructions: "Search for reliable sources.",
      provider_tools: [ "web_search" ]
    )

    assert definition.valid?, definition.errors.full_messages.to_sentence
  end
end

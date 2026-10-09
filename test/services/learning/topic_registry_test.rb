require "test_helper"

class LearningTopicRegistryTest < ActiveSupport::TestCase
  EXPECTED_KEYS = %w[
    model_explorer
    chat_setup
    chat_run
    tool_approval
    experiment_comparison
    run_inspector
    project_boundary
    knowledge_ingestion
    knowledge_search
    grounded_answer
    agent_execution
    evaluation_workflow
  ].freeze

  test "registry exposes the learning topics in a stable order" do
    assert_equal EXPECTED_KEYS, Learning::TopicRegistry.keys
    assert_equal EXPECTED_KEYS, Learning::TopicRegistry.all.map(&:key)
  end

  test "all registered source references are readable and anchored" do
    assert Learning::TopicRegistry.validate!
  end

  test "source reader rejects paths outside its allowlist" do
    reference = Learning::CodeReference.new(
      path: "../config/credentials.yml.enc",
      label: "forbidden",
      role: "must not be readable",
      start_line: 1,
      end_line: 1,
      anchor: "secret"
    )

    assert_raises(Learning::SourceReader::Error) { Learning::SourceReader.new(reference).read }
  end

  test "registered references avoid credentials and user content paths" do
    paths = Learning::TopicRegistry.all.flat_map { |topic| topic.code_references.map(&:path) }

    assert paths.none? { |path| path.match?(/credentials|storage|tmp|uploads/i) }
  end
end

require "test_helper"

# Keeps the public documentation linked, in English, and aligned with the
# concepts and evidence boundaries the application actually implements.
class HumanSystemDocsTest < ActiveSupport::TestCase
  DOCS = %w[README.md CAPABILITIES.md SYSTEM_GUIDE.md ARCHITECTURE.md OPERATIONS.md LEARNING.md SHOWCASE.md RELEASING.md CHANGELOG.md].freeze
  ROOT_DOCS = %w[README.md ROADMAP.md IMPLEMENTATION_MAP.md CONTRIBUTING.md SECURITY.md LICENSE].freeze

  test "the entry points link every core document" do
    DOCS.excluding("README.md").each { |name| assert_mentions "docs/README.md", name }
    assert_mentions "docs/README.md", "../ROADMAP.md", "../IMPLEMENTATION_MAP.md"
    assert_mentions "README.md", "docs/README.md", "docs/CAPABILITIES.md", "docs/SYSTEM_GUIDE.md",
      "docs/ARCHITECTURE.md", "docs/OPERATIONS.md", "ROADMAP.md", "LICENSE"
  end

  test "public documents are written in English" do
    (DOCS.map { |name| "docs/#{name}" } + ROOT_DOCS).each do |path|
      assert_no_match(/\p{Han}/, read(path), "#{path} contains Chinese text; public docs are English only")
    end
  end

  test "status labels and evidence kinds are defined" do
    assert_mentions "docs/README.md", *%w[IMPLEMENTED PARTIAL PLANNED DEPRECATED REMOVED].map { |label| "`#{label}`" }
    assert_mentions "docs/README.md", "current behavior, evidence", "**local**", "**live**"
  end

  test "capability matrix distinguishes registry gates from provider evidence" do
    assert_mentions "docs/CAPABILITIES.md",
      "RubyLLM 2.1.0",
      "explicitly declare `function_calling`",
      "registry metadata is only an admission hint",
      "no reliable Workbench model-level web-search capability gate",
      "No live provider Batch compatibility is claimed",
      "## Live dogfood record",
      "## RubyLLM workarounds",
      "## Verification snapshot"
  end

  test "system guide keeps goals, concepts and evidence boundaries visible" do
    assert_mentions "docs/SYSTEM_GUIDE.md",
      "## Goals", "## Non-goals", "## Capability map", "## Easy to misread",
      "## Implementation status and evidence", "LifecycleEvent", "Tool execution policy",
      "KnowledgeCollection", "parallel_tool_calls", "lexical", "EvaluationCaseReview", "production deployment"
  end

  test "architecture keeps the system diagrams and current boundary visible" do
    assert_operator read("docs/ARCHITECTURE.md").scan("```mermaid").length, :>=, 8
    assert_mentions "docs/ARCHITECTURE.md",
      "ToolInvocation", "LIFECYCLE_EVENT", "waiting_for_approval", "KnowledgeChunk", "KNOWLEDGE_EMBEDDING",
      "ChatResponseJob", "LifecycleEventRecorder", "ToolExecutionPolicy", "Knowledge::Retriever",
      "AgentLeaseHeartbeat", "RubyLlmInternals", "event_key deduplication", "APP PATH IMPLEMENTED"
  end

  test "operations covers setup, verification, live dogfood and troubleshooting" do
    assert_mentions "docs/OPERATIONS.md",
      "## Verification", "## Live provider dogfood", "## Upgrading RubyLLM", "## Observability boundaries",
      "## Tool Lab execution mode", "## Knowledge workspace", "PARALLEL_WORKERS=1",
      "bin/rails workbench:demo", "bin/dogfood"
  end

  test "learning layer documents its source-anchored contract" do
    assert_mentions "docs/LEARNING.md", "How this works", "SourceReader", "credentials"
  end

  test "development web and asset servers bind only to loopback" do
    vite_ruby_config = JSON.parse(read("config/vite.json"))

    assert_match(/^web: bin\/rails s -b 127\.0\.0\.1$/, read("Procfile.dev"))
    assert_match(/^vite: bin\/vite dev$/, read("Procfile.dev"))
    assert_match(/server:\s*\{\s*host: ['"]127\.0\.0\.1['"]/, read("vite.config.ts"))
    assert_equal "127.0.0.1", vite_ruby_config.dig("development", "host")
  end

  private

  def read(path)
    File.read(Rails.root.join(path))
  end

  # Reports the missing phrase instead of dumping the whole document.
  def assert_mentions(path, *phrases)
    text = read(path)
    phrases.each { |phrase| assert text.include?(phrase), "#{path} should mention #{phrase.inspect}" }
  end
end

require "test_helper"

class HumanSystemDocsTest < ActiveSupport::TestCase
  DOCS = %w[README.md CAPABILITIES.md SYSTEM_GUIDE.md ARCHITECTURE.md OPERATIONS.md LEARNING.md CHANGELOG.md].freeze

  test "human documentation entrypoint and core documents remain linked" do
    docs_root = Rails.root.join("docs")
    sources = DOCS.to_h { |name| [ name, File.read(docs_root.join(name)) ] }

    assert_includes sources.fetch("README.md"), "SYSTEM_GUIDE.md"
    assert_includes sources.fetch("README.md"), "CAPABILITIES.md"
    assert_includes sources.fetch("README.md"), "ARCHITECTURE.md"
    assert_includes sources.fetch("README.md"), "OPERATIONS.md"
    assert_includes sources.fetch("README.md"), "LEARNING.md"
    assert_includes sources.fetch("README.md"), "CHANGELOG.md"
    assert_includes File.read(Rails.root.join("README.md")), "docs/README.md"
    assert_includes File.read(Rails.root.join("README.md")), "docs/CAPABILITIES.md"
    assert_includes File.read(Rails.root.join("README.md")), "TODO.md"
    assert_includes sources.fetch("README.md"), "current behavior, evidence"
    assert_includes sources.fetch("README.md"), "`IMPLEMENTED`"
    assert_includes sources.fetch("README.md"), "`PARTIAL`"
    assert_includes sources.fetch("README.md"), "`PLANNED`"
    assert_includes sources.fetch("README.md"), "`DEPRECATED`"
    assert_includes sources.fetch("README.md"), "`REMOVED`"
    assert_includes sources.fetch("CHANGELOG.md"), "公开仓库"
    assert_includes sources.fetch("CHANGELOG.md"), "M8 RubyLLM 能力矩阵"
    assert_includes sources.fetch("OPERATIONS.md"), "当前可观测性边界"
    assert_includes sources.fetch("SYSTEM_GUIDE.md"), "LifecycleEvent"
    assert_includes sources.fetch("SYSTEM_GUIDE.md"), "Tool execution policy"
    assert_includes sources.fetch("SYSTEM_GUIDE.md"), "KnowledgeCollection"
    assert_includes sources.fetch("ARCHITECTURE.md"), "LifecycleEventRecorder"
    assert_includes sources.fetch("ARCHITECTURE.md"), "ToolExecutionPolicy"
    assert_includes sources.fetch("ARCHITECTURE.md"), "Knowledge::Retriever"
    assert_includes sources.fetch("ARCHITECTURE.md"), "APP PATH IMPLEMENTED"
    assert_includes sources.fetch("OPERATIONS.md"), "PARALLEL_WORKERS=1"
    assert_includes sources.fetch("OPERATIONS.md"), "Tool Lab 执行模式"
    assert_includes sources.fetch("OPERATIONS.md"), "Knowledge workspace"
    assert_includes sources.fetch("LEARNING.md"), "How this works"
    assert_includes sources.fetch("LEARNING.md"), "SourceReader"
    assert_includes sources.fetch("LEARNING.md"), "credentials"
    assert_includes sources.fetch("CHANGELOG.md"), "多调用审计"
    assert_includes sources.fetch("CHANGELOG.md"), "M4 本地文本 Knowledge 基础切片"
  end

  test "capability matrix distinguishes registry gates from provider evidence" do
    matrix = File.read(Rails.root.join("docs/CAPABILITIES.md"))

    assert_includes matrix, "RubyLLM 2.0.0"
    assert_includes matrix, "explicitly declare `function_calling`"
    assert_includes matrix, "Registry metadata is only an admission hint"
    assert_includes matrix, "no reliable Workbench model-level web-search capability gate"
    assert_includes matrix, "predates the stable 2.0.0 pin"
    assert_includes matrix, "No live provider Batch compatibility is claimed"
  end

  test "architecture keeps the system diagrams and current boundary visible" do
    architecture = File.read(Rails.root.join("docs/ARCHITECTURE.md"))

    assert_operator architecture.scan("```mermaid").length, :>=, 4
    assert_includes architecture, "ToolInvocation"
    assert_includes architecture, "LIFECYCLE_EVENT"
    assert_includes architecture, "event_key 去重"
    assert_includes architecture, "waiting_for_approval"
    assert_includes architecture, "M4 Knowledge"
    assert_includes architecture, "EvaluationCaseReview"
    assert_includes architecture, "reviewer label"
    assert_includes architecture, "KnowledgeChunk"
    assert_includes architecture, "KnowledgeEmbedding"
    assert_includes architecture, "char offsets"
    assert_includes architecture, "ChatResponseJob"
    assert_includes architecture, "Run #13"
    assert_includes architecture, "`IMPLEMENTED`"
    assert_includes architecture, "`PARTIAL`"
    assert_includes architecture, "`PLANNED`"
  end

  test "development web and asset servers bind only to loopback" do
    procfile = File.read(Rails.root.join("Procfile.dev"))
    vite_config = File.read(Rails.root.join("vite.config.ts"))
    vite_ruby_config = JSON.parse(File.read(Rails.root.join("config/vite.json")))

    assert_match(/^web: bin\/rails s -b 127\.0\.0\.1$/, procfile)
    assert_match(/^vite: bin\/vite dev$/, procfile)
    assert_match(/server:\s*\{\s*host: ['"]127\.0\.0\.1['"]/, vite_config)
    assert_equal "127.0.0.1", vite_ruby_config.dig("development", "host")
  end

  test "system guide keeps goals and evidence boundaries visible" do
    guide = File.read(Rails.root.join("docs/SYSTEM_GUIDE.md"))

    assert_includes guide, "## 产品目标"
    assert_includes guide, "## 当前能力地图"
    assert_includes guide, "## 最容易误读的地方"
    assert_includes guide, "不等于生产部署"
    assert_includes guide, "Run #13"
    assert_includes guide, "## 实现状态与证据"
    assert_includes guide, "LifecycleEvent"
    assert_includes guide, "parallel_tool_calls"
    assert_includes guide, "lexical/semantic/hybrid"
    assert_includes guide, "EvaluationCaseReview"
    assert_includes guide, "`IMPLEMENTED`"
    assert_includes guide, "`PARTIAL`"
    assert_includes guide, "`PLANNED`"
  end
end

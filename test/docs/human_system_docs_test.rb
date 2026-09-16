require "test_helper"

class HumanSystemDocsTest < ActiveSupport::TestCase
  DOCS = %w[README.md SYSTEM_GUIDE.md ARCHITECTURE.md OPERATIONS.md CHANGELOG.md].freeze

  test "human documentation entrypoint and core documents remain linked" do
    docs_root = Rails.root.join("docs")
    sources = DOCS.to_h { |name| [ name, File.read(docs_root.join(name)) ] }

    assert_includes sources.fetch("README.md"), "SYSTEM_GUIDE.md"
    assert_includes sources.fetch("README.md"), "ARCHITECTURE.md"
    assert_includes sources.fetch("README.md"), "OPERATIONS.md"
    assert_includes sources.fetch("README.md"), "CHANGELOG.md"
    assert_includes File.read(Rails.root.join("README.md")), "docs/README.md"
    assert_includes File.read(Rails.root.join("README.md")), "rubyllm-workbench/ai/00_ENTRYPOINT.md"
    assert_includes sources.fetch("README.md"), "Specs 基线"
    assert_includes sources.fetch("README.md"), "当前实现层"
    assert_includes sources.fetch("README.md"), "`IMPLEMENTED`"
    assert_includes sources.fetch("README.md"), "`PARTIAL`"
    assert_includes sources.fetch("README.md"), "`PLANNED`"
    assert_includes sources.fetch("README.md"), "`DEPRECATED`"
    assert_includes sources.fetch("README.md"), "`REMOVED`"
    assert_includes sources.fetch("CHANGELOG.md"), "双层体系"
    assert_includes sources.fetch("OPERATIONS.md"), "当前可观测性边界"
    assert_includes sources.fetch("SYSTEM_GUIDE.md"), "LifecycleEvent"
    assert_includes sources.fetch("SYSTEM_GUIDE.md"), "Tool execution policy"
    assert_includes sources.fetch("ARCHITECTURE.md"), "LifecycleEventRecorder"
    assert_includes sources.fetch("ARCHITECTURE.md"), "ToolExecutionPolicy"
    assert_includes sources.fetch("ARCHITECTURE.md"), "APP PATH IMPLEMENTED"
    assert_includes sources.fetch("OPERATIONS.md"), "PARALLEL_WORKERS=1"
    assert_includes sources.fetch("OPERATIONS.md"), "Tool Lab 执行模式"
    assert_includes sources.fetch("CHANGELOG.md"), "多调用审计"
  end

  test "architecture keeps the system diagrams and current boundary visible" do
    architecture = File.read(Rails.root.join("docs/ARCHITECTURE.md"))

    assert_operator architecture.scan("```mermaid").length, :>=, 4
    assert_includes architecture, "ToolInvocation"
    assert_includes architecture, "LIFECYCLE_EVENT"
    assert_includes architecture, "event_key 去重"
    assert_includes architecture, "waiting_for_approval"
    assert_includes architecture, "M4 Knowledge + RAG"
    assert_includes architecture, "ChatResponseJob"
    assert_includes architecture, "Run #13"
    assert_includes architecture, "`IMPLEMENTED`"
    assert_includes architecture, "`PARTIAL`"
    assert_includes architecture, "`PLANNED`"
  end

  test "system guide keeps goals and evidence boundaries visible" do
    guide = File.read(Rails.root.join("docs/SYSTEM_GUIDE.md"))

    assert_includes guide, "## 产品目标"
    assert_includes guide, "## 当前能力地图"
    assert_includes guide, "## 最容易误读的地方"
    assert_includes guide, "不等于生产部署"
    assert_includes guide, "Run #13"
    assert_includes guide, "Specs 基线"
    assert_includes guide, "当前现实层"
    assert_includes guide, "LifecycleEvent"
    assert_includes guide, "parallel_tool_calls"
    assert_includes guide, "`IMPLEMENTED`"
    assert_includes guide, "`PARTIAL`"
    assert_includes guide, "`PLANNED`"
  end
end

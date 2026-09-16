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
  end

  test "architecture keeps the system diagrams and current boundary visible" do
    architecture = File.read(Rails.root.join("docs/ARCHITECTURE.md"))

    assert_operator architecture.scan("```mermaid").length, :>=, 4
    assert_includes architecture, "ToolInvocation"
    assert_includes architecture, "waiting_for_approval"
    assert_includes architecture, "M4 Knowledge + RAG"
  end

  test "system guide keeps goals and evidence boundaries visible" do
    guide = File.read(Rails.root.join("docs/SYSTEM_GUIDE.md"))

    assert_includes guide, "## 产品目标"
    assert_includes guide, "## 当前能力地图"
    assert_includes guide, "## 最容易误读的地方"
    assert_includes guide, "不等于生产部署"
    assert_includes guide, "Run #13"
  end
end

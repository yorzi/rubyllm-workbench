require "test_helper"

class RubyLlmUsageLedgerTest < ActiveSupport::TestCase
  test "the 2.1 schema stores one-shot usage with an owner and no chat" do
    project = create_project(name: "Usage owner")
    usage = RubyLLM::ActiveRecord::Usage.create!(
      operation: "video", status: "succeeded", provider: "openrouter", model: "synthetic-video",
      owner: project, total_cost: 0.02, server_tool_use: { "web_search_requests" => 1 }
    )

    assert_nil usage.reload.chat
    assert_equal project, usage.owner
    assert_equal BigDecimal("0.02"), usage.cost.total
    assert_equal({ "web_search_requests" => 1 }, usage.tokens.server_tool_use)
  end
end

require "test_helper"

class Ai::ProviderToolActivityTest < ActiveSupport::TestCase
  Response = Struct.new(:tokens, :server_tool_calls)

  test "reads usage-only provider tool counters such as OpenRouter web search" do
    tokens = RubyLLM::Tokens.new(
      input: 10, output: 5,
      server_tool_use: { "web_search_requests" => 4, "tool_calls_executed" => 1, "zero" => 0, "junk" => "x" }
    )
    response = Response.new(tokens, [])

    assert_equal [], Ai::ProviderToolActivity.calls(response)
    assert_equal({ "web_search_requests" => 4, "tool_calls_executed" => 1 }, Ai::ProviderToolActivity.usage(response))
  end

  test "returns no usage when the provider reports no counters" do
    assert_equal({}, Ai::ProviderToolActivity.usage(Response.new(RubyLLM::Tokens.new(input: 1), [])))
    assert_equal({}, Ai::ProviderToolActivity.usage(Object.new))
  end

  test "records discrete server tool calls with sanitized input" do
    response = Response.new(nil, [ { type: "web_search_call", name: "web_search", id: "ws_1", input: { "query" => "rubyllm" } } ])

    assert_equal [ { "type" => "web_search_call", "name" => "web_search", "id" => "ws_1", "input" => { "query" => "rubyllm" } } ],
      Ai::ProviderToolActivity.calls(response)
  end

  test "sums counters across Agent steps" do
    merged = Ai::ProviderToolActivity.merge_usage({ "web_search_requests" => 1 }, { "web_search_requests" => 2, "web_fetch_requests" => 1 })

    assert_equal({ "web_search_requests" => 3, "web_fetch_requests" => 1 }, merged)
    assert_equal({ "web_search_requests" => 2 }, Ai::ProviderToolActivity.merge_usage(nil, { "web_search_requests" => 2 }))
  end
end

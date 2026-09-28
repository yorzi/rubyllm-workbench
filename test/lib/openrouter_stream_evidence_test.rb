require "test_helper"

class OpenRouterStreamEvidenceTest < ActiveSupport::TestCase
  ANNOTATION_EVENT = {
    "model" => "openai/gpt-5-nano",
    "choices" => [ { "delta" => { "content" => "Source", "annotations" => [
      { "type" => "url_citation", "url_citation" => { "url" => "https://rubygems.org/gems/ruby_llm", "title" => "ruby_llm" } }
    ] } } ]
  }.freeze
  USAGE_EVENT = {
    "model" => "openai/gpt-5-nano",
    "choices" => [ { "delta" => {}, "finish_reason" => "stop" } ],
    "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5, "server_tool_use_details" => { "web_search_requests" => 2 } }
  }.freeze

  setup do
    @protocol = RubyLLM::Providers::OpenRouter::ChatCompletions.allocate
  end

  test "streamed OpenRouter chunks keep citations and server tool usage" do
    assert RubyLLMWorkarounds::OpenRouterStreamEvidence.installed?

    citation_chunk = @protocol.send(:build_chunk, ANNOTATION_EVENT)
    usage_chunk = @protocol.send(:build_chunk, USAGE_EVENT)

    assert_equal [ "https://rubygems.org/gems/ruby_llm" ], citation_chunk.citations.map(&:url)
    assert_equal "Source", citation_chunk.content
    assert_equal({ "web_search_requests" => 2 }, usage_chunk.tokens.server_tool_use)
    assert_equal 10, usage_chunk.tokens.input
    assert_equal :stop, usage_chunk.finish_reason
  end

  test "chunks without evidence are unchanged" do
    chunk = @protocol.send(:build_chunk, { "choices" => [ { "delta" => { "content" => "plain" } } ] })

    assert_empty chunk.citations
    assert_nil chunk.tokens.server_tool_use
  end

  # When this fails, RubyLLM's OpenRouter stream parser maps citations itself:
  # delete lib/ruby_llm_workarounds/openrouter_stream_evidence.rb, its require
  # in config/initializers/ruby_llm.rb, and this test.
  test "upstream RubyLLM still drops streamed OpenRouter citations" do
    file, line = RubyLLM::Providers::OpenRouter::Streaming.instance_method(:build_chunk).source_location
    upstream_source = File.readlines(file)[(line - 1)..].take_while { |source_line| !source_line.match?(/^        end$/) }.join

    refute_match(/citations:|server_tool_use:/, upstream_source,
      "RubyLLM #{RubyLLM::VERSION} now maps OpenRouter stream evidence; remove the workaround")
  end
end

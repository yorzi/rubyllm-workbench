# Run with: bundle exec ruby script/diagnostics/ruby_llm_openrouter_stream_citations.rb
# No Rails, credentials, network, database, or Workbench workaround is loaded.
#
# OpenRouter streams hosted web-search evidence as a `url_citation` annotation
# in a delta and as `server_tool_use_details` in the final usage chunk. The
# generic Chat Completions stream parser maps both; OpenRouter's override of
# `build_chunk` drops them, so streamed OpenRouter responses have no citations
# and no server tool usage even when the provider searched.
require "ruby_llm"

annotation_event = {
  "model" => "openai/gpt-5-nano",
  "choices" => [ { "delta" => { "content" => "", "annotations" => [
    { "type" => "url_citation", "url_citation" => { "url" => "https://rubygems.org/gems/ruby_llm", "title" => "ruby_llm", "start_index" => 0, "end_index" => 10 } }
  ] } } ]
}
usage_event = {
  "model" => "openai/gpt-5-nano",
  "choices" => [ { "delta" => {}, "finish_reason" => "stop" } ],
  "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5, "server_tool_use_details" => { "web_search_requests" => 1 } }
}

puts "RubyLLM #{Gem.loaded_specs.fetch('ruby_llm').version}"
config = RubyLLM::Configuration.new
# Placeholder keys only satisfy provider construction; nothing is sent.
config.openai_api_key = "unused"
config.openrouter_api_key = "unused"
generic = RubyLLM::Protocols::ChatCompletions.new(RubyLLM::Providers::OpenAI.new(config))
openrouter = RubyLLM::Providers::OpenRouter::ChatCompletions.new(RubyLLM::Providers::OpenRouter.new(config))

{ "generic chat completions" => generic, "openrouter" => openrouter }.each do |label, protocol|
  citations = protocol.send(:build_chunk, annotation_event).citations
  usage = protocol.send(:build_chunk, usage_event).tokens&.server_tool_use
  puts "#{label}: citations=#{Array(citations).size} server_tool_use=#{usage.inspect}"
end

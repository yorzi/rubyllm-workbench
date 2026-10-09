#!/usr/bin/env ruby
# Offline public-API reproduction. No Rails database or credentials are loaded.
require "bundler/setup"
require "ruby_llm"
require "webmock"
require "json"

WebMock.enable!
WebMock.disable_net_connect!
RubyLLM.configure do |config|
  config.openrouter_api_key = "offline-placeholder"
  config.max_retries = 0
end

model = "liquid/lfm-2.5-2.6b:free"
WebMock.stub_request(:post, "https://openrouter.ai/api/v1/chat/completions")
  .to_return(status: 200, headers: { "content-type" => "application/json" }, body: JSON.generate(
    id: "offline-missing-usage", model:,
    choices: [ { index: 0, message: { role: "assistant", content: "ok" }, finish_reason: "stop" } ]
  ))

message = RubyLLM.chat(model:, provider: :openrouter).ask("Return ok.")
puts JSON.pretty_generate(
  ruby_llm_version: Gem.loaded_specs.fetch("ruby_llm").version.to_s,
  provider: "openrouter", model:, stubbed_http_requests: 1, real_network_requests: 0, fixture_contains_usage: false,
  tokens: message.tokens.to_h, reported_cost: message.tokens.reported_cost,
  cost: message.cost.to_h,
  observation: "The fixture reports no usage; a default cache_write_tokens=0 can produce total=0 while input/output remain unknown. This has not been checked against upstream main."
)

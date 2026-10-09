# Run: bundle exec ruby script/diagnostics/ruby_llm_openrouter_thinking_disable.rb
# Public API payload probe only: no Rails, network, database or real key.
require "ruby_llm"
require "json"

RubyLLM.models.load_from_json
context = RubyLLM.context do |config|
  config.openrouter_api_key = "unused-offline-placeholder"
end
chat = context.chat(model: "nvidia/nemotron-3-super-120b-a12b:free", provider: :openrouter, protocol: :chat_completions)

enabled = chat.with_thinking.render
disabled = chat.with_thinking(false).render
explicit = chat.with_provider_options(reasoning: { enabled: false }).render

abort "Explicit thinking disable is missing from the rendered payload." unless disabled.dig(:reasoning, :enabled) == false

puts JSON.pretty_generate(
  ruby_llm: RubyLLM::VERSION,
  model: chat.model.id,
  protocol: "chat_completions",
  enabled_reasoning: enabled[:reasoning],
  disabled_reasoning: disabled[:reasoning],
  explicit_provider_option_reasoning: explicit[:reasoning],
  network_requests: 0
)

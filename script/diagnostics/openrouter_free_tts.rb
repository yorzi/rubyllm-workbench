# Run: RUN_LIVE_AI=1 AI_TEST_PROFILE=free RAILS_ENV=test bundle exec ruby script/diagnostics/openrouter_free_tts.rb
# Uses Rails' existing credential boundary; never pass a key in command args.
# This raw REST call does not use RubyLLM's speech adapter.
abort "Explicit RUN_LIVE_AI=1 and AI_TEST_PROFILE=free are required." unless ENV["RUN_LIVE_AI"] == "1" && ENV["AI_TEST_PROFILE"] == "free"
abort "Paid acceptance is excluded from this free probe." if ENV["LIVE_DOGFOOD_PAID"] == "1"

require_relative "../../config/environment"
require_relative "support/openrouter_speech_probe"

directory = Rails.root.join("tmp/dogfood")
directory.mkpath
basename = "#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}-raw-tts"
report_path = directory.join("#{basename}.json")
audio_path = directory.join("#{basename}.mp3")
model = ENV.fetch("DOGFOOD_SPEECH_MODEL", OpenRouterSpeechProbe::DEFAULT_MODEL)
probe = OpenRouterSpeechProbe.new(api_key: RubyLLM.config.openrouter_api_key, model:, voice: ENV["DOGFOOD_SPEECH_VOICE"])
evidence = {
  scenario: "openrouter_raw_free_speech", profile: "free", provider: "openrouter", model:,
  ruby_llm: Gem.loaded_specs.fetch("ruby_llm").version.to_s, adapter_used: false,
  input_characters: OpenRouterSpeechProbe::TEXT.length, retries: 0, paid_fallback: false,
  cost_usd: nil, cost_complete: false, at: Time.current.utc.iso8601
}

begin
  result = probe.call
  File.binwrite(audio_path, result.data)
  evidence.merge!(result.evidence, result: "pass", audio_file: audio_path.to_s)
rescue StandardError => error
  # Error bodies and exception messages can include provider-echoed inputs.
  # Keep only classes/status/request ID in the reusable evidence report.
  evidence.merge!(result: "fail", error_class: error.class.name, http_status: probe.http_status, generation_id: probe.generation_id)
  evidence[:reason] = error.message if error.is_a?(OpenRouterSpeechProbe::Refused) || error.is_a?(OpenRouterSpeechProbe::InvalidResponse)
ensure
  evidence[:http_post_requests] = probe.post_requests
  File.write(report_path, JSON.pretty_generate(evidence) + "\n")
  puts JSON.pretty_generate(evidence.merge(report_file: report_path.to_s))
end
exit(evidence[:result] == "pass" ? 0 : 1)

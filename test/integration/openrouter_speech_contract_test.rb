require "test_helper"
require_relative "../../script/diagnostics/support/openrouter_speech_probe"

# Public RubyLLM API over a stubbed HTTP boundary, not a speech-object double.
# This contract remains offline even when the machine has provider keys.
class OpenRouterSpeechContractTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @original_retries = RubyLLM.config.max_retries
    @original_base = RubyLLM.config.openrouter_api_base
    RubyLLM.config.max_retries = 0
    RubyLLM.config.openrouter_api_base = "https://openrouter.ai/api/v1"
    @model = OpenRouterSpeechProbe::DEFAULT_MODEL
    @audio = "ID3\x04synthetic-mp3".b
  end

  teardown do
    RubyLLM.config.max_retries = @original_retries
    RubyLLM.config.openrouter_api_base = @original_base
  end

  test "OpenRouter adapter sends independent speech payload and returns a RubyLLM Speech object" do
    request = WebMock.stub_request(:post, "https://openrouter.ai/api/v1/audio/speech")
      .with do |http|
        JSON.parse(http.body) == { "model" => @model, "input" => OpenRouterSpeechProbe::TEXT, "response_format" => "mp3" }
      end.to_return(status: 200, body: @audio, headers: { "Content-Type" => "audio/mpeg" })

    speech = with_provider_configuration(:openrouter) do
      RubyLLM.speak(OpenRouterSpeechProbe::TEXT, model: @model, provider: :openrouter)
    end

    assert_instance_of RubyLLM::Speech, speech
    assert_equal @model, speech.model
    assert_equal "mp3", speech.format
    assert_equal "audio/mpeg", speech.mime_type
    assert_nil speech.voice, "Fish must not inherit an invented OpenAI voice"
    assert_equal @audio, speech.to_blob
    assert_requested request, times: 1
  end

  test "real speech adapter response travels through controller job and ActiveStorage without another chat request" do
    request = WebMock.stub_request(:post, "https://openrouter.ai/api/v1/audio/speech")
      .to_return(status: 200, body: @audio, headers: { "Content-Type" => "audio/mpeg" })
    project = create_project(name: "Speech HTTP contract")
    chat = create_chat(project)
    message = chat.messages.create!(role: "assistant", content: OpenRouterSpeechProbe::TEXT)

    with_provider_configuration(:openrouter) do
      perform_enqueued_jobs(only: SpeechRunJob) do
        post project_chat_message_speech_run_path(project, chat, message),
          params: { speech_run: { model_reference: "openrouter|#{@model}" } }
      end
    end

    assert_response :see_other
    run = chat.runs.find_by!(operation: "speech")
    assert run.succeeded?, run.error_summary.to_s
    audio = run.artifacts.find_by!(kind: "audio").audio_file
    assert audio.attached?
    assert_equal @audio, audio.download
    assert_equal "audio/mpeg", audio.content_type
    assert_equal "unknown", run.attempts.first.cost_status, "a free catalog entry cannot fabricate provider-reported usage/cost"
    get run_path(run)
    assert_response :success
    assert_select "audio[controls]"
    assert_select "a", text: "Download"
    assert_requested request, times: 1
  end
end

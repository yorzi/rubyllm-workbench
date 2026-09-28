require "test_helper"

class Ai::SpeechRunExecutorTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @project = create_project(name: "Speech Run executor project")
    @chat = create_chat(@project)
    @message = @chat.messages.create!(role: "assistant", content: "A saved reply for speech.")
    @original_models = RubyLLM.models.all_including_unlisted.dup
    @speech_model = test_speech_model
    RubyLLM.models.instance_variable_set(:@models, @original_models + [ @speech_model ])
  end

  teardown do
    RubyLLM.models.instance_variable_set(:@models, @original_models) if @original_models
  end

  test "queues a speech Run with a frozen source reply and provider/model Attempt" do
    assert @speech_model, "the bundled RubyLLM registry should include a speech-capable model"

    run = nil
    with_provider_configuration(@speech_model.provider) do
      assert_enqueued_with(job: SpeechRunJob) do
        run = Ai::SpeechRunExecutor.enqueue(
          message: @message,
          model_reference: "#{@speech_model.provider}|#{@speech_model.id}"
        )
      end
    end

    assert_equal "speech", run.operation
    assert run.queued?
    assert_equal @message.id, run.input_snapshot.fetch("source_message_id")
    assert_equal @message.content, run.input_snapshot.dig("speech", "text")
    assert_equal @speech_model.provider, run.input_snapshot.dig("speech", "provider")
    assert_equal @speech_model.id, run.input_snapshot.dig("speech", "model_id")
    assert_equal [ [ @speech_model.provider, @speech_model.id, "queued" ] ],
      run.attempts.pluck(:provider, :model_id, :status)
  end

  test "rejects chat models before creating a Run" do
    unsupported_model = chat_model
    assert unsupported_model, "the bundled registry should include a model without speech-generation support"

    assert_raises(ArgumentError) do
      Ai::SpeechRunExecutor.enqueue(
        message: @message,
        model_reference: "#{unsupported_model.provider}|#{unsupported_model.id}"
      )
    end

    assert_equal 0, @chat.runs.count
  end

  test "rejects user messages before creating a Run" do
    user_message = @chat.messages.create!(role: "user", content: "Do not read this.")

    assert_raises(ArgumentError) do
      Ai::SpeechRunExecutor.enqueue(
        message: user_message,
        model_reference: "openai|gpt-4o-mini-tts"
      )
    end

    assert_equal 0, @chat.runs.count
  end

  private

  def test_speech_model
    RubyLLM::Model.new(
      id: "test-speech-model",
      name: "Test Speech Model",
      provider: "openai",
      capabilities: [ "speech_generation" ],
      modalities: { input: [ "text" ], output: [ "audio" ] },
      pricing: {}
    )
  end
end

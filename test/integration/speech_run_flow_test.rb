require "test_helper"

class SpeechRunFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  RejectedEnqueue = Struct.new(:enqueue_error) do
    def successfully_enqueued?
      false
    end
  end

  SpeechResponse = Struct.new(:data, :model, :voice, :format, :mime_type, :tokens, :cost) do
    def to_blob
      data
    end
  end

  setup do
    @project = create_project(name: "Speech Run project")
    @chat = create_chat(@project)
    @message = @chat.messages.create!(role: "assistant", content: "This saved reply becomes speech.")
    @original_models = RubyLLM.models.all_including_unlisted.dup
    @speech_model = test_speech_model
    RubyLLM.models.instance_variable_set(:@models, @original_models + [ @speech_model ])
  end

  teardown do
    RubyLLM.models.instance_variable_set(:@models, @original_models) if @original_models
  end

  test "assistant reply queues speech and the Run inspector plays and downloads its audio Artifact" do
    assert @speech_model, "the bundled RubyLLM registry should include a speech-capable model"
    get project_chat_path(@project, @chat)
    assert_response :success
    assert_select "a[href=?]", new_project_chat_message_speech_run_path(@project, @chat, @message), text: "Generate audio Artifact"

    run = nil
    with_provider_configuration(@speech_model.provider) do
      assert_enqueued_with(job: SpeechRunJob) do
        post project_chat_message_speech_run_path(@project, @chat, @message),
          params: { speech_run: { model_reference: "#{@speech_model.provider}|#{@speech_model.id}" } }
        run = @chat.runs.order(:id).last
      end
    end

    assert_response :see_other
    assert run.queued?
    assert_equal "speech", run.operation

    fake_response = SpeechResponse.new(
      "fake-mp3-data".b,
      @speech_model.id,
      "alloy",
      "mp3",
      "audio/mpeg",
      RubyLLM::Tokens.new(input: 12, output: 24),
      nil
    )
    calls = []
    speaker = ->(text, **options) { calls << [ text, options ]; fake_response }

    with_provider_configuration(@speech_model.provider) do
      with_speech_client(speaker) do
        SpeechRunJob.perform_now(run.id)
        SpeechRunJob.perform_now(run.id)
      end
    end

    run.reload
    assert run.succeeded?
    assert_equal 1, calls.length
    assert_equal [ "This saved reply becomes speech.", @speech_model.id, @speech_model.provider.to_sym ],
      [ calls.first.first, calls.first.last.fetch(:model), calls.first.last.fetch(:provider) ]
    assert_equal 1, run.artifacts.where(kind: "audio").count
    attempt = run.attempts.first
    assert attempt.succeeded?
    assert_equal 12, attempt.input_tokens
    assert_equal 24, attempt.output_tokens
    assert_includes %w[unknown estimated reported], attempt.cost_status

    artifact = run.artifacts.find_by!(kind: "audio")
    assert artifact.audio_file.attached?
    assert_equal "audio/mpeg", artifact.audio_file.blob.content_type
    assert_equal Digest::SHA256.hexdigest("fake-mp3-data"), artifact.metadata_json.fetch("sha256")
    assert_equal @message.id, artifact.metadata_json.fetch("source_message_id")

    get run_path(run)
    assert_response :success
    assert_select "audio[controls]"
    assert_select "a", text: "Download"
    assert_select "#lifecycle-events-heading"
  end

  test "an explicit voice is frozen in the Run and sent to the provider" do
    with_provider_configuration(@speech_model.provider) do
      post project_chat_message_speech_run_path(@project, @chat, @message),
        params: { speech_run: { model_reference: "#{@speech_model.provider}|#{@speech_model.id}", voice: " aura-2-thalia-en " } }
    end
    run = @chat.runs.order(:id).last
    assert_equal "aura-2-thalia-en", run.input_snapshot.dig("speech", "voice")

    fake_response = SpeechResponse.new("fake-mp3-data".b, @speech_model.id, "aura-2-thalia-en", "mp3", "audio/mpeg", RubyLLM::Tokens.new(input: 1, output: 1), nil)
    calls = []
    speaker = ->(text, **options) { calls << options; fake_response }
    with_provider_configuration(@speech_model.provider) do
      with_speech_client(speaker) { SpeechRunJob.perform_now(run.id) }
    end

    assert run.reload.succeeded?
    assert_equal "aura-2-thalia-en", calls.first.fetch(:voice)
  end

  test "an invalid voice identifier re-renders the form without creating a Run" do
    with_provider_configuration(@speech_model.provider) do
      assert_no_difference -> { @chat.runs.count } do
        post project_chat_message_speech_run_path(@project, @chat, @message),
          params: { speech_run: { model_reference: "#{@speech_model.provider}|#{@speech_model.id}", voice: "bad voice; rm -rf" } }
      end
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "Voice must be a provider voice identifier"
  end

  test "provider failure remains visible on the Run and Attempt" do
    run = with_provider_configuration(@speech_model.provider) do
      Ai::SpeechRunExecutor.enqueue(
        message: @message,
        model_reference: "#{@speech_model.provider}|#{@speech_model.id}"
      )
    end

    with_provider_configuration(@speech_model.provider) do
      with_speech_client(->(*) { raise RubyLLM::Error, "synthetic provider failure" }) do
        SpeechRunJob.perform_now(run.id)
      end
    end

    assert run.reload.failed?
    assert run.error_summary.include?("synthetic provider failure")
    assert run.attempts.first.failed?
    assert_equal 0, run.artifacts.where(kind: "audio").count
  end

  test "rejected speech enqueue fails the Run and Attempt before provider work" do
    fake_job = RejectedEnqueue.new(IOError.new("queue unavailable"))

    raised = with_rejected_speech_enqueue(fake_job) do
      with_provider_configuration(@speech_model.provider) do
        assert_raises(ArgumentError) do
          Ai::SpeechRunExecutor.enqueue(
            message: @message,
            model_reference: "#{@speech_model.provider}|#{@speech_model.id}"
          )
        end
      end
    end

    assert_includes raised.message, "queue unavailable"
    run = @chat.runs.where(operation: "speech").order(:id).last
    assert run.failed?
    attempt = run.attempts.first
    assert attempt.failed?
    assert_equal attempt.error_code, run.result_summary.fetch("failure_kind")
    assert_includes attempt.error_message, "queue unavailable"
    assert_empty run.artifacts
  end

  test "cancellation during speech generation prevents a late Artifact and successful Attempt" do
    run = with_provider_configuration(@speech_model.provider) do
      Ai::SpeechRunExecutor.enqueue(
        message: @message,
        model_reference: "#{@speech_model.provider}|#{@speech_model.id}"
      )
    end
    fake_response = SpeechResponse.new(
      "late-audio".b,
      @speech_model.id,
      "alloy",
      "mp3",
      "audio/mpeg",
      RubyLLM::Tokens.new(input: 12, output: 24),
      nil
    )
    speaker = lambda do |_text, **_options|
      run.cancel!
      fake_response
    end

    with_provider_configuration(@speech_model.provider) do
      with_speech_client(speaker) { SpeechRunJob.perform_now(run.id) }
    end

    assert run.reload.cancelled?
    assert run.attempts.first.cancelled?
    assert_equal 0, run.artifacts.where(kind: "audio").count
  end

  test "maps RubyLLM speech instrumentation to the Run and Attempt" do
    run = @chat.runs.create!(
      project: @project,
      operation: "speech",
      status: :running,
      requested_by: "test",
      input_snapshot_json: { "speech" => { "text" => "hello" } }
    )
    attempt = run.attempts.create!(
      sequence: 1,
      provider: @speech_model.provider,
      model_id: @speech_model.id,
      status: :running
    )
    tokens = RubyLLM::Tokens.new(input: 10, output: 20)
    cost = Struct.new(:total_cost).new(0.012)

    Ai::ExecutionContext.with(run_id: run.id, attempt_id: attempt.id) do
      ActiveSupport::Notifications.instrument(
        "speech.ruby_llm",
        provider: @speech_model.provider,
        model: @speech_model.id,
        tokens: tokens,
        cost: cost,
        audio_bytes: 4096
      )
    end

    event = LifecycleEvent.find_by!(name: "ai.provider.speech", run_id: run.id)
    assert_equal attempt.id, event.attempt_id
    assert_equal "speech", event.payload["operation"]
    assert_equal 4096, event.payload["audio_bytes"]
    assert_equal 10, event.payload["input_tokens"]
    assert_equal 20, event.payload["output_tokens"]
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

  def with_speech_client(client)
    original_speak = RubyLLM.method(:speak)
    RubyLLM.define_singleton_method(:speak, client)
    yield
  ensure
    RubyLLM.define_singleton_method(:speak, original_speak)
  end

  def with_rejected_speech_enqueue(fake_job)
    original = SpeechRunJob.method(:perform_later)
    SpeechRunJob.define_singleton_method(:perform_later) { |*_arguments| fake_job }
    yield
  ensure
    SpeechRunJob.define_singleton_method(:perform_later, original) if original
  end
end

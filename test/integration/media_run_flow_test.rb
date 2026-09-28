require "test_helper"

class MediaRunFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  RejectedEnqueue = Struct.new(:enqueue_error) do
    def successfully_enqueued?
      false
    end
  end

  MediaResponse = Struct.new(:data, :model, :mime_type, :tokens, :cost, :duration) do
    def to_blob
      data
    end
  end

  TranscriptionResponse = Struct.new(:text, :language, :duration, :model, :tokens, :cost)

  setup do
    @project = create_project(name: "Media Run project")
    @chat = create_chat(@project)
    @original_models = RubyLLM.models.all_including_unlisted.dup
    @image_model = test_model("image", capabilities: [ "image_generation" ], output: "image")
    @transcription_model = test_model("transcription", capabilities: [ "transcription" ], input: "audio")
    @video_model = test_model("video", output: "video")
    RubyLLM.models.instance_variable_set(
      :@models,
      @original_models + [ @image_model, @transcription_model, @video_model ]
    )
  end

  teardown do
    RubyLLM.models.instance_variable_set(:@models, @original_models) if @original_models
  end

  test "image request queues a Run and stores generated image with provider usage" do
    assert @image_model
    get new_project_chat_image_run_path(@project, @chat)
    assert_response :success
    assert_select "form[action=?]", project_chat_image_runs_path(@project, @chat)

    run = nil
    with_provider_configuration(@image_model.provider) do
      assert_enqueued_with(job: ImageRunJob) do
        post project_chat_image_runs_path(@project, @chat), params: {
          image_run: {
            prompt: "A tiny paper boat on a blue lake",
            model_reference: model_reference(@image_model)
          }
        }
        run = @chat.runs.order(:id).last
      end
    end

    assert_response :see_other
    assert run.queued?
    assert_equal "A tiny paper boat on a blue lake", run.input_snapshot.dig("image", "prompt")
    assert_equal [ @image_model.provider, @image_model.id, "queued" ],
      run.attempts.first.slice(:provider, :model_id, :status).values

    response = MediaResponse.new(
      "fake-png-data".b,
      @image_model.id,
      "image/png",
      RubyLLM::Tokens.new(input: 12, output: 0),
      nil,
      nil
    )
    calls = []
    painter = ->(prompt, **options) { calls << [ prompt, options ]; response }

    with_provider_configuration(@image_model.provider) do
      with_ruby_llm_method(:paint, painter) do
        ImageRunJob.perform_now(run.id)
        ImageRunJob.perform_now(run.id)
      end
    end

    run.reload
    attempt = run.attempts.first
    assert run.succeeded?, run.error_summary
    assert_equal 1, calls.length
    assert_equal "A tiny paper boat on a blue lake", calls.first.first
    assert_equal @image_model.id, calls.first.last.fetch(:model)
    assert_equal @image_model.provider.to_sym, calls.first.last.fetch(:provider)
    assert_equal 12, attempt.input_tokens
    assert_equal "unknown", attempt.cost_status

    artifact = run.artifacts.find_by!(kind: "image")
    assert artifact.media_file.attached?
    assert_equal "image/png", artifact.media_file.blob.content_type
    assert_equal "fake-png-data", artifact.media_file.download
    assert_equal Digest::SHA256.hexdigest("fake-png-data"), artifact.metadata_json.fetch("sha256")
    assert_equal @image_model.provider, artifact.metadata_json.fetch("provider")
    assert_equal @image_model.id, artifact.metadata_json.fetch("model_id")

    get run_path(run)
    assert_response :success
    assert_select "h2", text: "Image Artifacts"
    assert_select "img[alt=?]", "Generated image for Run ##{run.id}"
    assert_select "a", text: "Download"
  end

  test "transcription queues the upload and stores source and transcript Artifacts" do
    assert @transcription_model
    upload = Rack::Test::UploadedFile.new(
      StringIO.new("fake-mp3-audio".b),
      "audio/mpeg",
      original_filename: "interview.mp3"
    )

    run = nil
    with_provider_configuration(@transcription_model.provider) do
      assert_enqueued_with(job: TranscriptionRunJob) do
        post project_chat_transcription_runs_path(@project, @chat), params: {
          transcription_run: {
            audio_file: upload,
            model_reference: model_reference(@transcription_model)
          }
        }
        run = @chat.runs.order(:id).last
      end
    end

    assert_response :see_other
    assert run.queued?
    source = run.artifacts.find_by!(kind: "audio")
    assert source.audio_file.attached?
    assert_equal "fake-mp3-audio", source.audio_file.download
    assert_equal "interview.mp3", source.name
    assert_equal Digest::SHA256.hexdigest("fake-mp3-audio"), run.input_snapshot.dig("transcription", "source_sha256")

    transcription = TranscriptionResponse.new(
      "The interview starts at nine.",
      "en",
      3.4,
      @transcription_model.id,
      RubyLLM::Tokens.new(input: 32, output: 8),
      nil
    )
    calls = []
    transcriber = ->(audio, **options) { calls << [ audio, options ]; transcription }

    with_provider_configuration(@transcription_model.provider) do
      with_ruby_llm_method(:transcribe, transcriber) do
        TranscriptionRunJob.perform_now(run.id)
        TranscriptionRunJob.perform_now(run.id)
      end
    end

    run.reload
    attempt = run.attempts.first
    assert run.succeeded?, run.error_summary
    assert_equal 1, calls.length
    assert_instance_of ActiveStorage::Blob, calls.first.first
    assert_equal @transcription_model.id, calls.first.last.fetch(:model)
    assert_equal @transcription_model.provider.to_sym, calls.first.last.fetch(:provider)
    assert_equal 32, attempt.input_tokens
    assert_equal 8, attempt.output_tokens
    assert_equal "unknown", attempt.cost_status

    transcript = run.artifacts.find_by!(kind: "transcript")
    assert_equal "The interview starts at nine.", transcript.content_text
    assert_equal source.id, transcript.metadata_json.fetch("source_artifact_id")
    assert_equal source.metadata_json.fetch("sha256"), transcript.metadata_json.fetch("source_sha256")

    get run_path(run)
    assert_response :success
    assert_select "h2", text: "Transcript Artifacts"
    assert_includes response.body, "The interview starts at nine."
  end

  test "whitespace-only transcription is stored as a successful empty transcript" do
    assert @transcription_model
    run = with_audio_upload("fake-mp3-audio", filename: "interview.mp3") do |upload|
      with_provider_configuration(@transcription_model.provider) do
        Ai::TranscriptionRunExecutor.enqueue(
          chat: @chat,
          audio_upload: upload,
          model_reference: model_reference(@transcription_model)
        )
      end
    end
    transcription = TranscriptionResponse.new(
      " \n\t",
      "en",
      0.0,
      @transcription_model.id,
      RubyLLM::Tokens.new(input: 12, output: 0),
      nil
    )

    with_provider_configuration(@transcription_model.provider) do
      with_ruby_llm_method(:transcribe, ->(*) { transcription }) do
        TranscriptionRunJob.perform_now(run.id)
      end
    end

    assert run.reload.succeeded?, run.error_summary
    assert run.attempts.first.succeeded?
    artifact = run.artifacts.find_by!(kind: "transcript")
    assert_equal "", artifact.content_text
    assert_equal true, run.result_summary.fetch("empty_transcript")
  end

  test "storage upload failure cannot mark a media Run or Attempt successful" do
    run = with_provider_configuration(@image_model.provider) do
      Ai::ImageRunExecutor.enqueue(
        chat: @chat,
        prompt: "A paper boat",
        model_reference: model_reference(@image_model)
      )
    end
    response = MediaResponse.new("fake-png-data".b, @image_model.id, "image/png", nil, nil, nil)
    blobs_before = ActiveStorage::Blob.count

    with_provider_configuration(@image_model.provider) do
      with_ruby_llm_method(:paint, ->(*) { response }) do
        with_storage_upload_failure do
          ImageRunJob.perform_now(run.id)
        end
      end
    end

    assert run.reload.failed?
    assert run.attempts.first.failed?
    assert_includes run.error_summary, "storage upload failed"
    assert_empty run.artifacts.where(kind: "image")
    assert_equal blobs_before, ActiveStorage::Blob.count
  end

  test "source audio storage failure creates no transcription Run or Blob" do
    runs_before = @chat.runs.count
    blobs_before = ActiveStorage::Blob.count

    with_audio_upload("fake-mp3-audio", filename: "interview.mp3") do |upload|
      with_provider_configuration(@transcription_model.provider) do
        with_storage_upload_failure do
          assert_raises(ArgumentError) do
            Ai::TranscriptionRunExecutor.enqueue(
              chat: @chat,
              audio_upload: upload,
              model_reference: model_reference(@transcription_model)
            )
          end
        end
      end
    end

    assert_equal runs_before, @chat.runs.count
    assert_equal blobs_before, ActiveStorage::Blob.count
  end

  test "video request returns before rendering and stores the video Artifact" do
    assert @video_model
    run = nil

    with_provider_configuration(@video_model.provider) do
      assert_enqueued_with(job: VideoRunJob) do
        post project_chat_video_runs_path(@project, @chat), params: {
          video_run: {
            prompt: "A paper boat crossing a lake",
            model_reference: model_reference(@video_model)
          }
        }
        run = @chat.runs.order(:id).last
      end
    end

    assert_response :see_other
    assert run.queued?
    assert_equal @video_model.id, run.input_snapshot.dig("video", "model_id")

    response = MediaResponse.new("fake-video-data".b, @video_model.id, "video/mp4", nil, nil, 2.5)
    calls = []
    animator = ->(prompt, **options) { calls << [ prompt, options ]; response }

    with_provider_configuration(@video_model.provider) do
      with_ruby_llm_method(:animate, animator) do
        VideoRunJob.perform_now(run.id)
        VideoRunJob.perform_now(run.id)
      end
    end

    run.reload
    attempt = run.attempts.first
    assert run.succeeded?
    assert_equal 1, calls.length
    assert_equal "A paper boat crossing a lake", calls.first.first
    assert_equal @video_model.id, calls.first.last.fetch(:model)
    assert_equal "unknown", attempt.cost_status

    artifact = run.artifacts.find_by!(kind: "video")
    assert artifact.media_file.attached?
    assert_equal "video/mp4", artifact.media_file.blob.content_type
    assert_equal 2.5, artifact.metadata_json.fetch("duration_seconds")
    assert_equal Digest::SHA256.hexdigest("fake-video-data"), artifact.metadata_json.fetch("sha256")

    get run_path(run)
    assert_response :success
    assert_select "h2", text: "Video Artifacts"
    assert_select "video[controls]"
    assert_select "a", text: "Download"
  end

  test "a provider failure after image cancellation cannot change terminal state" do
    run = with_provider_configuration(@image_model.provider) do
      Ai::ImageRunExecutor.enqueue(
        chat: @chat,
        prompt: "A paper boat",
        model_reference: model_reference(@image_model)
      )
    end
    painter = lambda do |_prompt, **_options|
      run.cancel!
      raise RubyLLM::Error, "late image provider failure"
    end

    with_provider_configuration(@image_model.provider) do
      with_ruby_llm_method(:paint, painter) { ImageRunJob.perform_now(run.id) }
    end

    assert run.reload.cancelled?
    assert run.attempts.first.cancelled?
    assert_empty run.artifacts.where(kind: "image")
  end

  test "a provider failure after transcription cancellation preserves the source Artifact" do
    run = with_audio_upload("fake-mp3-audio", filename: "interview.mp3") do |upload|
      with_provider_configuration(@transcription_model.provider) do
        Ai::TranscriptionRunExecutor.enqueue(
          chat: @chat,
          audio_upload: upload,
          model_reference: model_reference(@transcription_model)
        )
      end
    end
    transcriber = lambda do |_audio, **_options|
      run.cancel!
      raise RubyLLM::Error, "late transcription provider failure"
    end

    with_provider_configuration(@transcription_model.provider) do
      with_ruby_llm_method(:transcribe, transcriber) { TranscriptionRunJob.perform_now(run.id) }
    end

    assert run.reload.cancelled?
    assert run.attempts.first.cancelled?
    assert run.artifacts.find_by!(kind: "audio").audio_file.attached?
    assert_empty run.artifacts.where(kind: "transcript")
  end

  test "stale recovery fences a late successful image response" do
    run = with_provider_configuration(@image_model.provider) do
      Ai::ImageRunExecutor.enqueue(
        chat: @chat,
        prompt: "A paper boat",
        model_reference: model_reference(@image_model)
      )
    end
    response = MediaResponse.new("late-image".b, @image_model.id, "image/png", nil, nil, nil)
    painter = lambda do |_prompt, **_options|
      MediaRunRecoveryJob.perform_now(Time.current + 31.minutes)
      response
    end

    with_provider_configuration(@image_model.provider) do
      with_ruby_llm_method(:paint, painter) { ImageRunJob.perform_now(run.id) }
    end

    assert run.reload.failed?
    assert_equal "worker_interrupted", run.result_summary.dig("recovery", "reason")
    assert run.attempts.first.failed?
    assert_empty run.artifacts.where(kind: "image")
  end

  test "stale recovery fences a late successful video response" do
    run = with_provider_configuration(@video_model.provider) do
      Ai::VideoRunExecutor.enqueue(
        chat: @chat,
        prompt: "A paper boat",
        model_reference: model_reference(@video_model)
      )
    end
    response = MediaResponse.new("late-video".b, @video_model.id, "video/mp4", nil, nil, 2.5)
    animator = lambda do |_prompt, **_options|
      MediaRunRecoveryJob.perform_now(Time.current + 31.minutes)
      response
    end

    with_provider_configuration(@video_model.provider) do
      with_ruby_llm_method(:animate, animator) { VideoRunJob.perform_now(run.id) }
    end

    assert run.reload.failed?
    assert_equal "worker_interrupted", run.result_summary.dig("recovery", "reason")
    assert run.attempts.first.failed?
    assert_empty run.artifacts.where(kind: "video")
  end

  test "queue rejection fails image video and transcription Runs before provider work" do
    operations = [
      [ "image", ImageRunJob, @image_model ],
      [ "video", VideoRunJob, @video_model ],
      [ "transcription", TranscriptionRunJob, @transcription_model ]
    ]

    operations.each do |operation, job_class, model|
      error = IOError.new("queue unavailable")
      fake_job = RejectedEnqueue.new(error)
      enqueue = case operation
      when "image"
        -> {
          Ai::ImageRunExecutor.enqueue(
            chat: @chat,
            prompt: "A paper boat",
            model_reference: model_reference(model)
          )
        }
      when "video"
        -> {
          Ai::VideoRunExecutor.enqueue(
            chat: @chat,
            prompt: "A moving paper boat",
            model_reference: model_reference(model)
          )
        }
      when "transcription"
        -> {
          with_audio_upload("fake-mp3-audio", filename: "interview.mp3") do |upload|
            Ai::TranscriptionRunExecutor.enqueue(
              chat: @chat,
              audio_upload: upload,
              model_reference: model_reference(model)
            )
          end
        }
      end

      raised = with_rejected_enqueue(job_class, fake_job) do
        with_provider_configuration(model.provider) do
          assert_raises(ArgumentError, operation, &enqueue)
        end
      end
      assert_includes raised.message, "queue unavailable"

      run = @chat.runs.where(operation:).order(:id).last
      assert run.failed?, "#{operation} Run should be closed after queue rejection"
      attempt = run.attempts.first
      assert attempt.failed?
      assert_equal attempt.error_code, run.result_summary.fetch("failure_kind")
      assert_includes attempt.error_message, "queue unavailable"
      assert_empty run.artifacts.where(kind: %w[image video transcript])
      if operation == "transcription"
        assert run.artifacts.find_by!(kind: "audio").audio_file.attached?
      end
    end
  end

  test "media executors reject a model without the requested capability" do
    unsupported_model = chat_model

    assert_no_difference -> { @chat.runs.count } do
      post project_chat_image_runs_path(@project, @chat), params: {
        image_run: { prompt: "A tree", model_reference: model_reference(unsupported_model) }
      }
    end

    assert_response :unprocessable_entity
    assert_includes response.body, "does not declare image-generation support"
  end

  test "chat disables media actions when no catalog model supports them" do
    unsupported_model = test_model("chat")
    RubyLLM.models.instance_variable_set(:@models, [ unsupported_model ])
    @chat.update!(provider: unsupported_model.provider, model_id: unsupported_model.id)
    message = @chat.messages.create!(role: "assistant", content: "A saved reply")

    assert_empty Ai::MediaCatalog.entries(operation: "image")
    assert_empty Ai::MediaCatalog.entries(operation: "transcription")
    assert_empty Ai::MediaCatalog.entries(operation: "video")
    assert_empty Ai::SpeechCatalog.entries

    get project_chat_path(@project, @chat)

    assert_response :success
    assert_select "a[href=?]", new_project_chat_image_run_path(@project, @chat), count: 0
    assert_select "span[aria-disabled='true'][title=?]", "No RubyLLM image-generation model is available", text: "Image unavailable"
    assert_select "a[href=?]", new_project_chat_transcription_run_path(@project, @chat), count: 0
    assert_select "span[aria-disabled='true'][title=?]", "No RubyLLM transcription model is available", text: "Transcription unavailable"
    assert_select "a[href=?]", new_project_chat_video_run_path(@project, @chat), count: 0
    assert_select "span[aria-disabled='true'][title=?]", "No RubyLLM video-generation model is available", text: "Video unavailable"
    assert_select "a[href=?]", new_project_chat_message_speech_run_path(@project, @chat, message), count: 0
    assert_select "span[aria-disabled='true'][title=?]", "No RubyLLM speech-generation model is available", text: "Speech unavailable"
  end

  private

  def test_model(operation, capabilities: [], input: "text", output: "text")
    RubyLLM::Model.new(
      id: "test-#{operation}-model",
      name: "Test #{operation.capitalize} Model",
      provider: "openai",
      capabilities:,
      modalities: { input: [ input ], output: [ output ] },
      pricing: {}
    )
  end

  def model_reference(model)
    "#{model.provider}|#{model.id}"
  end

  def with_ruby_llm_method(name, replacement)
    original = RubyLLM.method(name)
    RubyLLM.define_singleton_method(name, replacement)
    yield
  ensure
    RubyLLM.define_singleton_method(name, original)
  end

  def with_audio_upload(data, filename:)
    tempfile = Tempfile.new([ "audio-upload", File.extname(filename) ])
    tempfile.binmode
    tempfile.write(data)
    tempfile.rewind
    upload = ActionDispatch::Http::UploadedFile.new(
      tempfile:,
      filename:,
      type: "audio/mpeg"
    )
    yield upload
  ensure
    tempfile&.close!
  end

  def with_rejected_enqueue(job_class, fake_job)
    original = job_class.method(:perform_later)
    job_class.define_singleton_method(:perform_later) { |*_arguments| fake_job }
    yield
  ensure
    job_class.define_singleton_method(:perform_later, original) if original
  end

  def with_storage_upload_failure
    service = ActiveStorage::Blob.service
    original_upload = service.method(:upload)
    service.define_singleton_method(:upload) do |*_args, **_options|
      raise IOError, "storage upload failed"
    end
    yield
  ensure
    service.define_singleton_method(:upload, original_upload) if service && original_upload
  end
end

module Ai
  class TranscriptionRunExecutor
    MAX_AUDIO_BYTES = 25_000_000
    AUDIO_EXTENSIONS = {
      ".flac" => %w[audio/flac audio/x-flac],
      ".m4a" => %w[audio/mp4 audio/x-m4a],
      ".mp3" => %w[audio/mpeg audio/mp3],
      ".mp4" => %w[audio/mp4 video/mp4],
      ".mpeg" => %w[audio/mpeg],
      ".mpga" => %w[audio/mpeg],
      ".ogg" => %w[audio/ogg application/ogg],
      ".wav" => %w[audio/wav audio/x-wav audio/wave],
      ".webm" => %w[audio/webm video/webm]
    }.freeze

    def self.enqueue(chat:, audio_upload:, model_reference:, requested_by: "local_user")
      new(chat:, audio_upload:, model_reference:, requested_by:).enqueue
    end

    def initialize(chat:, audio_upload:, model_reference:, requested_by:)
      @chat = chat
      @audio_upload = audio_upload
      @model_reference = model_reference.to_s
      @requested_by = requested_by
    end

    def enqueue
      validate_upload!
      provider, model_id = @model_reference.split("|", 2)
      raise ArgumentError, "Choose a transcription model." if provider.blank? || model_id.blank?

      entry = MediaCatalog.find(operation: "transcription", model_id:, provider:)
      raise ArgumentError, "This model does not declare audio-transcription support." unless entry
      unless entry.configured
        missing = entry.missing_configuration.join(", ").presence || "provider configuration"
        raise ArgumentError, "This transcription model is not runnable yet. Configure #{missing} first."
      end

      source_blob = upload_source_blob
      begin
        run = create_run(entry, source_blob:)
      ensure
        MediaBlobStorage.purge_if_unattached!(source_blob)
      end
      enqueue_job(run)
      run
    end

    private

    def validate_upload!
      raise ArgumentError, "Choose an audio file to transcribe." unless @audio_upload.respond_to?(:tempfile)

      extension = File.extname(@audio_upload.original_filename.to_s).downcase
      allowed_types = AUDIO_EXTENSIONS[extension]
      content_type = @audio_upload.content_type.to_s.downcase
      raise ArgumentError, "Use a supported audio file (FLAC, M4A, MP3, MP4, MPEG, OGG, WAV, or WebM)." unless allowed_types&.include?(content_type)
      raise ArgumentError, "Audio files must be 25 MB or smaller." if @audio_upload.size.to_i > MAX_AUDIO_BYTES
      raise ArgumentError, "The uploaded audio file is empty." if @audio_upload.size.to_i.zero?
    end

    def create_run(entry, source_blob:)
      provider = entry.provider.to_s
      model_id = entry.id.to_s
      original_filename = safe_filename(@audio_upload.original_filename)
      content_type = @audio_upload.content_type.to_s.downcase
      byte_size = @audio_upload.size.to_i
      sha256 = upload_sha256

      run = nil
      @chat.transaction do
        run = @chat.runs.create!(
          project: @chat.project,
          operation: "transcription",
          status: :queued,
          requested_by: @requested_by,
          input_snapshot_json: {
            "transcription" => {
              "provider" => provider,
              "model_id" => model_id,
              "source_filename" => original_filename,
              "source_content_type" => content_type,
              "source_byte_size" => byte_size,
              "source_sha256" => sha256
            }
          },
          app_version: ENV.fetch("APP_VERSION", "local"),
          ruby_llm_version: Gem.loaded_specs.fetch("ruby_llm").version.to_s
        )
        attempt = run.attempts.create!(sequence: 1, provider:, model_id:, status: :queued)
        source_artifact = run.artifacts.build(
          attempt:,
          kind: "audio",
          name: original_filename,
          metadata_json: {
            "role" => "transcription_input",
            "provider" => provider,
            "model_id" => model_id,
            "mime_type" => content_type,
            "byte_size" => byte_size,
            "sha256" => sha256
          }
        )
        source_artifact.audio_file.attach(source_blob)
        source_artifact.save!
      end
      run
    end

    def upload_source_blob
      filename = safe_filename(@audio_upload.original_filename)
      tempfile = @audio_upload.tempfile
      tempfile.rewind
      MediaBlobStorage.upload!(io: tempfile, filename:, content_type: @audio_upload.content_type.to_s.downcase)
    rescue StandardError => error
      raise ArgumentError, "Audio upload could not be stored: #{ErrorText.redact(error.message)}"
    ensure
      tempfile&.rewind
    end

    def enqueue_job(run)
      job = TranscriptionRunJob.perform_later(run.id)
      unless job.respond_to?(:successfully_enqueued?) && job.successfully_enqueued?
        raise job.enqueue_error if job.respond_to?(:enqueue_error) && job.enqueue_error

        raise ActiveJob::EnqueueError, "Transcription Run job was not accepted by the queue adapter."
      end
    rescue StandardError => error
      attempt = run.attempts.first
      run.fail_queued_execution!(operation: "transcription", error:) do
        attempt&.finish!(
          status: :failed,
          finished_at: Time.current,
          error_class: error.class.name,
          error_code: Ai::ErrorClassifier.code(error),
          error_message: Ai::ErrorText.redact(error.message).to_s.truncate(2_000)
        )
      end
      raise ArgumentError, "Transcription Run could not be queued: #{Ai::ErrorText.redact(error.message)}"
    end

    def upload_sha256
      tempfile = @audio_upload.tempfile
      tempfile.rewind
      Digest::SHA256.file(tempfile.path).hexdigest
    ensure
      tempfile&.rewind
    end

    def safe_filename(filename)
      basename = File.basename(filename.to_s)
      basename = basename.gsub(/[^\p{Alnum}_.-]/, "_").truncate(120)
      basename.presence || "audio-upload#{File.extname(filename.to_s).downcase}"
    end
  end
end

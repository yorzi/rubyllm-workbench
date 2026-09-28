class VideoRunJob < ApplicationJob
  queue_as :default

  ALLOWED_MIME_TYPES = %w[video/mp4 video/quicktime video/webm].freeze

  def perform(run_id)
    @run = Run.includes(:attempts, :chat).find(run_id)
    return unless @run.operation == "video" && !@run.terminal?

    @attempt = @run.attempts.order(:sequence, :id).first
    return unless @attempt && claim_run

    started_monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    snapshot = @run.input_snapshot.fetch("video")
    video = Ai::ExecutionContext.with(run_id: @run.id, attempt_id: @attempt.id) do
      RubyLLM.animate(
        snapshot.fetch("prompt"),
        model: snapshot.fetch("model_id"),
        provider: snapshot.fetch("provider").to_sym
      )
    end

    persist_result(video, started_monotonic)
  rescue StandardError => error
    persist_failure(error) if @run && !@run.terminal?
  end

  private

  def claim_run
    claimed = @run.claim_queued_execution!(operation: "video")
    @run.reload
    return false unless claimed

    @attempt.reload
    @attempt.start! unless @attempt.running?
    true
  end

  def persist_result(video, started_monotonic)
    raise ArgumentError, "The video provider returned no video." unless video

    data = video.to_blob.to_s.b
    mime_type = video.mime_type.to_s.downcase
    raise ArgumentError, "The video provider returned no video data." if data.empty?
    raise ArgumentError, "The video provider returned an unsupported media type." unless ALLOWED_MIME_TYPES.include?(mime_type)

    snapshot = @run.input_snapshot.fetch("video")
    model_id = video.model.to_s.presence || snapshot.fetch("model_id")
    extension = { "video/mp4" => "mp4", "video/quicktime" => "mov", "video/webm" => "webm" }.fetch(mime_type)
    filename = "run-#{@run.id}.#{extension}"
    metadata = {
      "provider" => snapshot.fetch("provider"),
      "model_id" => model_id,
      "mime_type" => mime_type,
      "duration_seconds" => video.duration,
      "byte_size" => data.bytesize,
      "sha256" => Digest::SHA256.hexdigest(data)
    }.compact
    blob = Ai::MediaBlobStorage.upload!(io: StringIO.new(data), filename:, content_type: mime_type)

    begin
      @run.finish_running_execution!(operation: "video", status: :succeeded, summary: {}) do
        artifact = @run.artifacts.build(
          attempt: @attempt,
          kind: "video",
          name: filename,
          metadata_json: metadata
        )
        artifact.media_file.attach(blob)
        artifact.save!

        # RubyLLM::Video does not expose normalized token or cost fields, so the
        # Attempt records unknown cost instead of inferring provider-specific raw data.
        @attempt.finish!(
          status: :succeeded,
          finished_at: Time.current,
          duration_ms: elapsed_ms(started_monotonic),
          cost_status: "unknown",
          currency: "USD",
          metadata_json: (@attempt.metadata_json || {}).merge("video" => metadata)
        )
        { "artifact_id" => artifact.id, "video" => metadata }
      end
    ensure
      Ai::MediaBlobStorage.purge_if_unattached!(blob)
    end
  end

  def persist_failure(error)
    @run.finish_running_execution!(operation: "video", status: :failed, error:) do
      @attempt.reload if @attempt&.persisted?
      if @attempt && (@attempt.queued? || @attempt.running?)
        @attempt.finish!(
          status: :failed,
          finished_at: Time.current,
          error_class: error.class.name,
          error_code: Ai::ErrorClassifier.code(error),
          error_message: Ai::ErrorText.redact(error.message).to_s.truncate(2_000)
        )
      end
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def elapsed_ms(started_monotonic)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_monotonic) * 1_000).round
  end
end

class ImageRunJob < ApplicationJob
  queue_as :default

  ALLOWED_MIME_TYPES = %w[image/avif image/gif image/jpeg image/png image/webp].freeze

  def perform(run_id)
    @run = Run.includes(:attempts, :chat).find(run_id)
    return unless @run.operation == "image" && !@run.terminal?

    @attempt = @run.attempts.order(:sequence, :id).first
    return unless @attempt && claim_run

    started_monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    snapshot = @run.input_snapshot.fetch("image")
    result = Ai::ExecutionContext.with(run_id: @run.id, attempt_id: @attempt.id) do
      RubyLLM.paint(
        snapshot.fetch("prompt"),
        model: snapshot.fetch("model_id"),
        provider: snapshot.fetch("provider").to_sym,
        count: 1
      )
    end

    image = result.is_a?(Array) ? result.first : result
    persist_result(image, started_monotonic)
  rescue StandardError => error
    persist_failure(error) if @run && !@run.terminal?
  end

  private

  def claim_run
    claimed = @run.claim_queued_execution!(operation: "image")
    @run.reload
    return false unless claimed

    @attempt.reload
    @attempt.start! unless @attempt.running?
    true
  end

  def persist_result(image, started_monotonic)
    raise ArgumentError, "The image provider returned no image." unless image

    data = image.to_blob.to_s.b
    mime_type = image.mime_type.to_s.downcase
    raise ArgumentError, "The image provider returned no image data." if data.empty?
    raise ArgumentError, "The image provider returned an unsupported media type." unless ALLOWED_MIME_TYPES.include?(mime_type)

    snapshot = @run.input_snapshot.fetch("image")
    model_id = image.model.to_s.presence || snapshot.fetch("model_id")
    extension = { "image/jpeg" => "jpg", "image/png" => "png", "image/webp" => "webp", "image/gif" => "gif", "image/avif" => "avif" }.fetch(mime_type)
    filename = "run-#{@run.id}.#{extension}"
    metadata = {
      "provider" => snapshot.fetch("provider"),
      "model_id" => model_id,
      "mime_type" => mime_type,
      "byte_size" => data.bytesize,
      "sha256" => Digest::SHA256.hexdigest(data)
    }
    model = Ai::MediaCatalog.find(
      operation: "image",
      model_id: snapshot.fetch("model_id"),
      provider: snapshot.fetch("provider")
    )&.model
    blob = Ai::MediaBlobStorage.upload!(io: StringIO.new(data), filename:, content_type: mime_type)

    begin
      @run.finish_running_execution!(operation: "image", status: :succeeded, summary: {}) do
        artifact = @run.artifacts.build(
          attempt: @attempt,
          kind: "image",
          name: filename,
          metadata_json: metadata
        )
        artifact.media_file.attach(blob)
        artifact.save!

        @attempt.finish!(
          status: :succeeded,
          finished_at: Time.current,
          duration_ms: elapsed_ms(started_monotonic),
          **token_attributes(image.tokens),
          **Ai::CostNormalizer.for(image, model:, category: :images),
          metadata_json: (@attempt.metadata_json || {}).merge("image" => metadata)
        )
        { "artifact_id" => artifact.id, "image" => metadata }
      end
    ensure
      Ai::MediaBlobStorage.purge_if_unattached!(blob)
    end
  end

  def token_attributes(tokens)
    {
      input_tokens: tokens&.input,
      output_tokens: tokens&.output,
      cache_read_tokens: tokens&.cache_read,
      cache_write_tokens: tokens&.cache_write,
      thinking_tokens: tokens&.thinking
    }.compact
  end

  def persist_failure(error)
    @run.finish_running_execution!(operation: "image", status: :failed, error:) do
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

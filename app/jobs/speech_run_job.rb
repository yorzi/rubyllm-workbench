class SpeechRunJob < ApplicationJob
  queue_as :default

  TOKEN_ATTRIBUTES = {
    input_tokens: :input,
    output_tokens: :output,
    cache_read_tokens: :cache_read,
    cache_write_tokens: :cache_write,
    thinking_tokens: :thinking
  }.freeze

  def perform(run_id)
    @run = Run.includes(:attempts, :chat).find(run_id)
    return unless @run.operation == "speech" && !@run.terminal?

    @attempt = @run.attempts.order(:sequence, :id).first
    return unless @attempt && claim_run

    started_monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    snapshot = @run.input_snapshot.fetch("speech")
    speech = Ai::ExecutionContext.with(run_id: @run.id, attempt_id: @attempt.id) do
      RubyLLM.speak(
        snapshot.fetch("text"),
        model: snapshot.fetch("model_id"),
        provider: snapshot.fetch("provider").to_sym,
        voice: snapshot["voice"],
        format: snapshot["format"]
      )
    end

    persist_result(speech, started_monotonic)
  rescue StandardError => error
    persist_failure(error) if @run && !@run.terminal?
  end

  private

  def claim_run
    claimed = @run.claim_queued_execution!(operation: "speech")
    @run.reload
    return false unless claimed

    @attempt.reload
    @attempt.start! unless @attempt.running?
    true
  end

  def persist_result(speech, started_monotonic)
    data = speech.to_blob.to_s.b
    mime_type = speech.mime_type.to_s
    raise ArgumentError, "The speech provider returned no audio." if data.empty?
    raise ArgumentError, "The speech provider returned an unsupported media type." unless mime_type.start_with?("audio/")

    snapshot = @run.input_snapshot.fetch("speech")
    format = speech.format.to_s.presence || mime_type.delete_prefix("audio/")
    filename = "run-#{@run.id}.#{safe_extension(format)}"
    metadata = {
      "source_message_id" => @run.input_snapshot["source_message_id"],
      "provider" => snapshot.fetch("provider"),
      "model_id" => speech.model.to_s.presence || snapshot.fetch("model_id"),
      "voice" => speech.voice,
      "format" => format,
      "mime_type" => mime_type,
      "byte_size" => data.bytesize,
      "sha256" => Digest::SHA256.hexdigest(data)
    }.compact
    token_attributes = TOKEN_ATTRIBUTES.to_h do |attribute, reader|
      [ attribute, speech.tokens.public_send(reader) ]
    end
    model = Ai::SpeechCatalog.find(snapshot.fetch("model_id"), provider: snapshot.fetch("provider"))&.model
    blob = Ai::MediaBlobStorage.upload!(io: StringIO.new(data), filename:, content_type: mime_type)

    begin
      @run.finish_running_execution!(
        operation: "speech",
        status: :succeeded,
        summary: {}
      ) do
        artifact = @run.artifacts.build(
          attempt: @attempt,
          kind: "audio",
          name: filename,
          metadata_json: metadata
        )
        artifact.audio_file.attach(blob)
        artifact.save!

        @attempt.finish!(
          status: :succeeded,
          finished_at: Time.current,
          duration_ms: elapsed_ms(started_monotonic),
          **token_attributes,
          **Ai::CostNormalizer.for(speech, model: model, category: :audio_tokens),
          metadata_json: (@attempt.metadata_json || {}).merge("speech" => metadata)
        )
        { "artifact_id" => artifact.id, "audio" => metadata }
      end
    ensure
      Ai::MediaBlobStorage.purge_if_unattached!(blob)
    end
  end

  def persist_failure(error)
    @run.finish_running_execution!(operation: "speech", status: :failed, error:) do
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

  def safe_extension(format)
    value = format.to_s.downcase.gsub(/[^a-z0-9]/, "")
    value.presence || "audio"
  end
end

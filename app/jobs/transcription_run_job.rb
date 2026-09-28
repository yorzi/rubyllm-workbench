class TranscriptionRunJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    @run = Run.includes(:attempts, :chat, :artifacts).find(run_id)
    return unless @run.operation == "transcription" && !@run.terminal?

    @attempt = @run.attempts.order(:sequence, :id).first
    return unless @attempt && claim_run

    started_monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    snapshot = @run.input_snapshot.fetch("transcription")
    source_artifact = @run.artifacts.find do |artifact|
      artifact.kind == "audio" && artifact.metadata_json["role"] == "transcription_input"
    end
    raise ArgumentError, "The uploaded audio Artifact is missing." unless source_artifact&.audio_file&.attached?

    transcription = Ai::ExecutionContext.with(run_id: @run.id, attempt_id: @attempt.id) do
      RubyLLM.transcribe(
        source_artifact.audio_file.blob,
        model: snapshot.fetch("model_id"),
        provider: snapshot.fetch("provider").to_sym
      )
    end

    persist_result(transcription, source_artifact, started_monotonic)
  rescue StandardError => error
    persist_failure(error) if @run && !@run.terminal?
  end

  private

  def claim_run
    claimed = @run.claim_queued_execution!(operation: "transcription")
    @run.reload
    return false unless claimed

    @attempt.reload
    @attempt.start! unless @attempt.running?
    true
  end

  def persist_result(transcription, source_artifact, started_monotonic)
    text = transcription.text.to_s
    text = "" if text.blank?
    snapshot = @run.input_snapshot.fetch("transcription")
    metadata = {
      "provider" => snapshot.fetch("provider"),
      "model_id" => transcription.model.to_s.presence || snapshot.fetch("model_id"),
      "source_artifact_id" => source_artifact.id,
      "source_sha256" => snapshot["source_sha256"],
      "language" => transcription.language,
      "duration_seconds" => transcription.duration
    }.compact
    model = Ai::MediaCatalog.find(
      operation: "transcription",
      model_id: snapshot.fetch("model_id"),
      provider: snapshot.fetch("provider")
    )&.model

    @run.finish_running_execution!(operation: "transcription", status: :succeeded, summary: {}) do
      artifact = @run.artifacts.create!(
        attempt: @attempt,
        kind: "transcript",
        name: "run-#{@run.id}-transcript.txt",
        content_text: text,
        metadata_json: metadata
      )

      @attempt.finish!(
        status: :succeeded,
        finished_at: Time.current,
        duration_ms: elapsed_ms(started_monotonic),
        **token_attributes(transcription.tokens),
        **Ai::CostNormalizer.for(transcription, model:, category: :audio_tokens),
        metadata_json: (@attempt.metadata_json || {}).merge("transcription" => metadata)
      )
      {
        "artifact_id" => artifact.id,
        "transcription" => metadata,
        "empty_transcript" => text.blank?
      }
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
    @run.finish_running_execution!(operation: "transcription", status: :failed, error:) do
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

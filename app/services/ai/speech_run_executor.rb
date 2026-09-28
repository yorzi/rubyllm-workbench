module Ai
  class SpeechRunExecutor
    def self.enqueue(message:, model_reference:, requested_by: "local_user")
      new(message:, model_reference:, requested_by:).enqueue
    end

    def initialize(message:, model_reference:, requested_by:)
      @message = message
      @model_reference = model_reference.to_s
      @requested_by = requested_by
    end

    def enqueue
      validate_message!
      provider, model_id = @model_reference.split("|", 2)
      raise ArgumentError, "Choose a speech model." if provider.blank? || model_id.blank?

      entry = SpeechCatalog.find(model_id, provider: provider)
      raise ArgumentError, "This model does not declare speech generation support." unless entry
      unless entry.configured
        missing = entry.missing_configuration.join(", ").presence || "provider configuration"
        raise ArgumentError, "This speech model is not runnable yet. Configure #{missing} first."
      end

      run = create_run(entry)
      enqueue_job(run)
      run
    end

    private

    def validate_message!
      valid_message = @message&.role == "assistant" && @message.content.present?
      raise ArgumentError, "Only a non-empty assistant reply can be converted to speech." unless valid_message
    end

    def create_run(entry)
      provider = entry.provider.to_s
      model_id = entry.id.to_s
      snapshot = {
        "source_message_id" => @message.id,
        "speech" => {
          "text" => @message.content,
          "provider" => provider,
          "model_id" => model_id,
          "voice" => nil,
          "format" => nil
        }
      }

      run = nil
      @message.chat.transaction do
        run = @message.chat.runs.create!(
          project: @message.chat.project,
          operation: "speech",
          status: :queued,
          requested_by: @requested_by,
          input_snapshot_json: snapshot,
          app_version: ENV.fetch("APP_VERSION", "local"),
          ruby_llm_version: Gem.loaded_specs.fetch("ruby_llm").version.to_s
        )
        run.attempts.create!(
          sequence: 1,
          provider: provider,
          model_id: model_id,
          status: :queued
        )
      end
      run
    end

    def enqueue_job(run)
      job = SpeechRunJob.perform_later(run.id)
      unless job.respond_to?(:successfully_enqueued?) && job.successfully_enqueued?
        raise job.enqueue_error if job.respond_to?(:enqueue_error) && job.enqueue_error

        raise ActiveJob::EnqueueError, "Speech Run job was not accepted by the queue adapter."
      end
    rescue StandardError => error
      attempt = run.attempts.first
      run.fail_queued_execution!(operation: "speech", error:) do
        attempt&.finish!(
          status: :failed,
          finished_at: Time.current,
          error_class: error.class.name,
          error_code: Ai::ErrorClassifier.code(error),
          error_message: Ai::ErrorText.redact(error.message).to_s.truncate(2_000)
        )
      end
      raise ArgumentError, "Speech Run could not be queued: #{Ai::ErrorText.redact(error.message)}"
    end
  end
end

module Ai
  class VideoRunExecutor
    MAX_PROMPT_LENGTH = 8_000

    def self.enqueue(chat:, prompt:, model_reference:, requested_by: "local_user")
      new(chat:, prompt:, model_reference:, requested_by:).enqueue
    end

    def initialize(chat:, prompt:, model_reference:, requested_by:)
      @chat = chat
      @prompt = prompt.to_s.strip
      @model_reference = model_reference.to_s
      @requested_by = requested_by
    end

    def enqueue
      raise ArgumentError, "A video prompt is required." if @prompt.blank?
      raise ArgumentError, "Video prompts must be #{MAX_PROMPT_LENGTH} characters or fewer." if @prompt.length > MAX_PROMPT_LENGTH

      provider, model_id = @model_reference.split("|", 2)
      raise ArgumentError, "Choose a video model." if provider.blank? || model_id.blank?

      entry = MediaCatalog.find(operation: "video", model_id:, provider:)
      raise ArgumentError, "This model does not declare video-generation support." unless entry
      unless entry.configured
        missing = entry.missing_configuration.join(", ").presence || "provider configuration"
        raise ArgumentError, "This video model is not runnable yet. Configure #{missing} first."
      end

      run = create_run(entry)
      enqueue_job(run)
      run
    end

    private

    def create_run(entry)
      provider = entry.provider.to_s
      model_id = entry.id.to_s
      run = nil
      @chat.transaction do
        run = @chat.runs.create!(
          project: @chat.project,
          operation: "video",
          status: :queued,
          requested_by: @requested_by,
          input_snapshot_json: {
            "video" => {
              "prompt" => @prompt,
              "provider" => provider,
              "model_id" => model_id
            }
          },
          app_version: ENV.fetch("APP_VERSION", "local"),
          ruby_llm_version: Gem.loaded_specs.fetch("ruby_llm").version.to_s
        )
        run.attempts.create!(sequence: 1, provider:, model_id:, status: :queued)
      end
      run
    end

    def enqueue_job(run)
      job = VideoRunJob.perform_later(run.id)
      unless job.respond_to?(:successfully_enqueued?) && job.successfully_enqueued?
        raise job.enqueue_error if job.respond_to?(:enqueue_error) && job.enqueue_error

        raise ActiveJob::EnqueueError, "Video Run job was not accepted by the queue adapter."
      end
    rescue StandardError => error
      attempt = run.attempts.first
      run.fail_queued_execution!(operation: "video", error:) do
        attempt&.finish!(
          status: :failed,
          finished_at: Time.current,
          error_class: error.class.name,
          error_code: Ai::ErrorClassifier.code(error),
          error_message: Ai::ErrorText.redact(error.message).to_s.truncate(2_000)
        )
      end
      raise ArgumentError, "Video Run could not be queued: #{Ai::ErrorText.redact(error.message)}"
    end
  end
end

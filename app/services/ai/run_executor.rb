module Ai
  class RunExecutor
    def self.enqueue(chat:, project:, prompt:, requested_by: "local_user", provider_tools: [])
      new(chat:, project:, prompt:, requested_by:, provider_tools:).enqueue
    end

    def initialize(chat:, project:, prompt:, requested_by:, provider_tools:)
      @chat = chat
      @project = project
      @prompt = prompt
      @requested_by = requested_by
      @provider_tools = normalize_provider_tools(provider_tools)
    end

    def enqueue
      Ai::ToolRegistry.sync_project!(@project)
      tools_snapshot = Ai::ChatTooling.snapshot(@project)
      tool_options = Ai::ToolExecutionPolicy.snapshot(project: @project, chat: @chat)
      run = @chat.with_lock do
        if @chat.remote_tool_outcome_unknown?
          raise ArgumentError, Chat::REMOTE_TOOL_OUTCOME_UNKNOWN_MESSAGE
        end

        if @chat.runs.where(status: Run::ACTIVE_STATUSES).exists?
          raise ArgumentError, "This chat already has a Run in progress. Wait for it to finish before starting another."
        end

        conversation_context = Ai::ChatContextSnapshot.call(@chat)
        message_high_watermark = @chat.messages.maximum(:id) || 0
        @chat.runs.create!(
          project: @project,
          operation: "chat",
          status: :queued,
          requested_by: @requested_by,
          input_snapshot_json: {
            "prompt" => @prompt,
            "conversation_context" => conversation_context,
            "conversation_message_high_watermark" => message_high_watermark,
            "tools" => tools_snapshot,
            "tool_options" => tool_options,
            "provider_tools" => @provider_tools
          },
          app_version: ENV.fetch("APP_VERSION", "local"),
          ruby_llm_version: Gem.loaded_specs.fetch("ruby_llm").version.to_s
        ).tap do |run|
          run.attempts.create!(
            sequence: 1,
            provider: @chat.provider,
            model_id: @chat.model_id,
            status: :queued
          )
        end
      end

      enqueue_job(run)
      run
    end

    private

    def normalize_provider_tools(provider_tools)
      Array(provider_tools).map(&:to_s).select { |key| key == "web_search" }.uniq
    end

    def enqueue_job(run)
      job = ChatResponseJob.perform_later(run.id)
      return if job&.respond_to?(:successfully_enqueued?) && job.successfully_enqueued?

      raise job.enqueue_error if job&.respond_to?(:enqueue_error) && job.enqueue_error

      raise ActiveJob::EnqueueError, "Chat Run job was not accepted by the queue adapter."
    rescue StandardError => error
      attempt = run.attempts.first
      run.fail_queued_execution!(operation: "chat", error:) do
        attempt&.finish!(
          status: :failed,
          finished_at: Time.current,
          error_class: error.class.name,
          error_code: Ai::ErrorClassifier.code(error),
          error_message: Ai::ErrorText.redact(error.message).to_s.truncate(2_000)
        )
      end
      raise ArgumentError, "Chat Run could not be queued: #{Ai::ErrorText.redact(error.message)}"
    end
  end
end

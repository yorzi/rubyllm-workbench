module Ai
  class RunExecutor
    def self.enqueue(chat:, project:, prompt:, requested_by: "local_user")
      new(chat:, project:, prompt:, requested_by:).enqueue
    end

    def initialize(chat:, project:, prompt:, requested_by:)
      @chat = chat
      @project = project
      @prompt = prompt
      @requested_by = requested_by
    end

    def enqueue
      run = @chat.transaction do
        run = @chat.runs.create!(
          project: @project,
          operation: "chat",
          status: :queued,
          requested_by: @requested_by,
          input_snapshot_json: { "prompt" => @prompt },
          app_version: ENV.fetch("APP_VERSION", "local"),
          ruby_llm_version: Gem.loaded_specs.fetch("ruby_llm").version.to_s
        )
        run.attempts.create!(
          sequence: 1,
          provider: @chat.provider,
          model_id: @chat.model_id,
          status: :queued
        )
        run
      end

      ChatResponseJob.perform_later(run.id)
      run
    end
  end
end

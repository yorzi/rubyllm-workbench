module Ai
  class StructuredExecutor
    def initialize(run_id, run: nil, chat: nil, experiment: nil)
      @run = run || Run.includes(:chat, :attempts, :experiment, :experiment_execution).find(run_id)
      @chat = chat || @run.chat
      @experiment = experiment || @run.experiment
    end

    def call
      return @run if @run.terminal?

      recorder = Ai::AttemptRecorder.new(@run, chat: @chat)
      recorder.start!
      usage_ids_before = @chat.ruby_llm_usages.pluck(:id)
      definition = @experiment.schema_definition
      configure_chat(definition)

      response = @chat.ask(prompt) do |chunk|
        content = chunk.content.to_s
        next if content.blank?

        recorder.observe!(content)
        latest_assistant_message&.broadcast_append_chunk(content)
      end

      parsed = parse_and_validate!(response, definition)
      @run.transaction do
        artifact = @run.artifacts.create!(
          attempt: @run.attempts.order(:sequence, :id).last,
          kind: "json",
          name: definition.name,
          content_text: JSON.pretty_generate(parsed),
          content_json: parsed,
          metadata_json: {
            "schema_name" => definition.name,
            "schema_validation" => "valid",
            "experiment_revision" => @experiment.revision
          }
        )
        recorder.succeed!(
          response,
          usage_ids_before: usage_ids_before,
          result_summary: {
            "schema_name" => definition.name,
            "schema_validation" => "valid",
            "artifact_id" => artifact.id,
            "structured_output" => parsed
          }
        )
      end

      @run
    rescue StandardError => error
      recorder&.fail!(error, usage_ids_before: usage_ids_before || [])
      @run
    ensure
      @run.experiment_execution&.refresh_status!
    end

    private

    def prompt
      @run.input_snapshot.fetch("experiment").fetch("input_prompt")
    end

    def configure_chat(definition)
      system_prompt = @run.input_snapshot.dig("experiment", "system_prompt")
      @chat.with_instructions(system_prompt, persist: false) if system_prompt.present?
      @chat.with_schema(definition.payload)

      options = @run.input_snapshot.dig("experiment", "generation_options") || {}
      @chat.with_temperature(options["temperature"]) if options["temperature"]
      @chat.with_max_output_tokens(options["max_output_tokens"]) if options["max_output_tokens"]
    end

    def parse_and_validate!(response, definition)
      parsed = JSON.parse(response.content.to_s)
      problems = Ai::SchemaValidator.new(definition).errors_for(parsed)
      raise Ai::StructuredOutputError, problems if problems.any?

      parsed
    rescue JSON::ParserError => error
      raise Ai::StructuredOutputError, [ "$: invalid JSON: #{error.message}" ]
    end

    def latest_assistant_message
      @chat.messages.reload.reverse.find { |message| message.role.to_s == "assistant" }
    end
  end
end

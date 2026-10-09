module Ai
  module Knowledge
    class GroundedAnswerExecutor
      class ExecutionStopped < StandardError
        def code
          "execution_stopped"
        end
      end

      def initialize(run_id, chat: nil)
        @run = Run.includes(:project, :chat, :attempts).find(run_id)
        @chat = chat || @run.chat
      end

      def call
        return @run unless @run.claim_queued_execution!(operation: GroundedAnswer::OPERATION)

        snapshot = @run.input_snapshot.fetch("grounded_answer")
        EvidenceSnapshot.verify_current!(snapshot, project: @run.project)
        if snapshot.fetch("evidence").empty?
          persist_result(GroundedResponse.empty_evidence_response, model_request: false)
          return @run
        end

        recorder = Ai::AttemptRecorder.new(@run, chat: @chat)
        started = @run.with_lock do
          next false unless @run.running?

          recorder.start!
        end
        return @run unless started

        target = @run.input_snapshot.fetch("target")
        unless @chat.model_id == target.fetch("model_id") && @chat.provider.to_s == target.fetch("provider")
          raise ArgumentError, "The answer Chat model changed after enqueueing. Create a new Run."
        end
        unless @chat.messages.reload.empty?
          raise Ai::ChatContextSnapshot::ContextChanged, "The answer Chat acquired history after enqueueing. No provider request was made; create a new Run."
        end
        usage_ids_before = @chat.ruby_llm_usages.pluck(:id)
        definition = Ai::SchemaDefinition.parse(snapshot.fetch("schema_json"))
        @chat.with_instructions(snapshot.fetch("instructions"), persist: false)
        @chat.with_schema(definition.payload)
        @chat.with_max_output_tokens(snapshot.fetch("generation_options").fetch("max_output_tokens"))
        @chat.before_request do |payload|
          raise ExecutionStopped, "This answer Run is no longer running." unless @run.reload.running?
          unless (payload[:model] || payload["model"]).to_s == target.fetch("model_id")
            raise ArgumentError, "The provider request model differs from the frozen target."
          end
        end
        return @run unless @run.reload.running?

        response = Ai::ExecutionContext.with(run_id: @run.id, attempt_id: @run.attempts.first.id) do
          @chat.ask(JSON.generate(snapshot.slice("question", "evidence")))
        end
        parsed = GroundedResponse.parse!(response.content, snapshot:)
        persist_result(parsed, model_request: true, recorder:, response:, usage_ids_before:)
        @run
      rescue StandardError => error
        @run.finish_running_execution!(operation: GroundedAnswer::OPERATION, status: :failed, error:) do
          if recorder
            recorder.fail_step!(error, usage_ids_before: usage_ids_before || [])
          else
            @run.attempts.first&.finish!(
              status: :failed, finished_at: Time.current, error_class: error.class.name,
              error_code: Ai::ErrorClassifier.code(error), error_message: Ai::ErrorText.redact(error.message).to_s.truncate(2_000)
            )
          end
        end
        @run
      end

      private

      def persist_result(parsed, model_request:, recorder: nil, response: nil, usage_ids_before: [])
        @run.finish_running_execution!(operation: GroundedAnswer::OPERATION, status: :succeeded) do
          recorder&.finish_step!(response, usage_ids_before:)
          artifact = @run.artifacts.create!(
            attempt: @run.attempts.first, kind: "json", name: "grounded_answer",
            content_json: parsed, content_text: JSON.pretty_generate(parsed),
            metadata_json: {
              "report_type" => GroundedAnswer::OPERATION, "citation_validation" => "valid",
              "corpus_checksum" => @run.input_snapshot.dig("grounded_answer", "corpus_checksum"),
              "model_request" => model_request
            }
          )
          summary = { "artifact_id" => artifact.id, "answer_status" => parsed.fetch("status"),
            "citation_validation" => "valid", "model_request" => model_request }
          recorder ? recorder.success_summary(response, result_summary: summary) : summary
        end
      end
    end
  end
end

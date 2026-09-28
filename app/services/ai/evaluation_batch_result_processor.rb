module Ai
  class EvaluationBatchResultProcessor
    class BatchRequestError < StandardError
      attr_reader :code

      def initialize(message, code: "provider_batch_request_failed")
        @code = code
        super(message)
      end
    end

    def initialize(case_result:, message:, batch_status:)
      @case_result = case_result
      @message = message
      @batch_status = batch_status.to_s
    end

    def call
      run = @case_result.run
      if run.terminal?
        @case_result.evaluate_run! if @case_result.running?
        return @case_result
      end
      return @case_result unless @case_result.running?

      unless @message
        code = @batch_status == "cancelled" ? "provider_batch_cancelled" : "provider_batch_request_failed"
        raise BatchRequestError.new("Provider batch returned no response for this case (#{@batch_status.presence || 'unknown'}).", code:)
      end

      finish_success!(run)
    rescue StandardError => error
      finish_failure!(error)
      @case_result.reload.evaluate_run! if @case_result.reload.running? && @case_result.run&.terminal?
      @case_result
    end

    private

    def finish_success!(run)
      experiment = run.input_snapshot.fetch("experiment")
      definition = Ai::SchemaDefinition.parse(experiment.fetch("schema"))
      parsed = JSON.parse(@message.content.to_s)
      problems = Ai::SchemaValidator.new(definition).errors_for(parsed)
      raise Ai::StructuredOutputError, problems if problems.any?

      attempt = run.attempts.order(:sequence, :id).last
      recorder = Ai::AttemptRecorder.new(run, attempt:, chat: run.chat)
      run.finish_running_execution!(operation: "structured", status: :succeeded) do
        recorder.finish_step!(@message, usage_ids_before: [])
        update_batch_duration!(attempt)
        artifact = run.artifacts.create!(
          attempt:,
          kind: "json",
          name: definition.name,
          content_text: JSON.pretty_generate(parsed),
          content_json: parsed,
          metadata_json: {
            "schema_name" => definition.name,
            "schema_validation" => "valid",
            "experiment_revision" => experiment.fetch("revision"),
            "execution_mode" => "provider_batch"
          }
        )
        recorder.success_summary(
          @message,
          result_summary: {
            "schema_name" => definition.name,
            "schema_validation" => "valid",
            "artifact_id" => artifact.id,
            "structured_output" => parsed,
            "evaluation_execution_mode" => "provider_batch"
          }
        )
      end

      @case_result.reload.evaluate_run! if run.reload.terminal?
      @case_result
    end

    def finish_failure!(error)
      run = @case_result.run
      return unless run&.running?

      attempt = run.attempts.order(:sequence, :id).last
      recorder = Ai::AttemptRecorder.new(run, attempt:, chat: run.chat)
      run.finish_running_execution!(operation: "structured", status: :failed, error:) do
        recorder.fail_step!(error, usage_ids_before: [])
        update_batch_duration!(attempt)
        { "evaluation_execution_mode" => "provider_batch" }
      end
    end

    def update_batch_duration!(attempt)
      return unless attempt&.started_at

      attempt.update!(duration_ms: ((Time.current - attempt.started_at) * 1_000).round)
    end
  end
end

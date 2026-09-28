module Ai
  class EvaluationCaseJudgeEnqueuer
    def self.call(case_result)
      judgment = create_judgment(case_result)
      enqueue_existing(judgment) if judgment
      judgment
    end

    def self.enqueue_existing(judgment)
      EvaluationJobEnqueuer.call(EvaluationCaseJudgeJob, judgment.id)
      judgment.clear_enqueue_rejection!
      judgment
    rescue StandardError => error
      judgment.record_enqueue_rejection!(error)
      judgment
    end

    def self.create_judgment(case_result)
      judgment = nil
      case_result.with_lock do
        case_result.reload
        next unless case_result.completed? && case_result.rubric.any?
        next if case_result.evaluation_case_judgment

        execution = case_result.evaluation_execution
        configuration = execution.input_snapshot["judge"]
        next unless configuration.is_a?(Hash)
        next unless case_result.run&.succeeded?

        rubric = case_result.rubric
        input = case_result.input_json
        actual_output = case_result.actual_output_json
        next if actual_output.nil?

        judgment_input = EvaluationRubricJudge.judgment_input_snapshot(
          configuration:,
          rubric:,
          input:,
          actual_output:
        )
        experiment_snapshot = EvaluationRubricJudge.experiment_snapshot(
          configuration:,
          rubric:,
          input:,
          actual_output:
        )
        target = configuration.fetch("target")
        chat = case_result.evaluation_dataset_revision.evaluation_dataset.project.chats.create!(
          title: "Rubric judge · #{case_result.case_key}",
          model_id: target.fetch("model_id"),
          provider: target.fetch("provider")
        )
        run = chat.runs.create!(
          project: chat.project,
          operation: "structured",
          status: :queued,
          requested_by: execution.requested_by,
          input_snapshot_json: {
            "experiment" => experiment_snapshot,
            "evaluation_judge" => {
              "prompt_version" => configuration.fetch("prompt_version"),
              "schema_version" => configuration.fetch("schema_version"),
              "target" => target.deep_dup
            },
            "target" => target.deep_dup
          },
          app_version: ENV.fetch("APP_VERSION", "local"),
          ruby_llm_version: Gem.loaded_specs.fetch("ruby_llm").version.to_s
        )
        run.attempts.create!(sequence: 1, provider: target.fetch("provider"), model_id: target.fetch("model_id"), status: :queued)
        judgment = case_result.create_evaluation_case_judgment!(
          run:,
          status: :queued,
          input_snapshot_json: judgment_input
        )
      end
      judgment
    end
    private_class_method :create_judgment
  end
end

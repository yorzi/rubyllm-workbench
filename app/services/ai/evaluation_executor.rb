module Ai
  class EvaluationExecutor
    ComparisonResult = Data.define(:comparison, :queued_count, :rejected_count)
    ModelTarget = Data.define(:provider, :model_id, :name, :capabilities)

    def self.enqueue(dataset:, experiment:, model_reference:, execution_mode: "individual", judge_model_reference: nil, requested_by: "local_user", model_catalog: Ai::ModelCatalog.new)
      new(dataset:, experiment:, execution_mode:, requested_by:, model_catalog:).enqueue(model_reference:, judge_model_reference:)
    end

    def self.enqueue_comparison(dataset:, experiment:, model_references:, judge_model_reference: nil, requested_by: "local_user", model_catalog: Ai::ModelCatalog.new)
      new(dataset:, experiment:, execution_mode: "individual", requested_by:, model_catalog:).enqueue_comparison(model_references:, judge_model_reference:)
    end

    def initialize(dataset:, experiment:, execution_mode:, requested_by:, model_catalog:)
      @dataset = dataset
      @experiment = experiment
      @execution_mode = execution_mode.to_s
      @requested_by = requested_by
      @model_catalog = model_catalog
    end

    def enqueue(model_reference:, judge_model_reference: nil)
      validate_scope_and_mode!
      revision, dataset_snapshot, experiment_snapshot = frozen_inputs
      model = configured_model(model_reference)
      judge_configuration = judge_configuration_for(judge_model_reference, dataset_snapshot)
      validate_batch_support!(model) if @execution_mode == "provider_batch"

      execution = nil
      @dataset.project.transaction do
        execution = create_execution!(
          revision:,
          dataset_snapshot:,
          experiment_snapshot:,
          model:,
          judge_configuration:,
          comparison: nil
        )
      end

      enqueue_execution!(execution)
      execution
    end

    def enqueue_comparison(model_references:, judge_model_reference: nil)
      validate_scope_and_mode!
      raise ArgumentError, "Model comparisons currently use individual execution mode." unless @execution_mode == "individual"

      references = Array(model_references).map(&:to_s).reject(&:blank?)
      unless references.size.between?(EvaluationComparison::MIN_MODELS, EvaluationComparison::MAX_MODELS)
        raise ArgumentError,
          "Choose between #{EvaluationComparison::MIN_MODELS} and #{EvaluationComparison::MAX_MODELS} configured structured-output models to compare."
      end
      raise ArgumentError, "Choose each provider/model only once." unless references.uniq.size == references.size

      models = references.map { |reference| configured_model(reference) }
      revision, dataset_snapshot, experiment_snapshot = frozen_inputs
      judge_configuration = judge_configuration_for(judge_model_reference, dataset_snapshot)
      model_targets = models.map { |model| target_snapshot(model) }
      comparison = nil
      executions = []

      @dataset.project.transaction do
        comparison = @dataset.project.evaluation_comparisons.create!(
          evaluation_dataset_revision: revision,
          experiment: @experiment,
          dataset_snapshot_json: dataset_snapshot,
          experiment_snapshot_json: experiment_snapshot,
          model_targets_json: model_targets,
          requested_by: @requested_by
        )
        models.each do |model|
          executions << create_execution!(
            revision:,
            dataset_snapshot:,
            experiment_snapshot:,
            model:,
            judge_configuration:,
            comparison:
          )
        end
      end

      queued_count = 0
      rejected_count = 0
      executions.each do |execution|
        result = enqueue_execution!(execution, raise_on_rejection: false)
        queued_count += result.fetch(:queued_count)
        rejected_count += result.fetch(:rejected_count)
      end

      ComparisonResult.new(comparison, queued_count, rejected_count)
    end

    private

    def validate_scope_and_mode!
      raise ArgumentError, "The dataset and experiment must belong to the same Project." unless @dataset.project_id == @experiment.project_id
      raise ArgumentError, "Experiment must be runnable." unless @experiment.runnable?
      raise ArgumentError, "Choose an evaluation execution mode." unless EvaluationExecution::EXECUTION_MODES.include?(@execution_mode)
    end

    def frozen_inputs
      revision = @dataset.current_revision_record
      raise ArgumentError, "Evaluation dataset has no valid revision." unless revision

      dataset_snapshot = {
        "id" => @dataset.id,
        "name" => @dataset.name,
        "revision" => revision.revision,
        "cases" => revision.cases.map do |evaluation_case|
          evaluation_case.merge(
            "attachments" => attachment_snapshot(revision, evaluation_case.fetch("key"))
          )
        end
      }
      [ revision, dataset_snapshot, @experiment.snapshot ]
    end

    def configured_model(model_reference)
      provider, model_id = model_reference.to_s.split("|", 2)
      raise ArgumentError, "Choose one configured structured-output model." if provider.blank? || model_id.blank?

      entry = @model_catalog.entries(capability: "structured_output", configured: "true").find do |candidate|
        candidate.provider == provider && candidate.id == model_id
      end
      raise ArgumentError, "Choose one configured structured-output model." unless entry&.interactive?

      @model_catalog.find!(model_id, provider:)
    end

    def validate_batch_support!(model)
      return if model.supports?(:batch)

      raise ArgumentError, "Provider Batch requires one configured model that supports both structured output and batch requests."
    end

    def create_execution!(revision:, dataset_snapshot:, experiment_snapshot:, model:, judge_configuration:, comparison:)
      execution = @dataset.project.evaluation_executions.create!(
        evaluation_comparison: comparison,
        evaluation_dataset_revision: revision,
        experiment: @experiment,
        provider: model.provider,
        model_id: model.id,
        execution_mode: @execution_mode,
        status: :queued,
        case_count: dataset_snapshot.fetch("cases").size,
        requested_by: @requested_by,
        input_snapshot_json: {
          "dataset" => dataset_snapshot,
          "experiment" => experiment_snapshot,
          "target" => target_snapshot(model).merge("execution_mode" => @execution_mode),
          "judge" => judge_configuration
        }
      )

      dataset_snapshot.fetch("cases").each_with_index do |evaluation_case, position|
        create_case_run!(execution:, evaluation_case:, position:, revision:, experiment_snapshot:, model:)
      end
      execution
    end

    def create_case_run!(execution:, evaluation_case:, position:, revision:, experiment_snapshot:, model:)
      case_result = execution.evaluation_case_results.create!(
        evaluation_dataset_revision: revision,
        case_key: evaluation_case.fetch("key"),
        case_position: position,
        input_json: evaluation_case.fetch("input"),
        expected_output_json: evaluation_case.fetch("expected_output"),
        rubric_json: evaluation_case.fetch("rubric", []),
        status: :queued
      )
      chat = @dataset.project.chats.create!(
        title: "#{@dataset.name} · #{evaluation_case.fetch('key')}",
        model_id: model.id,
        provider: model.provider
      )
      case_experiment_snapshot = experiment_snapshot.deep_dup
      case_experiment_snapshot["input_prompt"] = evaluation_prompt(
        experiment_snapshot.fetch("input_prompt"),
        evaluation_case.fetch("input")
      )
      run = chat.runs.create!(
        project: @dataset.project,
        experiment: @experiment,
        operation: "structured",
        status: :queued,
        requested_by: @requested_by,
        input_snapshot_json: {
          "experiment" => case_experiment_snapshot,
          "evaluation" => {
            "execution_id" => execution.id,
            "comparison_id" => execution.evaluation_comparison_id,
            "case_result_id" => case_result.id,
            "dataset_revision" => revision.revision,
            "case_key" => evaluation_case.fetch("key"),
            "tags" => evaluation_case.fetch("tags", []),
            "rubric" => evaluation_case.fetch("rubric", []),
            "attachments" => evaluation_case.fetch("attachments", []),
            "input" => evaluation_case.fetch("input"),
            "expected_output" => evaluation_case.fetch("expected_output")
          },
          "target" => execution.input_snapshot.fetch("target")
        },
        app_version: ENV.fetch("APP_VERSION", "local"),
        ruby_llm_version: Gem.loaded_specs.fetch("ruby_llm").version.to_s
      )
      run.attempts.create!(sequence: 1, provider: model.provider, model_id: model.id, status: :queued)
      case_result.update!(run:)
    end

    def enqueue_execution!(execution, raise_on_rejection: true)
      return enqueue_provider_batch!(execution) if execution.provider_batch?

      queued_count = 0
      rejected_count = 0
      execution.evaluation_case_results.order(:case_position, :id).each do |case_result|
        Ai::EvaluationJobEnqueuer.call(EvaluationCaseJob, case_result.id)
        queued_count += 1
      rescue StandardError => error
        case_result.record_enqueue_rejection!(error)
        rejected_count += 1
      end

      if raise_on_rejection && rejected_count.positive?
        raise ArgumentError,
          "Queue accepted #{queued_count} evaluation case job(s) and rejected #{rejected_count}; rejected cases remain queued for retry."
      end
      { queued_count:, rejected_count: }
    end

    def enqueue_provider_batch!(execution)
      Ai::EvaluationJobEnqueuer.call(EvaluationBatchSubmissionJob, execution.id)
      { queued_count: 1, rejected_count: 0 }
    rescue StandardError => error
      failed_before_start = execution.fail_queued_provider_batch_enqueue!(error:)
      if failed_before_start
        raise ArgumentError, "Provider Batch submission could not be queued; local cases were marked failed before any provider request."
      end

      raise ArgumentError, "Provider Batch queue acceptance was not confirmed; inspect Evaluation ##{execution.id} before retrying."
    end

    def target_snapshot(model)
      {
        "provider" => model.provider,
        "model_id" => model.id,
        "name" => model.name,
        "capabilities" => model.capabilities.map(&:to_s)
      }
    end

    def judge_configuration_for(model_reference, dataset_snapshot)
      return nil if model_reference.blank?
      unless dataset_snapshot.fetch("cases").any? { |evaluation_case| Array(evaluation_case["rubric"]).any? }
        raise ArgumentError, "An automated rubric judge requires at least one case with a rubric."
      end

      model = configured_model(model_reference)
      Ai::EvaluationRubricJudge.configuration_snapshot(model)
    end

    def attachment_snapshot(revision, case_key)
      revision.case_attachments_for(case_key).map do |attachment|
        blob = attachment.file.blob
        {
          "id" => attachment.id,
          "filename" => attachment.file.filename.to_s,
          "content_type" => blob.content_type,
          "byte_size" => blob.byte_size,
          "checksum" => blob.checksum
        }
      end
    end

    def evaluation_prompt(base_prompt, input)
      "#{base_prompt}\n\nEvaluation case input (JSON):\n#{JSON.pretty_generate(input)}"
    end
  end
end

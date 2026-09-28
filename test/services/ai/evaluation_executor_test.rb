require "test_helper"
require "ostruct"

class Ai::EvaluationExecutorTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  class AcceptedEnqueue
    def successfully_enqueued?
      true
    end
  end

  setup do
    @project = create_project(name: "Evaluation project")
    @experiment = @project.experiments.create!(
      name: "Answer schema",
      input_prompt: "Answer the question.",
      schema_json: JSON.parse(Ai::SchemaDefinition.default_json)
    )
    @models = RubyLLM.models.chat_models.all.select do |candidate|
      candidate.provider.to_s == "openrouter" && candidate.supports?(:structured_output) && !candidate.id.to_s.end_with?(":batch")
    end.first(5)
    @model = @models.first
    skip "RubyLLM registry has no structured-output OpenRouter model" unless @model
    @catalog = Ai::ModelCatalog.new(
      models: @models,
      config: OpenStruct.new(openrouter_api_key: "test-only-key")
    )
    @dataset = @project.evaluation_datasets.create!(name: "Answer cases")
    @dataset.create_revision!(cases)
  end

  test "queues one ordinary structured Run per immutable case and freezes both inputs" do
    execution = nil
    with_provider_configuration(@model.provider) do
      assert_enqueued_jobs 2, only: EvaluationCaseJob do
        execution = Ai::EvaluationExecutor.enqueue(
          dataset: @dataset,
          experiment: @experiment,
          model_reference: "#{@model.provider}|#{@model.id}",
          model_catalog: @catalog
        )
      end
    end

    original_revision = execution.evaluation_dataset_revision
    runs = execution.runs.includes(:evaluation_case_result, :attempts).to_a
    assert_equal 2, runs.size
    assert runs.all? { |run| run.operation == "structured" && run.queued? && run.attempts.one? }
    assert_equal 2, execution.evaluation_case_results.size
    assert_equal "What is 2 + 2?", runs.first.input_snapshot.dig("evaluation", "input", "question")
    assert_equal [ "tag-only-sentinel" ], runs.first.input_snapshot.dig("evaluation", "tags")
    frozen_rubric = cases.first.fetch("rubric")
    assert_equal frozen_rubric, runs.first.evaluation_case_result.rubric
    assert_equal frozen_rubric, runs.first.input_snapshot.dig("evaluation", "rubric")
    refute_includes runs.first.input_snapshot.dig("experiment", "input_prompt"), "tag-only-sentinel"
    refute_includes runs.first.input_snapshot.dig("experiment", "input_prompt"), "rubric-only-secret"
    refute_includes runs.first.input_snapshot.dig("experiment", "input_prompt"), "accuracy"
    assert_nil runs.first.input_snapshot.dig("experiment", "input_prompt").match(/Expected output/)

    @dataset.create_revision!([
      cases.first.merge(
        "key" => "changed",
        "tags" => [ "later-tag" ],
        "rubric" => [ { "key" => "accuracy", "description" => "Later rubric revision" } ]
      )
    ])
    @experiment.update!(input_prompt: "A later prompt revision.")

    assert_equal 1, original_revision.revision
    assert_equal "case-add", original_revision.cases.first.fetch("key")
    assert_equal [ "tag-only-sentinel" ], original_revision.cases.first.fetch("tags")
    assert_equal 1, execution.input_snapshot.dig("dataset", "revision")
    assert_equal [ "tag-only-sentinel" ], execution.input_snapshot.dig("dataset", "cases").first.fetch("tags")
    assert_equal frozen_rubric, runs.first.evaluation_case_result.reload.rubric
    assert_equal frozen_rubric, runs.first.input_snapshot.dig("evaluation", "rubric")
    assert_equal [ "later-tag" ], @dataset.reload.current_revision_record.cases.first.fetch("tags")
    assert_includes runs.first.input_snapshot.dig("experiment", "input_prompt"), "Answer the question."
    refute_includes runs.first.input_snapshot.dig("experiment", "input_prompt"), "A later prompt revision."
  end

  test "one model is required and only configured structured targets are accepted" do
    assert_raises(ArgumentError) do
      Ai::EvaluationExecutor.enqueue(
        dataset: @dataset,
        experiment: @experiment,
        model_reference: "openrouter|does-not-exist",
        model_catalog: @catalog
      )
    end
    assert_empty @dataset.evaluation_executions
  end

  test "queues a frozen multi-model comparison with one Run and Attempt per case and target" do
    skip "RubyLLM registry has fewer than two structured-output OpenRouter models" if @models.size < 2
    references = @models.first(2).map { |model| "#{model.provider}|#{model.id}" }
    comparison = nil

    with_provider_configuration(@model.provider) do
      assert_enqueued_jobs 4, only: EvaluationCaseJob do
        comparison = Ai::EvaluationExecutor.enqueue_comparison(
          dataset: @dataset,
          experiment: @experiment,
          model_references: references,
          model_catalog: @catalog
        ).comparison
      end
    end

    executions = comparison.evaluation_executions.includes(evaluation_case_results: [ :run ]).to_a
    assert_equal 2, executions.size
    assert_equal references.sort, executions.map { |execution| "#{execution.provider}|#{execution.model_id}" }.sort
    assert_equal [ @dataset.current_revision_record.id ], executions.map(&:evaluation_dataset_revision_id).uniq
    assert_equal 4, executions.sum { |execution| execution.evaluation_case_results.size }
    assert executions.all? { |execution| execution.individual? && execution.queued? }
    assert executions.flat_map { |execution| execution.runs.includes(:attempts).to_a }.all? do |run|
      run.queued? && run.operation == "structured" && run.attempts.one? && run.attempts.first.queued?
    end
    assert_equal executions.first.input_snapshot.fetch("dataset"), executions.second.input_snapshot.fetch("dataset")
    assert_equal executions.first.input_snapshot.fetch("experiment"), executions.second.input_snapshot.fetch("experiment")
    targets = executions.map do |execution|
      [ execution.input_snapshot.dig("target", "provider"), execution.input_snapshot.dig("target", "model_id") ]
    end
    assert_equal 2, targets.uniq.size

    original_dataset_snapshot = comparison.dataset_snapshot
    original_experiment_snapshot = comparison.experiment_snapshot
    @dataset.create_revision!([ cases.first.merge("key" => "changed") ])
    @experiment.update!(input_prompt: "A later prompt revision.")
    assert_equal original_dataset_snapshot, comparison.reload.dataset_snapshot
    assert_equal original_experiment_snapshot, comparison.experiment_snapshot
    assert_raises(ActiveRecord::RecordNotSaved) { comparison.update!(requested_by: "changed") }

    comparison_id = comparison.id
    @project.destroy!
    refute EvaluationComparison.exists?(comparison_id)
    refute EvaluationExecution.exists?(evaluation_comparison_id: comparison_id)
  end

  test "rejects duplicate and out-of-range comparison targets before creating records" do
    reference = "#{@model.provider}|#{@model.id}"

    assert_raises(ArgumentError) do
      Ai::EvaluationExecutor.enqueue_comparison(
        dataset: @dataset,
        experiment: @experiment,
        model_references: [ reference, reference ],
        model_catalog: @catalog
      )
    end
    assert_empty @dataset.evaluation_comparisons
    assert_empty @dataset.evaluation_executions
  end

  test "keeps rejected comparison case jobs visible and retryable" do
    skip "RubyLLM registry has fewer than two structured-output OpenRouter models" if @models.size < 2
    references = @models.first(2).map { |model| "#{model.provider}|#{model.id}" }
    enqueue_results = [ AcceptedEnqueue.new, false, AcceptedEnqueue.new, AcceptedEnqueue.new ]
    comparison = nil

    with_provider_configuration(@model.provider) do
      with_singleton_method_stub(EvaluationCaseJob, :perform_later, ->(*) { enqueue_results.shift }) do
        comparison = Ai::EvaluationExecutor.enqueue_comparison(
          dataset: @dataset,
          experiment: @experiment,
          model_references: references,
          model_catalog: @catalog
        )
      end
    end

    assert_equal 3, comparison.queued_count
    assert_equal 1, comparison.rejected_count
    failed_execution = comparison.comparison.evaluation_executions.find do |execution|
      execution.evaluation_case_results.any? { |result| result.error_summary.present? }
    end
    rejected_case = failed_execution.evaluation_case_results.find { |result| result.error_summary.present? }
    assert rejected_case.queued?
    assert rejected_case.run.queued?
    assert_equal [ "queued" ], rejected_case.run.attempts.map(&:status)
    assert_includes rejected_case.error_summary, "Queue adapter did not accept this case"

    with_singleton_method_stub(EvaluationCaseJob, :perform_later, ->(*) { AcceptedEnqueue.new }) do
      result = failed_execution.resume_unstarted!
      assert_equal 2, result.queued_count
      assert_equal 0, result.rejected_count
    end
    assert_nil rejected_case.reload.error_summary
  end

  test "persisted dataset revisions reject edits while remaining deletable with their Project" do
    revision = @dataset.current_revision_record

    assert_raises(ActiveRecord::RecordNotSaved) do
      revision.update!(cases_json: cases.reverse)
    end

    assert_equal "case-add", revision.reload.cases.first.fetch("key")
  end

  test "case result delivery claim prevents duplicate attempts and exact comparison remains per case" do
    with_provider_configuration(@model.provider) do
      execution = Ai::EvaluationExecutor.enqueue(
        dataset: @dataset,
        experiment: @experiment,
        model_reference: "#{@model.provider}|#{@model.id}",
        model_catalog: @catalog
      )
      result = execution.evaluation_case_results.first
      run = result.run

      assert result.claim!
      refute result.reload.claim!
      run.update!(
        status: :succeeded,
        result_summary_json: { "structured_output" => result.expected_output_json }
      )
      result.evaluate_run!

      assert result.reload.completed?
      assert result.passed?
      assert_equal cases.first.fetch("rubric"), result.rubric
      assert_equal 1, execution.reload.passed_count

      mismatch = execution.evaluation_case_results.where.not(id: result.id).first
      assert mismatch.claim!
      mismatch.run.update!(status: :succeeded, result_summary_json: { "structured_output" => { "summary" => "wrong", "confidence" => 0 } })
      mismatch.evaluate_run!

      assert execution.reload.completed?
      assert_equal 1, execution.passed_count
      assert_equal 1, execution.failed_count
      assert_equal false, mismatch.reload.passed
    end
  end

  test "resume only queues case results whose provider Run has not started" do
    execution = with_provider_configuration(@model.provider) do
      Ai::EvaluationExecutor.enqueue(
        dataset: @dataset,
        experiment: @experiment,
        model_reference: "#{@model.provider}|#{@model.id}",
        model_catalog: @catalog
      )
    end
    started_result = execution.evaluation_case_results.first
    assert started_result.claim!

    assert_equal 1, execution.resume_unstarted!.queued_count
    assert_equal 1, execution.evaluation_case_results.queued.count
    assert_equal 1, execution.evaluation_case_results.running.count
  end

  test "records rejected individual job enqueues as retryable and clears them after requeue" do
    enqueue_results = [ AcceptedEnqueue.new, false ]
    with_provider_configuration(@model.provider) do
      with_singleton_method_stub(EvaluationCaseJob, :perform_later, ->(*) { enqueue_results.shift }) do
        error = assert_raises(ArgumentError) do
          Ai::EvaluationExecutor.enqueue(
            dataset: @dataset,
            experiment: @experiment,
            model_reference: "#{@model.provider}|#{@model.id}",
            model_catalog: @catalog
          )
        end
        assert_includes error.message, "rejected 1"
      end
    end

    execution = @dataset.evaluation_executions.last
    results = execution.evaluation_case_results.order(:case_position).to_a
    assert execution.queued?
    assert_equal [ "queued", "queued" ], results.map(&:status)
    assert_nil results.first.error_summary
    assert_includes results.second.error_summary, "Queue adapter did not accept this case"
    assert results.all? { |result| result.run.queued? && result.run.attempts.all?(&:queued?) }

    with_singleton_method_stub(EvaluationCaseJob, :perform_later, ->(*) { AcceptedEnqueue.new }) do
      resumed = execution.resume_unstarted!
      assert_equal 2, resumed.queued_count
      assert_equal 0, resumed.rejected_count
    end
    assert_nil results.second.reload.error_summary
  end

  test "fails a queued provider batch locally when its submission job is rejected" do
    batch_model = RubyLLM.models.chat_models.all.find do |candidate|
      candidate.supports?(:structured_output) && candidate.supports?(:batch) && !candidate.id.to_s.end_with?(":batch")
    end
    skip "RubyLLM registry has no structured-output model with provider Batch support" unless batch_model

    requirements = RubyLLM::Provider.resolve(batch_model.provider).configuration_requirements
    catalog = Ai::ModelCatalog.new(
      models: [ batch_model ],
      config: OpenStruct.new(requirements.to_h { |requirement| [ requirement, "test-only-key" ] })
    )
    with_provider_configuration(batch_model.provider) do
      with_singleton_method_stub(EvaluationBatchSubmissionJob, :perform_later, ->(*) { false }) do
        error = assert_raises(ArgumentError) do
          Ai::EvaluationExecutor.enqueue(
            dataset: @dataset,
            experiment: @experiment,
            model_reference: "#{batch_model.provider}|#{batch_model.id}",
            execution_mode: "provider_batch",
            model_catalog: catalog
          )
        end
        assert_includes error.message, "marked failed"
      end
    end

    execution = @dataset.evaluation_executions.last
    assert execution.failed?
    assert execution.provider_batch_error.present?
    assert_nil execution.provider_batch_id
    refute execution.submission_unknown?
    assert execution.evaluation_case_results.all? { |result| result.failed? && result.run.failed? && result.run.attempts.first.failed? }
  end

  private

  def with_singleton_method_stub(object, name, implementation)
    original = object.method(name)
    object.define_singleton_method(name, &implementation)
    yield
  ensure
    object.define_singleton_method(name, original)
  end

  def cases
    [
      {
        "key" => "case-add",
        "tags" => [ "tag-only-sentinel" ],
        "rubric" => [
          { "key" => "accuracy", "description" => "rubric-only-secret: factual accuracy" },
          { "key" => "completeness", "description" => "Includes the requested detail" }
        ],
        "input" => { "question" => "What is 2 + 2?" },
        "expected_output" => { "summary" => "4", "confidence" => 1 }
      },
      { "key" => "case-subtract", "input" => { "question" => "What is 8 - 3?" }, "expected_output" => { "summary" => "5", "confidence" => 1 } }
    ]
  end
end

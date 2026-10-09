require "test_helper"

class DemoTourTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "builds an explorable synthetic tour without calling a provider" do
    project = Workbench::DemoTour.build!

    assert_equal "demo-tour", project.slug
    statuses = project.runs.pluck(:status).tally
    assert_equal({ "succeeded" => 8, "failed" => 1 }, statuses)
    assert project.runs.all? { |run| run.requested_by == "demo" }
    assert project.runs.find_by(operation: "agent").artifacts.exists?(kind: "report")
    assert_operator project.knowledge_collections.first.knowledge_chunks.count, :>=, 3

    get project_path(project)
    assert_response :success
    project.runs.each do |run|
      get run_path(run)
      assert_response :success, "Run ##{run.id} (#{run.operation}) inspector failed"
    end
    collection = project.knowledge_collections.first
    get project_knowledge_collection_path(project, collection), params: { q: "database jobs" }
    assert_response :success
    assert_includes response.body, "Solid Queue"
    get project_evaluation_dataset_path(project, project.evaluation_datasets.first)
    assert_response :success
  end

  test "synthetic comparison keeps transport, schema validity and exact equality separate" do
    project = nil
    assert_enqueued_jobs 0, only: [ EvaluationCaseJob, EvaluationCaseJudgeJob, EvaluationBatchSubmissionJob ] do
      project = Workbench::DemoTour.build!
    end
    dataset = project.evaluation_datasets.first
    comparison = dataset.evaluation_comparisons.first
    executions = comparison.evaluation_executions.includes(evaluation_case_results: { run: :attempts }).to_a

    assert_includes dataset.description, "Synthetic comparison"
    assert_equal "demo", comparison.requested_by
    assert_equal 2, comparison.model_targets.size
    assert_equal 2, executions.size
    assert_equal [ 2, 1 ], executions.map(&:passed_count)
    assert_equal [ 0, 1 ], executions.map(&:failed_count)

    executions.each do |execution|
      assert execution.completed?
      assert_equal "demo", execution.requested_by
      assert_equal comparison.dataset_snapshot, execution.input_snapshot.fetch("dataset")
      assert_equal comparison.experiment_snapshot, execution.input_snapshot.fetch("experiment")
      assert_equal Workbench::DemoTour::SYNTHETIC_NOTE, execution.input_snapshot.fetch("demo_note")
      metrics = Ai::EvaluationMetrics.call(execution)
      assert_equal 2, metrics.transport_received_count
      assert_equal 2, metrics.schema_valid_count
      assert_equal 2, metrics.known_cost_attempt_count
      assert_operator metrics.estimated_cost_totals.fetch("USD"), :>, 0
      assert_nil metrics.latency_p95_ms

      execution.evaluation_case_results.each do |result|
        run = result.run
        assert result.completed?
        assert_equal "received", result.transport_status
        assert_equal "valid", result.schema_status
        assert_equal(result.actual_output_json == result.expected_output_json, result.passed?)
        assert run.succeeded?
        assert_equal "demo", run.requested_by
        assert_equal "demo", run.app_version
        assert_equal Workbench::DemoTour::SYNTHETIC_NOTE, run.input_snapshot.fetch("demo_note")
        assert_equal execution.id, run.input_snapshot.dig("evaluation", "execution_id")
        assert_equal comparison.id, run.input_snapshot.dig("evaluation", "comparison_id")
        assert_equal [ execution.provider, execution.model_id ], [ run.chat.provider, run.chat.model_id ]
        assert_equal [ execution.provider, execution.model_id ], [ run.attempts.first.provider, run.attempts.first.model_id ]
        assert_equal "estimated", run.attempts.first.cost_status
        assert_empty Ai::SchemaValidator.new(comparison.experiment_snapshot.fetch("schema")).errors_for(result.actual_output_json)
        assert_equal result.actual_output_json, run.result_summary.fetch("structured_output")
        assert_equal result.actual_output_json, run.artifacts.find_by!(kind: "json").content_json
      end
    end

    mismatch = executions.last.evaluation_case_results.find_by!(case_key: "queue")
    refute mismatch.passed?
    assert_includes mismatch.error_summary, "did not exactly match"
    assert_equal "Solid Queue persists background jobs in a database.", mismatch.actual_output_json.fetch("summary")

    frozen_dataset = comparison.dataset_snapshot.deep_dup
    frozen_experiment = comparison.experiment_snapshot.deep_dup
    frozen_targets = comparison.model_targets.deep_dup
    dataset.create_revision!([ { "key" => "later", "input" => "Changed input", "expected_output" => "Changed output" } ])
    comparison.experiment.update!(input_prompt: "A later experiment prompt.")
    comparison.reload
    assert_equal frozen_dataset, comparison.dataset_snapshot
    assert_equal frozen_experiment, comparison.experiment_snapshot
    assert_equal frozen_targets, comparison.model_targets
    assert_equal 1, comparison.evaluation_dataset_revision.revision
  end

  test "rebuilding replaces the tour and remove deletes it" do
    first = Workbench::DemoTour.build!
    second = Workbench::DemoTour.build!

    assert_not Project.exists?(first.id)
    assert_equal 1, Project.where(slug: "demo-tour").count

    Workbench::DemoTour.remove!
    assert_not Project.exists?(second.id)
  end
end

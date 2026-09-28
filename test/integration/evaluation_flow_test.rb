require "test_helper"

class EvaluationFlowTest < ActionDispatch::IntegrationTest
  setup do
    @models = RubyLLM.models.chat_models.all.select do |candidate|
      candidate.provider.to_s == "openrouter" && candidate.supports?(:structured_output) && !candidate.id.to_s.end_with?(":batch")
    end.first(5)
    @model = @models.first
    skip "RubyLLM registry has no structured-output OpenRouter model" unless @model
  end

  test "creates and displays a revisioned dataset and queues a case execution" do
    project = create_project(name: "Evaluation flow project")
    experiment = project.experiments.create!(
      name: "Evaluation schema",
      input_prompt: "Return the expected structure.",
      schema_json: JSON.parse(Ai::SchemaDefinition.default_json)
    )
    cases_json = JSON.pretty_generate([
      { "key" => "case-1", "tags" => [ "smoke", "reference" ], "input" => { "prompt" => "sample" }, "expected_output" => { "summary" => "sample", "confidence" => 1 } }
    ])

    post project_evaluation_datasets_path(project), params: {
      evaluation_dataset: { name: "Smoke cases", description: "One local sample.", cases_json: }
    }
    assert_response :see_other
    dataset = project.evaluation_datasets.last
    assert_equal 1, dataset.current_revision

    with_provider_configuration(@model.provider) do
      get project_evaluation_dataset_path(project, dataset)
    end
    assert_response :success
    assert_includes response.body, "Evaluate a structured Experiment"
    assert_includes response.body, "Optional rubric judge"
    assert_includes response.body, "sends each eligible case's input, generated output, and rubric to the selected judge provider"
    assert_includes response.body, "expected output, tags, and attachments are excluded"
    assert_includes response.body, "up to one provider request per successful case with a rubric"
    assert_includes response.body, "case-1"
    assert_includes response.body, "smoke"

    with_provider_configuration(@model.provider) do
      assert_enqueued_jobs 1, only: EvaluationCaseJob do
        post project_evaluation_dataset_executions_path(project, dataset), params: {
          execution: {
            experiment_id: experiment.id,
            model_reference: "#{@model.provider}|#{@model.id}"
          }
        }
      end
    end

    assert_response :see_other
    execution = dataset.evaluation_executions.last
    assert_equal 1, execution.case_count
    assert_equal "case-1", execution.evaluation_case_results.first.case_key
    assert_equal [ "smoke", "reference" ], execution.runs.first.input_snapshot.dig("evaluation", "tags")
    assert_equal experiment.id, execution.runs.first.experiment_id
    assert_equal "structured", execution.runs.first.operation
  end

  test "queues multiple models against one frozen revision and renders a traceable comparison summary" do
    skip "RubyLLM registry has fewer than two structured-output OpenRouter models" if @models.size < 2
    project = create_project(name: "Comparison flow project")
    experiment = project.experiments.create!(
      name: "Comparison schema",
      input_prompt: "Return the expected structure.",
      schema_json: JSON.parse(Ai::SchemaDefinition.default_json)
    )
    dataset = project.evaluation_datasets.create!(name: "Comparison cases")
    dataset.create_revision!([
      { "key" => "case-1", "input" => { "prompt" => "sample" }, "expected_output" => { "summary" => "sample", "confidence" => 1 } }
    ])
    model_references = @models.first(2).map { |model| "#{model.provider}|#{model.id}" }

    with_provider_configuration(@model.provider) do
      assert_enqueued_jobs 2, only: EvaluationCaseJob do
        post project_evaluation_dataset_executions_path(project, dataset), params: {
          execution: { experiment_id: experiment.id, model_references: }
        }
      end
      assert_response :see_other
      comparison = dataset.evaluation_comparisons.last
      assert_equal 2, comparison.evaluation_executions.count
      assert_equal [ 1 ], comparison.evaluation_executions.map { |execution| execution.input_snapshot.dig("dataset", "revision") }.uniq

      get project_evaluation_dataset_path(project, dataset)
      assert_response :success
      assert_includes response.body, "Cross-model comparison summaries"
      assert_includes response.body, "Comparison ##{comparison.id}"
      assert_includes response.body, "Run #"
      assert_includes response.body, "Observed provider response"
      assert_includes response.body, "Schema validation"
      assert_includes response.body, "Reported:"
    end
  end

  test "rejects invalid or duplicate dataset case keys without persisting a dataset" do
    project = create_project(name: "Invalid dataset project")

    post project_evaluation_datasets_path(project), params: {
      evaluation_dataset: {
        name: "Invalid cases",
        cases_json: JSON.generate([
          { key: "same", input: {}, expected_output: {} },
          { key: "same", input: {}, expected_output: {} }
        ])
      }
    }

    assert_response :unprocessable_entity
    assert_includes response.body, "case key"
    assert_empty project.evaluation_datasets
  end

  test "shows an alert when the queue rejects evaluation case jobs" do
    project = create_project(name: "Rejected evaluation queue project")
    experiment = project.experiments.create!(
      name: "Queue rejection schema",
      input_prompt: "Return the expected structure.",
      schema_json: JSON.parse(Ai::SchemaDefinition.default_json)
    )
    dataset = project.evaluation_datasets.create!(name: "Rejected queue cases")
    dataset.create_revision!([
      { "key" => "case-1", "input" => { "prompt" => "sample" }, "expected_output" => { "summary" => "sample" } }
    ])

    with_provider_configuration(@model.provider) do
      with_singleton_method_stub(EvaluationCaseJob, :perform_later, ->(*) { false }) do
        post project_evaluation_dataset_executions_path(project, dataset), params: {
          execution: {
            experiment_id: experiment.id,
            model_reference: "#{@model.provider}|#{@model.id}"
          }
        }
      end
    end

    assert_response :redirect
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Queue accepted 0 evaluation case job(s) and rejected 1"
    refute_includes response.body, "Evaluation execution #"
    result = dataset.evaluation_executions.last.evaluation_case_results.first
    assert result.queued?
    assert_includes result.error_summary, "Queue adapter did not accept this case"
  end

  test "reports a provider Batch refresh queue rejection without changing execution state" do
    project, dataset, execution, case_result, run = build_running_provider_batch_execution

    assert_no_enqueued_jobs(only: EvaluationBatchRefreshJob) do
      with_singleton_method_stub(EvaluationBatchRefreshJob, :perform_later, ->(*) { false }) do
        post refresh_project_evaluation_dataset_execution_path(project, dataset, execution)
      end
    end

    assert_response :see_other
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Provider batch refresh could not be queued."
    refute_includes response.body, "Provider batch refresh queued."
    assert execution.reload.running?
    assert_equal "batch-refresh-fixture", execution.provider_batch_id
    assert_nil execution.provider_batch_refresh_started_at
    assert_nil execution.provider_batch_refreshed_at
    assert case_result.reload.running?
    assert run.reload.running?
    assert run.attempts.last.running?
  end

  test "reports a provider Batch refresh as queued only when the queue accepts it" do
    project, dataset, execution, = build_running_provider_batch_execution

    assert_enqueued_jobs 1, only: EvaluationBatchRefreshJob do
      post refresh_project_evaluation_dataset_execution_path(project, dataset, execution)
    end

    assert_response :see_other
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Provider batch refresh queued."
    assert execution.reload.running?
    assert_equal "batch-refresh-fixture", execution.provider_batch_id
  end

  test "editing creates a new revision while prior executions keep the original cases" do
    project = create_project(name: "Revisioned evaluation project")
    experiment = project.experiments.create!(
      name: "Revisioned schema",
      input_prompt: "Return the expected structure.",
      schema_json: JSON.parse(Ai::SchemaDefinition.default_json)
    )
    dataset = project.evaluation_datasets.create!(name: "Revisioned cases")
    first_cases = [ { "key" => "original", "input" => { "x" => 1 }, "expected_output" => { "x" => 1 } } ]
    first_revision = dataset.create_revision!(first_cases)
    execution = EvaluationExecution.create!(
      project:,
      evaluation_dataset_revision: first_revision,
      experiment:,
      provider: "openrouter",
      model_id: "test-model",
      status: :queued,
      case_count: 1,
      requested_by: "test",
      input_snapshot_json: {}
    )
    changed_cases = [ first_cases.first.merge("key" => "revised", "input" => { "x" => 2 }) ]

    patch project_evaluation_dataset_path(project, dataset), params: {
      evaluation_dataset: {
        name: "Revisioned cases v2",
        description: "Updated input",
        cases_json: JSON.pretty_generate(changed_cases)
      }
    }

    assert_response :see_other
    assert_equal 2, dataset.reload.current_revision
    assert_equal "original", first_revision.reload.cases.first.fetch("key")
    assert_equal 1, execution.reload.evaluation_dataset_revision.revision
    assert_equal "revised", dataset.current_revision_record.cases.first.fetch("key")
  end

  test "project deletion removes evaluation snapshots and child Run relationships safely" do
    project = create_project(name: "Evaluation deletion project")
    experiment = project.experiments.create!(
      name: "Deletion schema",
      input_prompt: "Return JSON.",
      schema_json: JSON.parse(Ai::SchemaDefinition.default_json)
    )
    dataset = project.evaluation_datasets.create!(name: "Deletion cases")
    revision = dataset.create_revision!([
      { "key" => "delete-me", "input" => { "x" => 1 }, "expected_output" => { "x" => 1 } }
    ])
    execution = EvaluationExecution.create!(
      project:,
      evaluation_dataset_revision: revision,
      experiment:,
      provider: "openrouter",
      model_id: "test-model",
      status: :queued,
      case_count: 1,
      requested_by: "test",
      input_snapshot_json: {}
    )
    chat = create_chat(project)
    run = chat.runs.create!(project:, operation: "structured", status: :queued, requested_by: "test")
    execution.evaluation_case_results.create!(
      evaluation_dataset_revision: revision,
      case_key: "delete-me",
      case_position: 0,
      input_json: { "x" => 1 },
      expected_output_json: { "x" => 1 },
      status: :queued,
      run:
    )

    assert_difference "Project.count", -1 do
      project.destroy!
    end

    assert_not EvaluationDatasetRevision.exists?(revision.id)
    assert_not EvaluationExecution.exists?(execution.id)
    assert_not Run.exists?(run.id)
  end

  private

  def build_running_provider_batch_execution
    project = create_project(name: "Refresh admission project")
    experiment = project.experiments.create!(
      name: "Refresh schema",
      input_prompt: "Return the requested summary.",
      schema_json: JSON.parse(Ai::SchemaDefinition.default_json)
    )
    dataset = project.evaluation_datasets.create!(name: "Refresh cases")
    revision = dataset.create_revision!([
      { "key" => "refresh-case", "input" => { "question" => "sample" }, "expected_output" => { "summary" => "sample" } }
    ])
    execution = project.evaluation_executions.create!(
      evaluation_dataset_revision: revision,
      experiment:,
      provider: @model.provider,
      model_id: @model.id,
      execution_mode: :provider_batch,
      status: :running,
      case_count: 1,
      requested_by: "test",
      started_at: Time.current,
      provider_batch_id: "batch-refresh-fixture",
      provider_batch_status: "pending",
      input_snapshot_json: {}
    )
    case_result = execution.evaluation_case_results.create!(
      evaluation_dataset_revision: revision,
      case_key: "refresh-case",
      case_position: 0,
      input_json: { "question" => "sample" },
      expected_output_json: { "summary" => "sample" },
      status: :running,
      started_at: Time.current
    )
    chat = project.chats.create!(title: "Refresh case", model_id: @model.id, provider: @model.provider)
    run = chat.runs.create!(
      project:,
      experiment:,
      operation: "structured",
      status: :running,
      requested_by: "test",
      started_at: Time.current,
      input_snapshot_json: {}
    )
    run.attempts.create!(
      sequence: 1,
      provider: @model.provider,
      model_id: @model.id,
      status: :running,
      started_at: Time.current
    )
    case_result.update!(run:)

    [ project, dataset, execution, case_result, run ]
  end

  def with_singleton_method_stub(object, name, implementation)
    original = object.method(name)
    object.define_singleton_method(name, &implementation)
    yield
  ensure
    object.define_singleton_method(name, original)
  end
end

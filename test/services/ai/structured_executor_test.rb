require "test_helper"

class Ai::StructuredExecutorTest < ActiveSupport::TestCase
  Chunk = Data.define(:content)
  Response = Data.define(:content, :tokens, :cost, :finish_reason, :id)

  class FakeStructuredChat
    def initialize(chat, content, on_response: nil)
      @chat = chat
      @content = content
      @on_response = on_response
    end

    def provider
      @chat.provider
    end

    def model_id
      @chat.model_id
    end

    def messages
      @chat.messages
    end

    def ruby_llm_usages
      @chat.ruby_llm_usages
    end

    def with_instructions(*, **)
      self
    end

    def with_schema(_schema)
      self
    end

    def with_temperature(_temperature)
      self
    end

    def with_max_output_tokens(_tokens)
      self
    end

    def ask(prompt)
      @chat.messages.create!(role: "user", content: prompt)
      assistant = @chat.messages.create!(role: "assistant", content: "")
      @content.scan(/.{1,12}/m).each do |content|
        yield Chunk.new(content)
        assistant.update!(content: assistant.content.to_s + content)
      end

      model = RubyLLM.models.find(@chat.model_id, provider: @chat.provider)
      tokens = RubyLLM::Tokens.new(input: 10, output: 8)
      response = Response.new(@content, tokens, model.cost_for(tokens), :stop, "structured-response-1")
      @on_response&.call
      response
    end
  end

  setup do
    @project = create_project(name: "Structured executor project")
    @experiment = @project.experiments.create!(
      name: "Structured extraction",
      input_prompt: "Extract the summary and confidence.",
      schema_json: JSON.parse(Ai::SchemaDefinition.default_json)
    )
    @chat = create_chat(@project)
    @run = @chat.runs.create!(
      project: @project,
      experiment: @experiment,
      operation: "structured",
      status: :queued,
      requested_by: "test",
      input_snapshot_json: {
        "experiment" => @experiment.snapshot,
        "target" => { "provider" => @chat.provider, "model_id" => @chat.model_id }
      },
      app_version: "test",
      ruby_llm_version: Gem.loaded_specs.fetch("ruby_llm").version.to_s
    )
    @run.attempts.create!(sequence: 1, provider: @chat.provider, model_id: @chat.model_id, status: :queued)
  end

  test "persists a valid JSON artifact and completes the run" do
    fake_chat = FakeStructuredChat.new(@chat, '{"summary":"Good answer","confidence":0.9}')

    Ai::StructuredExecutor.new(@run.id, run: @run, chat: fake_chat, experiment: @experiment).call

    @run.reload
    artifact = @run.artifacts.first
    assert @run.succeeded?
    assert @run.attempts.first.succeeded?
    assert_equal "valid", @run.result_summary["schema_validation"]
    assert_equal({ "summary" => "Good answer", "confidence" => 0.9 }, artifact.parsed_content)
    assert_equal "json", artifact.kind
  end

  test "fails the attempt when JSON does not satisfy the schema" do
    fake_chat = FakeStructuredChat.new(@chat, '{"summary":"Missing confidence","confidence":"high"}')

    Ai::StructuredExecutor.new(@run.id, run: @run, chat: fake_chat, experiment: @experiment).call

    @run.reload
    attempt = @run.attempts.first
    assert @run.failed?
    assert attempt.failed?
    assert_equal "schema_validation", attempt.error_code
    assert_equal "schema_validation", @run.result_summary["failure_kind"]
    assert_nil @run.artifacts.first
    assert_includes @run.error_summary, "Structured output validation failed"
  end

  test "uses the schema snapshot even after the Experiment definition changes" do
    changed_schema = JSON.parse(Ai::SchemaDefinition.default_json)
    changed_schema["name"] = "later_schema"
    changed_schema["schema"]["properties"]["later_field"] = { "type" => "string" }
    changed_schema["schema"]["required"] = [ "later_field" ]
    @experiment.update!(schema_json: changed_schema)
    fake_chat = FakeStructuredChat.new(@chat, '{"summary":"Frozen schema","confidence":0.8}')

    Ai::StructuredExecutor.new(@run.id, run: @run, chat: fake_chat, experiment: @experiment).call

    assert @run.reload.succeeded?
    assert_equal "response_summary", @run.artifacts.first.metadata_json.fetch("schema_name")
    assert_equal 1, @run.input_snapshot.dig("experiment", "revision")
    assert_equal 2, @experiment.reload.revision
  end

  test "stale evaluation recovery fences a provider response that arrives afterward" do
    dataset = @project.evaluation_datasets.create!(name: "Late response cases")
    revision = dataset.create_revision!([
      { "key" => "late", "input" => { "question" => "sample" }, "expected_output" => { "summary" => "sample", "confidence" => 1 } }
    ])
    execution = EvaluationExecution.create!(
      project: @project,
      evaluation_dataset_revision: revision,
      experiment: @experiment,
      provider: @chat.provider,
      model_id: @chat.model_id,
      status: :running,
      case_count: 1,
      requested_by: "test",
      input_snapshot_json: {}
    )
    result = execution.evaluation_case_results.create!(
      evaluation_dataset_revision: revision,
      case_key: "late",
      case_position: 0,
      input_json: { "question" => "sample" },
      expected_output_json: { "summary" => "sample", "confidence" => 1 },
      status: :running,
      started_at: 1.hour.ago,
      run: @run
    )
    @run.update!(started_at: 1.hour.ago)
    fake_chat = FakeStructuredChat.new(
      @chat,
      '{"summary":"sample","confidence":1}',
      on_response: -> { EvaluationCaseRecoveryJob.perform_now }
    )

    Ai::StructuredExecutor.new(@run.id, run: @run, chat: fake_chat, experiment: @experiment).call

    assert @run.reload.failed?
    assert @run.attempts.first.failed?
    assert result.reload.failed?
    assert_empty @run.artifacts
    assert execution.reload.completed?
  end
end

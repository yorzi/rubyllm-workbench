require "test_helper"

class RunTest < ActiveSupport::TestCase
  setup do
    @project = create_project
    @chat = create_chat(@project)
  end

  test "tracks a successful run and normalizes its inspector values" do
    run = @chat.runs.create!(
      project: @project,
      operation: "chat",
      status: :queued,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "hello" },
      app_version: "test",
      ruby_llm_version: Gem.loaded_specs.fetch("ruby_llm").version.to_s
    )
    run.attempts.create!(
      sequence: 1,
      provider: @chat.provider,
      model_id: @chat.model_id,
      status: :succeeded,
      input_tokens: 10,
      output_tokens: 4,
      reported_cost: 0.001,
      cost_status: "reported"
    )

    run.succeed!("finish_reason" => "stop")

    assert run.reload.succeeded?
    assert_equal({ input: 10, output: 4, cache_read: 0, cache_write: 0, thinking: 0 }, run.total_tokens)
    assert_equal BigDecimal("0.001"), run.total_cost
    assert_equal "reported", run.cost_status
    assert_equal "stop", run.result_summary["finish_reason"]
  end

  test "preserves partial output when a run fails" do
    run = @chat.runs.create!(
      project: @project,
      operation: "chat",
      status: :running,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "hello" }
    )

    run.fail!(RuntimeError.new("provider unavailable"), summary: { "partial_output" => "partial" })

    assert run.reload.failed?
    assert_equal "partial", run.result_summary["partial_output"]
    assert_includes run.error_summary, "provider unavailable"
  end
end

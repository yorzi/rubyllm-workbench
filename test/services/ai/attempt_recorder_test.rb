require "test_helper"

class Ai::AttemptRecorderTest < ActiveSupport::TestCase
  Response = Data.define(:tokens, :cost, :finish_reason, :id)

  setup do
    @project = create_project
    @chat = create_chat(@project)
    @run = @chat.runs.create!(
      project: @project,
      operation: "chat",
      status: :queued,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "hello" },
      app_version: "test",
      ruby_llm_version: Gem.loaded_specs.fetch("ruby_llm").version.to_s
    )
    @attempt = @run.attempts.create!(sequence: 1, provider: @chat.provider, model_id: @chat.model_id, status: :queued)
  end

  test "persists first output timing and response usage without a provider call" do
    recorder = Ai::AttemptRecorder.new(@run, attempt: @attempt, clock: monotonic_clock)
    recorder.start!
    recorder.observe!("partial")

    tokens = RubyLLM::Tokens.new(input: 12, output: 7)
    model = RubyLLM.models.find(@chat.model_id, provider: @chat.provider)
    response = Response.new(tokens, model.cost_for(tokens), :stop, "response-1")
    recorder.succeed!(response)

    assert @run.reload.succeeded?
    assert_equal "partial", recorder.partial_output
    assert_equal 12, @attempt.reload.input_tokens
    assert_equal 7, @attempt.output_tokens
    assert_operator @run.reload.time_to_first_output_ms, :>=, 0
    assert_equal "estimated", @attempt.cost_status
    assert_equal "stop", @run.result_summary["finish_reason"]
  end

  test "copies a persisted usage total into the Attempt and Run without changing its provenance" do
    recorder = Ai::AttemptRecorder.new(@run, attempt: @attempt, clock: monotonic_clock)
    recorder.start!
    usage = @chat.ruby_llm_usages.create!(
      operation: "chat", status: "succeeded", provider: @chat.provider, model: @chat.model_id,
      input_tokens: 12, output_tokens: 7, total_cost: 0.0201,
      server_tool_use: { "web_search_requests" => 2 }
    )
    response = Response.new(RubyLLM::Tokens.new(input: 12, output: 7), nil, :stop, "ledger-response")

    recorder.succeed!(response)

    assert_equal "recorded", @attempt.reload.cost_status
    assert_equal BigDecimal("0.0201"), @attempt.recorded_cost
    assert_equal [ usage.id ], @attempt.ruby_llm_usage_ids_json
    assert_nil @attempt.reported_cost
    assert_nil @attempt.estimated_cost
    assert_equal BigDecimal("0.0201"), @run.reload.total_cost
    assert_equal "recorded", @run.cost_status
    assert_equal({ "web_search_requests" => 2 }, usage.reload.tokens.server_tool_use)
  end

  private

  def monotonic_clock
    values = [ 10.0, 10.125, 10.250 ]
    lambda do |_clock|
      values.shift || 10.250
    end
  end
end

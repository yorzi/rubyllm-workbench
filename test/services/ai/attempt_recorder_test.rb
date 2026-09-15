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

  private

  def monotonic_clock
    values = [ 10.0, 10.125, 10.250 ]
    lambda do |_clock|
      values.shift || 10.250
    end
  end
end

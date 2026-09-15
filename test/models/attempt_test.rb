require "test_helper"

class AttemptTest < ActiveSupport::TestCase
  setup do
    @project = create_project
    @chat = create_chat(@project)
    @run = @chat.runs.create!(
      project: @project,
      operation: "chat",
      status: :queued,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "hello" }
    )
  end

  test "keeps retry attempts separate by sequence" do
    first = @run.attempts.create!(sequence: 1, provider: @chat.provider, model_id: @chat.model_id, status: :failed)
    second = @run.attempts.create!(sequence: 2, provider: @chat.provider, model_id: @chat.model_id, status: :succeeded)

    assert_equal [ first, second ], @run.attempts.to_a
    assert second.succeeded?
    assert_raises(ActiveRecord::RecordInvalid) do
      @run.attempts.create!(sequence: 2, provider: @chat.provider, model_id: @chat.model_id, status: :queued)
    end
  end
end

require "test_helper"

class Ai::AgentResearchReportRecorderTest < ActiveSupport::TestCase
  setup do
    @project = create_project(name: "Research report project")
    @chat = create_chat(@project)
    @run = @chat.runs.create!(
      project: @project,
      operation: "agent",
      status: :running,
      requested_by: "test",
      input_snapshot_json: {
        "agent_definition" => { "id" => 17, "name" => "Source checker", "revision" => 4 }
      }
    )
    @attempt = @run.attempts.create!(
      sequence: 1,
      provider: @chat.provider,
      model_id: @chat.model_id,
      status: :succeeded
    )
    @message = @chat.messages.create!(role: "assistant", content: "A sourced answer.")
    @citation_artifact = @run.artifacts.create!(
      attempt: @attempt,
      kind: "citation_set",
      name: "Provider citations",
      content_json: [ { "title" => "Primary source", "url" => "https://example.test/source" } ],
      metadata_json: { "source_message_id" => @message.id, "citation_count" => 1 }
    )
  end

  test "persists an idempotent report tied to the final message, citations and frozen Agent revision" do
    first = Ai::AgentResearchReportRecorder.call(run: @run, message: @message)
    second = Ai::AgentResearchReportRecorder.call(run: @run, message: @message)

    assert_equal first.id, second.id
    assert_equal 1, @run.artifacts.where(kind: "report").count
    assert_equal "A sourced answer.", first.content_text
    assert_equal @message.id, first.content_json.fetch("source_message_id")
    assert_equal [ @citation_artifact.id ], first.content_json.fetch("citation_artifact_ids")
    assert_equal({ "id" => 17, "name" => "Source checker", "revision" => 4 }, first.content_json.fetch("agent"))
    assert_equal @chat.provider.to_s, first.metadata_json.fetch("provider")
    assert_equal @chat.model_id.to_s, first.metadata_json.fetch("model_id")
    assert_equal @attempt.id, first.attempt_id
  end

  test "rejects an assistant message from another Chat" do
    other_chat = create_chat(@project)
    other_message = other_chat.messages.create!(role: "assistant", content: "Unrelated answer.")

    assert_raises(ArgumentError) do
      Ai::AgentResearchReportRecorder.call(run: @run, message: other_message)
    end
  end
end

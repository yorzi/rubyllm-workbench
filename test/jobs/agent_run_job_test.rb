require "test_helper"

class AgentRunJobTest < ActiveSupport::TestCase
  CitationResponse = Data.define(:id, :citations, :server_tool_calls)
  AttemptRecorderStub = Struct.new(:partial_output)
  AgentStub = Struct.new(:approval_pending) do
    def awaiting_approval?
      approval_pending
    end
  end

  setup do
    @project = create_project(name: "Agent job project")
    @chat = create_chat(@project)
    @run = @chat.runs.create!(
      project: @project,
      operation: "agent",
      status: :running,
      requested_by: "test",
      input_snapshot_json: {
        "prompt" => "verify a claim",
        "agent_definition" => { "id" => 42, "name" => "Source checker", "revision" => 3 }
      }
    )
    @attempt = @run.attempts.create!(
      sequence: 1,
      provider: @chat.provider,
      model_id: @chat.model_id,
      status: :succeeded
    )
  end

  test "stores a cited Agent step on the Run and in its lifecycle timeline" do
    source_message = @chat.messages.create!(role: "assistant", content: "Claim verified.")
    response = CitationResponse.new(
      source_message.id,
      [ { "title" => "Primary source", "url" => "https://example.test/source" } ],
      []
    )
    artifact = Ai::CitationSetRecorder.new(
      run: @run,
      attempt: @attempt,
      response: response,
      source_message_id: source_message.id
    ).call
    job = AgentRunJob.new
    job.instance_variable_set(:@run, @run)
    job.instance_variable_set(:@agent, AgentStub.new(false))
    job.instance_variable_set(:@attempt_recorder, AttemptRecorderStub.new(nil))

    job.send(:save_step_summary, 1, response, source_message.id, artifact)
    job.send(:emit_step_event, 1, @attempt, "completed")

    summary = @run.reload.result_summary
    assert_equal 1, summary.fetch("agent_step_count")
    assert_equal 3, summary.dig("agent_definition", "revision")
    assert_equal [ artifact.id ], summary.fetch("citation_artifact_ids")
    assert_equal artifact.id, summary.fetch("citation_artifact_id")
    assert_equal source_message.id, artifact.metadata_json.fetch("source_message_id")

    event = @run.lifecycle_events.find_by!(name: "ai.agent.step")
    assert_equal 1, event.payload_json.fetch("step_number")
    assert_equal "completed", event.payload_json.fetch("step_status")
    assert_equal 3, event.payload_json.fetch("agent_revision")
  end
end

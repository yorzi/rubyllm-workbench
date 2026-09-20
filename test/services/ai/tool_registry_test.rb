require "test_helper"

class Ai::ToolRegistryTest < ActiveSupport::TestCase
  setup do
    @project = create_project(name: "Tool registry project")
  end

  test "syncs only code-defined tools with inspectable schemas" do
    definitions = Ai::ToolRegistry.sync_project!(@project).to_a

    assert_equal %w[project_snapshot save_run_note], definitions.map(&:key).sort
    assert_equal "never", definitions.find { |definition| definition.key == "project_snapshot" }.approval_policy
    assert_equal "always", definitions.find { |definition| definition.key == "save_run_note" }.approval_policy
    assert definitions.find { |definition| definition.key == "project_snapshot" }.parallel_safe?
    assert_not definitions.find { |definition| definition.key == "save_run_note" }.parallel_safe?
    assert_equal [ "note" ], definitions.find { |definition| definition.key == "save_run_note" }.schema_json.fetch("required")
    assert_equal [ "project_snapshot", "save_run_note" ], Ai::ToolRegistry.snapshot(@project).map { |entry| entry.fetch("key") }
    assert_equal true, Ai::ToolRegistry.snapshot(@project).find { |entry| entry.fetch("key") == "project_snapshot" }.fetch("parallel_safe")
  end

  test "disabled definitions are excluded from the next Run snapshot" do
    Ai::ToolRegistry.sync_project!(@project)
    @project.tool_definitions.find_by!(key: "project_snapshot").update!(enabled: false)

    snapshot = Ai::ToolRegistry.snapshot(@project)

    assert_equal [ "save_run_note" ], snapshot.map { |entry| entry.fetch("key") }
    assert_not @project.tool_definitions.find_by!(key: "project_snapshot").reload.enabled?
  end

  test "executes the approval-gated note tool into a Run Artifact" do
    chat = create_chat(@project)
    run = chat.runs.create!(
      project: @project,
      operation: "chat",
      status: :running,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "save this" }
    )
    attempt = run.attempts.create!(sequence: 1, provider: chat.provider, model_id: chat.model_id, status: :running)
    assistant = chat.messages.create!(role: "assistant", content: "")
    tool_call = RubyLLM::ActiveRecord::ToolCall.create!(
      message: assistant,
      tool_call_id: "call-save-note-#{SecureRandom.hex(4)}",
      name: "save_run_note",
      arguments: { "note" => "A durable observation" }
    )
    Ai::ToolRegistry.sync_project!(@project)
    tool = @project.tool_definitions.find_by!(key: "save_run_note").tool_instance(run:)

    result = tool.call(note: "A durable observation", tool_call:)

    artifact = run.artifacts.order(:id).last
    assert_equal "saved", result.fetch("status")
    assert_equal artifact.id, result.fetch("artifact_id")
    assert_equal "A durable observation", artifact.content_text
    assert_equal attempt.id, artifact.attempt_id
  end

  test "replays a saved note with the same tool call id without duplicating its Artifact" do
    chat = create_chat(@project)
    run = chat.runs.create!(
      project: @project,
      operation: "agent",
      status: :running,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "save this" }
    )
    assistant = chat.messages.create!(role: "assistant", content: "")
    tool_call = RubyLLM::ActiveRecord::ToolCall.create!(
      message: assistant,
      tool_call_id: "call-replayed-note-#{SecureRandom.hex(4)}",
      name: "save_run_note",
      arguments: { "note" => "A replay-safe observation" }
    )
    Ai::ToolRegistry.sync_project!(@project)
    tool = @project.tool_definitions.find_by!(key: "save_run_note").tool_instance(run:)

    first_result = tool.call(note: "A replay-safe observation", tool_call:)
    second_result = tool.call(note: "A replay-safe observation", tool_call:)

    assert_equal first_result.fetch("artifact_id"), second_result.fetch("artifact_id")
    assert_equal 1, run.artifacts.where(source_tool_call_id: tool_call.id).count
  end

  test "sanitizes sensitive nested tool arguments" do
    sanitized = Ai::ToolPayloadSanitizer.call(
      "api_key" => "secret-value",
      "nested" => [ { "authorization" => "Bearer secret-value", "note" => "visible" } ]
    )

    assert_equal "[REDACTED]", sanitized.fetch("api_key")
    assert_equal "[REDACTED]", sanitized.fetch("nested").first.fetch("authorization")
    assert_equal "visible", sanitized.fetch("nested").first.fetch("note")
  end
end

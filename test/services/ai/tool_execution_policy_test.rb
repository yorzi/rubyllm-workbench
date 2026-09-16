require "test_helper"

class Ai::ToolExecutionPolicyTest < ActiveSupport::TestCase
  ModelStub = Data.define(:capabilities) do
    def supports?(capability)
      capabilities.include?(capability.to_s)
    end
  end
  ChatStub = Data.define(:model)

  setup do
    @project = create_project(name: "Tool execution policy project")
    Ai::ToolRegistry.sync_project!(@project)
    @chat = ChatStub.new(model: ModelStub.new([ "parallel_tool_calls" ]))
  end

  test "keeps the default policy sequential" do
    snapshot = Ai::ToolExecutionPolicy.snapshot(project: @project, chat: @chat)

    assert_equal "sequential", snapshot.fetch("requested_mode")
    assert_equal "sequential", snapshot.fetch("effective_mode")
    assert_equal "not_requested", snapshot.fetch("parallel_tool_calls_capability")
    assert_not snapshot.key?("fallback_reason")
    assert_equal({ calls: :one, concurrency: false }, Ai::ToolExecutionPolicy.ruby_llm_options(snapshot))
  end

  test "enables parallel calls only for a capable model and parallel-safe tools" do
    @project.tool_definitions.find_by!(key: "save_run_note").update!(enabled: false)
    @project.update_tool_execution_mode!("parallel")

    snapshot = Ai::ToolExecutionPolicy.snapshot(project: @project, chat: @chat)

    assert_equal "parallel", snapshot.fetch("requested_mode")
    assert_equal "parallel", snapshot.fetch("effective_mode")
    assert_equal "supported", snapshot.fetch("parallel_tool_calls_capability")
    assert_equal "many", snapshot.fetch("calls")
    assert_equal "threads", snapshot.fetch("concurrency")
    assert_not snapshot.key?("fallback_reason")
    assert_equal({ calls: :many, concurrency: :threads }, Ai::ToolExecutionPolicy.ruby_llm_options(snapshot))
  end

  test "falls back to sequential when an enabled tool has side effects" do
    @project.update_tool_execution_mode!("parallel")

    snapshot = Ai::ToolExecutionPolicy.snapshot(project: @project, chat: @chat)

    assert_equal "sequential", snapshot.fetch("effective_mode")
    assert_equal "tool_not_parallel_safe", snapshot.fetch("fallback_reason")
    assert_equal({ calls: :one, concurrency: false }, Ai::ToolExecutionPolicy.ruby_llm_options(snapshot))
  end

  test "falls back when the model does not advertise parallel tool calls" do
    @project.tool_definitions.find_by!(key: "save_run_note").update!(enabled: false)
    @project.update_tool_execution_mode!("parallel")
    unsupported_chat = ChatStub.new(model: ModelStub.new([ "function_calling" ]))

    snapshot = Ai::ToolExecutionPolicy.snapshot(project: @project, chat: unsupported_chat)

    assert_equal "missing", snapshot.fetch("parallel_tool_calls_capability")
    assert_equal "sequential", snapshot.fetch("effective_mode")
    assert_equal "model_capability_missing", snapshot.fetch("fallback_reason")
  end

  test "records an unknown capability when the chat cannot expose model metadata" do
    @project.update_tool_execution_mode!("parallel")
    unknown_chat = Object.new

    snapshot = Ai::ToolExecutionPolicy.snapshot(project: @project, chat: unknown_chat)

    assert_equal "unknown", snapshot.fetch("parallel_tool_calls_capability")
    assert_equal "model_capability_unknown", snapshot.fetch("fallback_reason")
  end
end

require "test_helper"

class Ai::RunExecutorTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @project = create_project(name: "Run executor project")
    @chat = create_chat(@project)
  end

  test "provider-hosted tools are disabled in a new Run by default" do
    assert_enqueued_with(job: ChatResponseJob) do
      @run = Ai::RunExecutor.enqueue(chat: @chat, project: @project, prompt: "answer")
    end

    assert_equal [], @run.input_snapshot.fetch("provider_tools")
  end

  test "freezes the opted-in provider tool allowlist into the Run snapshot" do
    assert_enqueued_with(job: ChatResponseJob) do
      @run = Ai::RunExecutor.enqueue(
        chat: @chat,
        project: @project,
        prompt: "search",
        provider_tools: [ "web_search", "unsupported_tool", "web_search" ]
      )
    end

    assert_equal [ "web_search" ], @run.input_snapshot.fetch("provider_tools")
  end

  test "freezes persisted chat history and its message watermark into the Run snapshot" do
    @chat.messages.create!(role: "user", content: "Earlier question")
    @chat.messages.create!(role: "assistant", content: "Earlier answer")
    watermark = @chat.messages.maximum(:id)

    assert_enqueued_with(job: ChatResponseJob) do
      @run = Ai::RunExecutor.enqueue(chat: @chat, project: @project, prompt: "Continue")
    end

    snapshot = @run.input_snapshot
    assert_equal watermark, snapshot.fetch("conversation_message_high_watermark")
    assert_equal [ "Earlier question", "Earlier answer" ],
      snapshot.dig("conversation_context", "messages").map { |message| message.fetch("content") }
    assert_equal false, snapshot.dig("conversation_context", "attachments_included")
  end

  test "allows only one active Run for a chat" do
    assert_enqueued_jobs 1, only: ChatResponseJob do
      @run = Ai::RunExecutor.enqueue(chat: @chat, project: @project, prompt: "first")

      error = assert_raises(ArgumentError) do
        Ai::RunExecutor.enqueue(chat: @chat, project: @project, prompt: "second")
      end
      assert_includes error.message, "already has a Run in progress"
    end

    assert_equal 1, @chat.runs.count
    assert_equal 1, @run.attempts.count
  end

  test "fails the Run and its initial Attempt when the queue rejects it" do
    with_singleton_method_stub(ChatResponseJob, :perform_later, ->(*) { false }) do
      error = assert_raises(ArgumentError) do
        Ai::RunExecutor.enqueue(chat: @chat, project: @project, prompt: "cannot queue")
      end
      assert_includes error.message, "could not be queued"
    end

    failed_run = @chat.runs.sole
    assert failed_run.failed?
    assert_equal 0, failed_run.result_summary.fetch("conversation_message_end_id")
    assert failed_run.attempts.sole.failed?
    assert_equal "ActiveJob::EnqueueError", failed_run.attempts.sole.error_class
  end

  test "blocks chat continuation after an approved remote tool call has unknown outcome" do
    failed_run = @chat.runs.create!(
      project: @project,
      operation: "agent",
      status: :failed,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "search" }
    )
    failed_run.tool_invocations.create!(
      tool_call_id: "unknown-remote-call",
      tool_key: "web_search",
      status: :failed,
      remote: true,
      error_code: "remote_tool_outcome_unknown"
    )

    assert_no_enqueued_jobs only: ChatResponseJob do
      error = assert_raises(ArgumentError) do
        Ai::RunExecutor.enqueue(chat: @chat, project: @project, prompt: "continue")
      end
      assert_includes error.message, "start a new chat"
    end
    assert_equal 1, @chat.runs.count
  end

  private

  def with_singleton_method_stub(object, name, implementation)
    original = object.method(name)
    object.define_singleton_method(name, &implementation)
    yield
  ensure
    object.define_singleton_method(name, original)
  end
end

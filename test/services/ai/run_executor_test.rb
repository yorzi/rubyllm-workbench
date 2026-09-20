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
end

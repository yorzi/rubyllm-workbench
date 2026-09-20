require "test_helper"

class Ai::ChatToolingTest < ActiveSupport::TestCase
  class FakeChat
    attr_reader :registered_tools, :tool_options, :provider_tools, :provider_tool_calls

    def initialize
      @registered_tools = []
      @provider_tool_calls = []
    end

    def with_tools(*tools)
      @registered_tools = [] if tools == [ nil ]
      @registered_tools.concat(tools.compact)
      self
    end

    def with_tool_options(**options)
      @tool_options = options
      self
    end

    def with_provider_tools(*tools)
      @provider_tool_calls << tools
      @provider_tools = tools
      self
    end
  end

  setup do
    @project = create_project(name: "Chat tooling project")
    Ai::ToolRegistry.sync_project!(@project)
    @chat = create_chat(@project)
  end

  test "applies the frozen parallel policy through RubyLLM public options" do
    @project.tool_definitions.find_by!(key: "save_run_note").update!(enabled: false)
    run = @chat.runs.create!(
      project: @project,
      operation: "chat",
      status: :queued,
      requested_by: "test",
      input_snapshot_json: {
        "prompt" => "inspect",
        "tools" => Ai::ToolRegistry.snapshot(@project),
        "tool_options" => {
          "effective_mode" => "parallel",
          "calls" => "many",
          "concurrency" => "threads"
        }
      }
    )
    fake_chat = FakeChat.new

    Ai::ChatTooling.new(chat: fake_chat, project: @project, run: run).configure

    assert_equal [ "project_snapshot" ], fake_chat.registered_tools.map(&:name)
    assert_equal({ calls: :many, concurrency: :threads }, fake_chat.tool_options)
  end

  test "uses deterministic sequential options for an old Run without a policy snapshot" do
    run = @chat.runs.create!(
      project: @project,
      operation: "chat",
      status: :queued,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "legacy" }
    )
    fake_chat = FakeChat.new

    Ai::ChatTooling.new(chat: fake_chat, project: @project, run: run).configure

    assert_equal({ calls: :one, concurrency: false }, fake_chat.tool_options)
  end

  test "applies snapshotted provider tools and clears them for a default Run" do
    opted_in_run = @chat.runs.create!(
      project: @project,
      operation: "chat",
      status: :queued,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "search", "provider_tools" => [ "web_search" ] }
    )
    default_run = @chat.runs.create!(
      project: @project,
      operation: "chat",
      status: :queued,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "no search" }
    )
    fake_chat = FakeChat.new

    Ai::ChatTooling.new(chat: fake_chat, project: @project, run: opted_in_run).configure

    assert_equal [ [ nil ], [ :web_search ] ], fake_chat.provider_tool_calls
    assert_equal [ :web_search ], fake_chat.provider_tools

    Ai::ChatTooling.new(chat: fake_chat, project: @project, run: default_run).configure

    assert_equal [ [ nil ], [ :web_search ], [ nil ] ], fake_chat.provider_tool_calls
    assert_equal [ nil ], fake_chat.provider_tools
  end
end

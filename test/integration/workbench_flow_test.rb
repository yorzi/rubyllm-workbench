require "test_helper"

class WorkbenchFlowTest < ActionDispatch::IntegrationTest
  test "renders projects and model explorer without provider credentials" do
    get root_path
    assert_response :success
    assert_includes response.body, "Projects"
    assert_includes response.body, "Credential boundary"

    get models_path
    assert_response :success
    assert_includes response.body, "Model Explorer"
    assert_includes response.body, "Needs setup"
  end

  test "creates a project, chat, and queued inspectable run" do
    post projects_path, params: { project: { name: "Flow project", description: "Test" } }
    assert_response :redirect

    project = Project.find_by!(slug: "flow-project")
    model = chat_model
    ensure_chat_model_record

    post project_chats_path(project), params: { chat: { title: "Flow chat", model: "#{model.provider}|#{model.id}" } }
    assert_response :redirect
    chat = project.chats.order(:id).last
    assert_equal model.id, chat.model_id

    get project_chat_path(project, chat)
    assert_response :success
    assert_includes response.body, "Flow chat"

    with_configured_provider(chat) do
      assert_enqueued_with(job: ChatResponseJob) do
        post project_chat_messages_path(project, chat), params: { message: { content: "Say hello" } }
      end
    end
    assert_response :redirect

    run = chat.runs.order(:id).last
    assert_equal "queued", run.status
    assert_equal "Say hello", run.input_snapshot["prompt"]
    assert_equal "sequential", run.input_snapshot.dig("tool_options", "effective_mode")
    assert_equal 1, run.attempts.count

    get run_path(run)
    assert_response :success
    assert_includes response.body, "Input snapshot"
    assert_includes response.body, "Lifecycle events"
    assert_includes response.body, "ai.run.created"
  end

  test "run inspector shows provider activity from its own result snapshot" do
    project = create_project(name: "Provider activity project")
    chat = create_chat(project)
    chat.messages.create!(
      role: "assistant",
      content: "A later answer",
      server_tool_calls: [
        { "type" => "web_search_call", "name" => "later-run-search", "input" => { "query" => "later query" } }
      ]
    )
    run = chat.runs.create!(
      project: project,
      operation: "chat",
      status: :succeeded,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "Earlier run" },
      result_summary_json: {
        "provider_tool_calls" => [
          { "type" => "web_search_call", "name" => "current-run-search", "input" => { "query" => "current query" } }
        ]
      },
      app_version: "test",
      ruby_llm_version: Gem.loaded_specs.fetch("ruby_llm").version.to_s
    )
    run.attempts.create!(sequence: 1, provider: chat.provider, model_id: chat.model_id, status: :succeeded)

    get run_path(run)

    assert_response :success
    assert_includes response.body, "current-run-search"
    assert_includes response.body, "current query"
    refute_includes response.body, "later-run-search"
    refute_includes response.body, "later query"
  end

  test "freezes an effective parallel tool policy into a Run snapshot" do
    project = create_project(name: "Parallel policy project")
    chat = create_chat(project)
    ensure_chat_model_record
    chat.model.update!(capabilities: chat.model.capabilities | [ "parallel_tool_calls" ])
    Ai::ToolRegistry.sync_project!(project)
    project.tool_definitions.find_by!(key: "save_run_note").update!(enabled: false)
    project.update_tool_execution_mode!("parallel")

    assert_enqueued_with(job: ChatResponseJob) do
      @run = Ai::RunExecutor.enqueue(chat:, project:, prompt: "Inspect two sources")
    end

    snapshot = @run.input_snapshot.fetch("tool_options")
    assert_equal "parallel", snapshot.fetch("requested_mode")
    assert_equal "parallel", snapshot.fetch("effective_mode")
    assert_equal "many", snapshot.fetch("calls")
    assert_equal "threads", snapshot.fetch("concurrency")
    assert_equal "supported", snapshot.fetch("parallel_tool_calls_capability")
    assert_nil snapshot["fallback_reason"]
  end

  test "renders persisted chat messages with their message local" do
    project = create_project(name: "Message rendering project")
    chat = create_chat(project)
    chat.messages.create!(role: "user", content: "A persisted prompt")
    chat.messages.create!(role: "assistant", content: "A persisted answer")

    get project_chat_path(project, chat)

    assert_response :success
    assert_includes response.body, "A persisted prompt"
    assert_includes response.body, "A persisted answer"
  end

  test "turns a provider configuration failure into a diagnostic Run" do
    project = create_project(name: "Failure project")
    chat = create_chat(project)
    provider_class = RubyLLM::Provider.resolve(chat.provider)
    requirements = provider_class.configuration_requirements
    previous_values = requirements.to_h { |requirement| [ requirement, RubyLLM.config.public_send(requirement) ] }
    requirements.each { |requirement| RubyLLM.config.public_send("#{requirement}=", nil) }

    run = chat.runs.create!(
      project: project,
      operation: "chat",
      status: :queued,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "This should fail before an API request." },
      app_version: "test",
      ruby_llm_version: Gem.loaded_specs.fetch("ruby_llm").version.to_s
    )
    run.attempts.create!(sequence: 1, provider: chat.provider, model_id: chat.model_id, status: :queued)

    ChatResponseJob.perform_now(run.id)

    assert run.reload.failed?
    assert run.error_summary.present?
    assert run.attempts.first.failed?
  ensure
    previous_values&.each { |requirement, value| RubyLLM.config.public_send("#{requirement}=", value) }
  end

  test "browses and filters the global Run history" do
    project = create_project(name: "History project")
    chat = create_chat(project)
    failed_run = chat.runs.create!(project: project, operation: "chat", status: :failed, requested_by: "test")
    succeeded_run = chat.runs.create!(project: project, operation: "chat", status: :succeeded, requested_by: "test")

    get runs_path
    assert_response :success
    assert_includes response.body, "Run ##{failed_run.id}"
    assert_includes response.body, "Run ##{succeeded_run.id}"
    assert_includes response.body, "History project"

    get runs_path, params: { status: "failed" }
    assert_response :success
    assert_includes response.body, "Run ##{failed_run.id}"
    refute_includes response.body, "Run ##{succeeded_run.id}"

    get runs_path, params: { provider: chat.provider }
    assert_response :success
    assert_includes response.body, "Run ##{failed_run.id}"
    assert_includes response.body, chat.provider

    get runs_path, params: { q: "History project" }
    assert_response :success
    assert_includes response.body, "2 matching runs"
  end
end

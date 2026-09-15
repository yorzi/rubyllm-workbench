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
    assert_equal 1, run.attempts.count

    get run_path(run)
    assert_response :success
    assert_includes response.body, "Input snapshot"
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
end

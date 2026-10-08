require "test_helper"

class LearningExplanationFlowTest < ActionDispatch::IntegrationTest
  test "chat context exposes a learning link and a turbo-frame explanation" do
    project = create_project(name: "Learning chat project")
    chat = create_chat(project)
    chat_path = project_chat_path(project, chat)

    get chat_path

    assert_response :success
    assert_includes response.body, "How this works"
    assert_includes response.body, learning_topic_path("chat_run", return_to: chat_path)
    assert_select "turbo-frame#learning-panel"

    get learning_topic_path("chat_run", return_to: chat_path), headers: { "Turbo-Frame" => "learning-panel" }

    assert_response :success
    assert_select "turbo-frame#learning-panel"
    assert_select "article[data-learning-topic='chat_run']"
    assert_includes response.body, "How a Chat Run works"
    assert_includes response.body, "app/services/ai/chat_executor.rb"
    assert_includes response.body, "RubyLLM overview"
  end

  test "tool and knowledge pages expose their contextual topics" do
    project = create_project(name: "Learning surface project")
    collection = project.knowledge_collections.create!(name: "Learning notes")

    get project_tool_definitions_path(project)
    assert_response :success
    assert_includes response.body, learning_topic_path("tool_approval", return_to: project_tool_definitions_path(project))

    get learning_topic_path("tool_approval"), headers: { "Turbo-Frame" => "learning-panel" }
    assert_response :success
    assert_select "article[data-learning-topic='tool_approval']"
    assert_includes response.body, "How Tool Approval works"
    assert_includes response.body, "app/services/ai/approval_service.rb"

    knowledge_path = project_knowledge_collection_path(project, collection)
    get knowledge_path
    assert_response :success
    assert_includes response.body, learning_topic_path("knowledge_search", return_to: knowledge_path)

    get learning_topic_path("knowledge_search"), headers: { "Turbo-Frame" => "learning-panel" }
    assert_response :success
    assert_select "article[data-learning-topic='knowledge_search']"
    assert_includes response.body, "How Knowledge Search works"
    assert_includes response.body, "app/services/ai/knowledge/retriever.rb"
  end

  test "primary workbench surfaces expose the expanded learning topics" do
    project = create_project(name: "Expanded learning project")

    get root_path
    assert_response :success
    assert_includes response.body, learning_topic_path("project_boundary", return_to: root_path)

    get models_path
    assert_response :success
    assert_includes response.body, learning_topic_path("model_explorer", return_to: models_path)

    chat_setup_url = new_project_chat_path(project)
    get chat_setup_url
    assert_response :success
    assert_includes response.body, learning_topic_path("chat_setup", return_to: chat_setup_url)

    project_url = project_path(project)
    get project_url
    assert_response :success
    assert_includes response.body, learning_topic_path("project_boundary", return_to: project_url)

    experiments_url = project_experiments_path(project)
    get experiments_url
    assert_response :success
    assert_includes response.body, learning_topic_path("experiment_comparison", return_to: experiments_url)

    runs_url = runs_path
    get runs_url
    assert_response :success
    assert_includes response.body, learning_topic_path("run_inspector", return_to: runs_url)

    knowledge_index_url = project_knowledge_collections_path(project)
    get knowledge_index_url
    assert_response :success
    assert_includes response.body, learning_topic_path("knowledge_ingestion", return_to: knowledge_index_url)
  end

  test "expanded topics render their own evidence panels" do
    %w[
      model_explorer
      chat_setup
      experiment_comparison
      run_inspector
      project_boundary
      knowledge_ingestion
      agent_execution
      evaluation_workflow
    ].each do |topic|
      get learning_topic_path(topic), headers: { "Turbo-Frame" => "learning-panel" }

      assert_response :success
      assert_select "article[data-learning-topic='#{topic}']"
      assert_includes response.body, "Source snapshot"
    end
  end

  test "project explanation connects creation, slug routing, and resource ownership to code" do
    get learning_topic_path("project_boundary"), headers: { "Turbo-Frame" => "learning-panel" }

    assert_response :success
    assert_select "article[data-learning-topic='project_boundary']"
    assert_includes response.body, "app/controllers/projects_controller.rb"
    assert_includes response.body, "app/views/projects/index.html.erb"
    assert_includes response.body, "app/models/project.rb"
    assert_includes response.body, "parameterize"
    assert_includes response.body, "nested Rails resources"
  end

  test "Agent and evaluation pages link source-anchored diagrams" do
    project = create_project(name: "Learning durable workflows")
    {
      project_agent_definitions_path(project) => "agent_execution",
      project_evaluation_datasets_path(project) => "evaluation_workflow"
    }.each do |path, topic|
      get path
      assert_response :success
      assert_includes response.body, learning_topic_path(topic, return_to: path)

      get learning_topic_path(topic), headers: { "Turbo-Frame" => "learning-panel" }
      assert_response :success
      assert_select "figure[data-learning-flow='#{topic}']"
      assert_includes response.body, "Execution map"
    end
  end

  test "direct topic URLs remain readable outside a frame" do
    get learning_topic_path("chat_run")

    assert_response :success
    assert_select "article[data-learning-topic='chat_run']"
    assert_includes response.body, "Source snapshot"
    assert_includes response.body, "Rails"
  end

  test "unknown learning topics return not found" do
    get learning_topic_path("not-a-topic")

    assert_response :not_found
  end
end

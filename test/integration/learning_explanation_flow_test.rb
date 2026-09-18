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

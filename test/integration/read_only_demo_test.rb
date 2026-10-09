require "test_helper"
require_relative "../support/read_only_demo_helpers"
require "open3"

class ReadOnlyDemoProbeJob < ApplicationJob
  def perform
    raise "Job body must never execute"
  end
end

class ReadOnlyDemoTest < ActionDispatch::IntegrationTest
  include ReadOnlyDemoHelpers
  setup do
    @project = Message.suppressing_turbo_broadcasts { Workbench::DemoTour.build! }
  end

  test "every tour page is read-only with no SQL writes or execution controls" do
    paths = [ root_path, project_path(@project), models_path,
      project_tool_definitions_path(@project), project_agent_definitions_path(@project),
      project_knowledge_collections_path(@project), project_experiments_path(@project),
      project_evaluation_datasets_path(@project), runs_path ]
    paths += @project.chats.map { |chat| project_chat_path(@project, chat) }
    paths += @project.runs.map { |run| run_path(run) }
    paths += @project.agent_definitions.map { |agent| project_agent_definition_path(@project, agent) }
    paths += @project.knowledge_collections.map { |collection| project_knowledge_collection_path(@project, collection) }
    paths += @project.experiments.map { |experiment| project_experiment_path(@project, experiment) }
    paths += @project.evaluation_datasets.map { |dataset| project_evaluation_dataset_path(@project, dataset) }
    writes = []
    subscriber = lambda do |event|
      writes << event.payload[:sql] if event.payload[:sql].match?(/\A\s*(?:INSERT|UPDATE|DELETE|CREATE|DROP|ALTER)\b/i)
    end
    with_demo_mode do
      ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
        paths.each do |path|
          get path
          assert_response :success, path
          assert_select "form[method='post']", { count: 0 }, path
          assert_select "turbo-cable-stream-source", { count: 0 }, path
          assert_includes response.body, "Synthetic read-only demo"
          assert_equal "no-store", response.headers["Cache-Control"]
        end
      end
    end
    assert_empty writes, writes.join("\n")
  end

  test "crafted mutations and framework endpoints are rejected before parsing bodies" do
    with_demo_mode do
      [ projects_path, project_chat_messages_path(@project, @project.chats.first),
        "/rails/active_storage/direct_uploads", "/cable" ].each do |path|
        post path, params: "malformed upload", headers: { "CONTENT_TYPE" => "multipart/form-data; boundary=broken" }
        assert_response :forbidden
      end
      [ new_project_chat_path(@project), "/rails/active_storage/blobs/redirect/fake/private.txt",
        "/cable", "/unknown", "/assets/../config/database.yml" ].each do |path|
        get path
        assert_response :forbidden, path
      end
      delete project_chat_path(@project, @project.chats.first)
      assert_response :forbidden
    end
  end

  test "final GET parameters cannot turn lexical search into provider work" do
    previous_adapter = ENV["KNOWLEDGE_VECTOR_ADAPTER"]
    ENV["KNOWLEDGE_VECTOR_ADAPTER"] = "sqlite_vector_extension"
    collection = @project.knowledge_collections.first
    fail_provider = ->(*, **) { flunk "A demo GET called a provider" }
    with_replaced_method(Ai::Knowledge::VectorStore::SqliteExtension, :new, -> { flunk "The demo loaded an optional native extension" }) do
      with_demo_mode do
        with_replaced_method(RubyLLM, :embed, fail_provider) do
          with_replaced_method(RubyLLM, :rerank, fail_provider) do
            get project_knowledge_collection_path(@project, collection),
              params: { q: "database jobs", mode: "hybrid", rerank: "true", rerank_model_id: "fake" }
            assert_response :success
            assert_includes response.body, "Solid Queue"
            get project_knowledge_collection_path(@project, collection),
              params: { q: "database jobs", mode: "semantic", rerank: true }.to_json,
              headers: { "CONTENT_TYPE" => "application/json" }
            assert_response :success
            assert_includes response.body, "Solid Queue"
          end
        end
      end
    end
  ensure
    ENV["KNOWLEDGE_VECTOR_ADAPTER"] = previous_adapter
  end

  test "private records never appear in demo navigation or exports" do
    private_project = create_project(name: "Private customer")
    private_run = Run.create!(project: private_project, chat: create_chat(private_project), operation: "chat", requested_by: "local", status: "queued")
    with_demo_mode do
      [ root_path, runs_path, models_path ].each do |path|
        get path
        assert_response :success
        assert_not_includes response.body, "Private customer"
      end
      [ project_path(private_project), run_path(private_run), reproduction_run_path(private_run), events_run_path(private_run) ].each do |path|
        get path
        assert_response :not_found
      end
      get reproduction_run_path(@project.runs.first)
      assert_response :success
      assert_includes response.body, Workbench::DemoTour::SYNTHETIC_NOTE
    end
  end

  test "both scheduling and immediate job execution are disabled" do
    adapter = Workbench::DemoMode::QueueAdapter.new
    assert_raises(Workbench::DemoMode::DisabledOperation) { adapter.enqueue(ReadOnlyDemoProbeJob.new) }
    assert_raises(Workbench::DemoMode::DisabledOperation) { adapter.enqueue_at(ReadOnlyDemoProbeJob.new, Time.now.to_f) }
    with_demo_mode do
      assert_raises(Workbench::DemoMode::DisabledOperation) { ReadOnlyDemoProbeJob.perform_now }
    end
  end

  test "real demo boot uses a separate read-only snapshot and clears provider configuration" do
    environment = { "RAILS_ENV" => "test", "CI" => "1", "WORKBENCH_DEMO" => "1" }
    ENV.each_key { |key| environment[key] = nil if key == "DATABASE_URL" || key.end_with?("_DATABASE_URL") }
    environment["SOLID_QUEUE_IN_PUMA"] = nil
    output, status = Open3.capture2e(environment, Rails.root.join("bin/demo").to_s, "prepare")
    assert status.success?, output
    script = <<~RUBY
      raise "wrong database" unless ActiveRecord::Base.connection_db_config.database == Workbench::DemoMode.snapshot_path.to_s
      raise "wrong queue" unless ActiveJob::Base.queue_adapter.is_a?(Workbench::DemoMode::QueueAdapter)
      raise "provider configured" unless RUBYLLM_CONFIGURATION_ENV.keys.all? { |key| RubyLLM.config.public_send(key).nil? }
      raise "private data" unless Project.pluck(:slug) == ["demo-tour"] && Run.count == 9
      class DemoBootProbeJob < ApplicationJob
        def perform
          raise "job body executed"
        end
      end
      begin
        DemoBootProbeJob.perform_later
        raise "enqueue allowed"
      rescue Workbench::DemoMode::DisabledOperation
      end
      begin
        Project.first.update!(name: "write must fail")
        raise "writable database"
      rescue ActiveRecord::StatementInvalid => error
        raise unless error.cause.is_a?(SQLite3::ReadOnlyException)
      end
      puts "isolated, credential-free, read-only"
    RUBY
    output, status = Open3.capture2e(environment.merge("OPENAI_API_KEY" => "unused-test-value"),
      Rails.root.join("bin/rails").to_s, "runner", script)
    assert status.success?, output
    assert_includes output, "isolated, credential-free, read-only"

    [ { "DATABASE_URL" => "sqlite3:storage/test.sqlite3" }, { "QUEUE_DATABASE_URL" => "sqlite3:storage/test_queue.sqlite3" },
      { "SOLID_QUEUE_IN_PUMA" => "0" } ].each do |override|
      output, status = Open3.capture2e(environment.merge(override), Rails.root.join("bin/rails").to_s, "runner", 'raise "boot guard missed"')
      assert_not status.success?
      assert_match(/Remove database URL overrides|Remove SOLID_QUEUE_IN_PUMA/, output)
      assert_not_includes output, "boot guard missed"
    end
  end
end

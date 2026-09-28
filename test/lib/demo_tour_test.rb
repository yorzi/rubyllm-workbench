require "test_helper"

class DemoTourTest < ActionDispatch::IntegrationTest
  test "builds an explorable synthetic tour without calling a provider" do
    project = Workbench::DemoTour.build!

    assert_equal "demo-tour", project.slug
    statuses = project.runs.pluck(:status).tally
    assert_equal({ "succeeded" => 4, "failed" => 1 }, statuses)
    assert project.runs.all? { |run| run.requested_by == "demo" }
    assert project.runs.find_by(operation: "agent").artifacts.exists?(kind: "report")
    assert_operator project.knowledge_collections.first.knowledge_chunks.count, :>=, 3

    get project_path(project)
    assert_response :success
    project.runs.each do |run|
      get run_path(run)
      assert_response :success, "Run ##{run.id} (#{run.operation}) inspector failed"
    end
    collection = project.knowledge_collections.first
    get project_knowledge_collection_path(project, collection), params: { q: "database jobs" }
    assert_response :success
    assert_includes response.body, "Solid Queue"
    get project_evaluation_dataset_path(project, project.evaluation_datasets.first)
    assert_response :success
  end

  test "rebuilding replaces the tour and remove deletes it" do
    first = Workbench::DemoTour.build!
    second = Workbench::DemoTour.build!

    assert_not Project.exists?(first.id)
    assert_equal 1, Project.where(slug: "demo-tour").count

    Workbench::DemoTour.remove!
    assert_not Project.exists?(second.id)
  end
end

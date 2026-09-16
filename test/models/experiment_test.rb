require "test_helper"

class ExperimentTest < ActiveSupport::TestCase
  setup do
    @project = create_project
    @experiment = @project.experiments.create!(
      name: "Ticket extraction",
      input_prompt: "Extract the ticket fields.",
      schema_json: JSON.parse(Ai::SchemaDefinition.default_json)
    )
  end

  test "starts runnable and snapshots its definition" do
    assert @experiment.runnable?
    assert_equal 1, @experiment.revision
    assert_equal "Extract the ticket fields.", @experiment.snapshot["input_prompt"]
    assert_equal "response_summary", @experiment.snapshot.dig("schema", "name")
  end

  test "increments the revision when the saved definition changes" do
    @experiment.update!(input_prompt: "Extract the revised ticket fields.")

    assert_equal 2, @experiment.reload.revision
    assert_equal "Extract the revised ticket fields.", @experiment.input_prompt
  end

  test "rejects an unsupported schema document" do
    experiment = @project.experiments.new(
      name: "Unsafe schema",
      input_prompt: "Do the task.",
      schema_json: { "name" => "unsafe", "schema" => { "type" => "object", "$ref" => "Ruby.eval" } }
    )

    assert_not experiment.valid?
    assert_includes experiment.errors[:schema_json].join, "$ref"
  end
end

require "test_helper"

class EvaluationDatasetRevisionTest < ActiveSupport::TestCase
  setup do
    project = create_project(name: "Evaluation tag project")
    @dataset = project.evaluation_datasets.create!(name: "Tagged cases")
  end

  test "accepts absent tags and a bounded list of unique labels" do
    no_tags = @dataset.create_revision!([ evaluation_case ])
    tagged = @dataset.create_revision!([ evaluation_case.merge("tags" => [ "smoke", "regression-2026" ]) ])

    assert_equal [ "smoke", "regression-2026" ], tagged.cases.first.fetch("tags")
    refute no_tags.cases.first.key?("tags")
  end

  test "rejects malformed, duplicate, oversized and unbounded tags" do
    invalid_tag_lists = [
      "smoke",
      [ 1 ],
      [ "" ],
      [ " padded " ],
      [ "Repeated", "repeated" ],
      [ "x" * (EvaluationDatasetRevision::MAX_TAG_LENGTH + 1) ],
      Array.new(EvaluationDatasetRevision::MAX_TAGS_PER_CASE + 1, "tag")
    ]

    invalid_tag_lists.each do |tags|
      error = assert_raises(ActiveRecord::RecordInvalid) do
        @dataset.create_revision!([ evaluation_case.merge("tags" => tags) ])
      end
      assert_includes error.record.errors[:cases_json].join, "tags"
    end
  end

  test "accepts a rubric with the maximum number of criteria" do
    rubric = Array.new(EvaluationDatasetRevision::MAX_RUBRIC_CRITERIA) do |index|
      { "key" => "criterion_#{index}", "description" => "Criterion #{index}" }
    end

    revision = @dataset.create_revision!([ evaluation_case.merge("rubric" => rubric) ])

    assert_equal rubric, revision.cases.first.fetch("rubric")
  end

  test "rejects malformed, duplicate and out-of-bounds rubric criteria" do
    valid = { "key" => "accuracy", "description" => "Factual accuracy" }
    invalid_rubrics = [
      "accuracy",
      [],
      Array.new(EvaluationDatasetRevision::MAX_RUBRIC_CRITERIA + 1) { |index| { "key" => "criterion_#{index}", "description" => "Criterion #{index}" } },
      [ "accuracy" ],
      [ valid.merge("extra" => "not allowed") ],
      [ valid.except("description") ],
      [ valid.merge("key" => "Accuracy") ],
      [ valid.merge("key" => "_accuracy") ],
      [ valid.merge("key" => "a" * (EvaluationDatasetRevision::MAX_RUBRIC_KEY_LENGTH + 1)) ],
      [ valid, valid.deep_dup ],
      [ valid.merge("description" => "") ],
      [ valid.merge("description" => " padded ") ],
      [ valid.merge("description" => 42) ],
      [ valid.merge("description" => "x" * (EvaluationDatasetRevision::MAX_RUBRIC_DESCRIPTION_LENGTH + 1)) ]
    ]

    invalid_rubrics.each do |rubric|
      error = assert_raises(ActiveRecord::RecordInvalid) do
        @dataset.create_revision!([ evaluation_case.merge("rubric" => rubric) ])
      end
      assert_includes error.record.errors[:cases_json].join, "rubric"
    end
  end

  private

  def evaluation_case
    { "key" => "case-1", "input" => { "prompt" => "sample" }, "expected_output" => { "answer" => "sample" } }
  end
end

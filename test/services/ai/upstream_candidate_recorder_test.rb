require "test_helper"
require "stringio"

class UpstreamCandidateRecorderTest < ActiveSupport::TestCase
  setup do
    @project = create_project(name: "Upstream candidate project")
    @chat = create_chat(@project)
    @run = @chat.runs.create!(
      project: @project,
      operation: "chat",
      status: :failed,
      requested_by: "local_user",
      app_version: "workbench-test-version",
      ruby_llm_version: "2.0.0",
      input_snapshot_json: { "prompt" => "Reproduce the provider behavior." }
    )
  end

  test "validates candidate category and bounded required and optional fields before saving" do
    invalid_inputs = [
      [ valid_attributes.merge(category: "unknown"), /valid candidate category/ ],
      [ valid_attributes.merge(title: "  \n "), /title is required/i ],
      [ valid_attributes.merge(title: "x" * 201), /title is too long/i ],
      [ valid_attributes.merge(expected_behavior: "  "), /expected behavior is required/i ],
      [ valid_attributes.merge(observed_behavior: "  "), /observed behavior is required/i ],
      [ valid_attributes.merge(reproduction_steps: "  "), /reproduction steps is required/i ],
      [ valid_attributes.merge(regression_test_reference: "reference " * 50 + "x"), /regression test reference is too long/i ]
    ]

    invalid_inputs.each do |attributes, message|
      assert_no_difference -> { @run.artifacts.count } do
        error = assert_raises(ArgumentError, "expected rejection for #{attributes.inspect}") do
          Ai::UpstreamCandidateRecorder.call(run: @run, attributes:)
        end
        assert_match message, error.message
      end
    end
  end

  test "stores each report as a new Artifact with sanitized fields and latest Attempt evidence" do
    @run.attempts.create!(
      sequence: 1,
      provider: "earlier-provider",
      model_id: "earlier-model",
      status: :failed
    )
    @run.attempts.create!(
      sequence: 2,
      provider: "latest-provider",
      model_id: "latest-model",
      status: :failed
    )

    first = Ai::UpstreamCandidateRecorder.call(
      run: @run,
      attributes: valid_attributes.merge(
        title: "  Provider\n\tbehavior mismatch  ",
        regression_test_reference: "  test/integration/provider_flow_test.rb  "
      )
    )
    first_snapshot = first.content_json.deep_dup
    second = Ai::UpstreamCandidateRecorder.call(run: @run, attributes: valid_attributes.merge(title: "Second report"))

    assert_equal "report", first.kind
    assert_equal "Provider behavior mismatch", first.content_json.fetch("title")
    assert_equal "test/integration/provider_flow_test.rb", first.content_json.fetch("regression_test_reference")
    assert_equal "upstream_candidate", first.content_json.fetch("report_type")
    assert_equal 1, first.content_json.fetch("format_version")
    assert_equal @run.id, first.content_json.dig("evidence", "run_id")
    assert_equal "latest-provider", first.content_json.dig("evidence", "provider")
    assert_equal "latest-model", first.content_json.dig("evidence", "model_id")
    assert_equal "workbench-test-version", first.content_json.dig("evidence", "app_version")
    assert_equal "2.0.0", first.content_json.dig("evidence", "ruby_llm_version")
    assert_equal "upstream_candidate", first.metadata_json.fetch("report_type")
    assert_equal "ruby_llm_gap", first.metadata_json.fetch("category")
    assert_equal true, first.metadata_json.fetch("append_only")
    assert_equal JSON.pretty_generate(first.content_json), first.content_text

    assert_not_equal first.id, second.id
    assert_equal 2, @run.artifacts.where(kind: "report").count
    assert_equal first_snapshot, first.reload.content_json
  end

  test "redacts reproduction evidence and excludes candidate Artifacts from later exports" do
    @run.update!(input_snapshot_json: {
      "prompt" => "Keep this prompt with a marker ```` for reproduction. AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE",
      "provider_options" => { "api_key" => "sk-openrouter-SENTINEL-abcdefghijklmnopqrstuvwxyz123456" },
      "source_path" => "/Users/andy/private/project/input.txt"
    })
    @run.attempts.create!(
      sequence: 1,
      provider: "test-provider",
      model_id: "test-model",
      status: :failed,
      error_message: "Failed with OPENAI_API_KEY=assignment-SENTINEL-abcdefghijklmnopqrstuvwxyz123456"
    )
    ordinary_report = @run.artifacts.create!(
      kind: "report",
      name: "Ordinary report",
      content_json: { "report_type" => "agent_research_report", "summary" => "Keep ordinary evidence." },
      content_text: "Keep ordinary evidence."
    )
    audio_artifact = @run.artifacts.create!(kind: "audio", name: "voice.mp3", content_text: "binary placeholder")
    audio_artifact.audio_file.attach(
      io: StringIO.new("AUDIO-BINARY-SENTINEL"),
      filename: "voice.mp3",
      content_type: "audio/mpeg"
    )

    candidate = Ai::UpstreamCandidateRecorder.call(
      run: @run,
      attributes: valid_attributes.merge(
        title: "Leak sk-openrouter-SENTINEL-abcdefghijklmnopqrstuvwxyz123456",
        observed_behavior: "Request included AWS_SECRET_ACCESS_KEY=secret-SENTINEL-abcdefghijklmnopqrstuvwxyz123456"
      )
    )
    serialized_candidate = JSON.generate(candidate.content_json)
    embedded_reproduction = candidate.content_json.fetch("reproduction")
    exported_audio = embedded_reproduction.fetch("artifacts").find { |artifact| artifact["kind"] == "audio" }

    assert_equal "[REDACTED]", candidate.content_json.fetch("title").split.last
    assert_equal "AWS_SECRET_ACCESS_KEY=[REDACTED]", candidate.content_json.fetch("observed_behavior").split.last
    assert_equal "Keep this prompt with a marker ```` for reproduction. AWS_ACCESS_KEY_ID=[REDACTED]",
      embedded_reproduction.dig("run", "input_snapshot", "prompt")
    assert_equal "[REDACTED]", embedded_reproduction.dig("run", "input_snapshot", "provider_options", "api_key")
    assert_equal "OPENAI_API_KEY=[REDACTED]", embedded_reproduction.dig("attempts", 0, "error", "message").split.last
    assert_equal false, exported_audio.fetch("binary_content_included")
    assert_equal false, exported_audio.dig("binary", "included")
    assert_includes serialized_candidate, "Keep ordinary evidence."
    refute_includes candidate.content_text, "SENTINEL"
    refute_includes candidate.content_text, "/Users/andy"
    refute_includes serialized_candidate, "SENTINEL"
    refute_includes serialized_candidate, "AKIAIOSFODNN7EXAMPLE"
    refute_includes serialized_candidate, "/Users/andy"
    refute_includes serialized_candidate, "AUDIO-BINARY-SENTINEL"
    refute_includes serialized_candidate, "binary placeholder"

    later_export = Ai::RunReproductionExporter.call(@run)
    reports = later_export.fetch("artifacts").select { |artifact| artifact["kind"] == "report" }
    assert_equal [ ordinary_report.name ], reports.map { |artifact| artifact.fetch("name") }
    refute_includes JSON.generate(later_export.fetch("artifacts")), "upstream_candidate"
  end

  private

  def valid_attributes
    {
      category: "ruby_llm_gap",
      title: "Provider behavior mismatch",
      expected_behavior: "The client should preserve the response metadata.",
      observed_behavior: "The response metadata is absent.",
      reproduction_steps: "Send a request through the configured provider.",
      regression_test_reference: "test/provider_flow_test.rb"
    }
  end
end

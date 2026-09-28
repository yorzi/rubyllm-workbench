require "test_helper"

class UpstreamCandidateFlowTest < ActionDispatch::IntegrationTest
  setup do
    @project = create_project(name: "Upstream candidate flow project")
    @chat = create_chat(@project)
    @run = @chat.runs.create!(
      project: @project,
      operation: "chat",
      status: :failed,
      requested_by: "local_user",
      app_version: "workbench-test-version",
      ruby_llm_version: "2.0.0",
      input_snapshot_json: {
        "prompt" => "Reproduce this response marker: ````. OPENAI_API_KEY=assignment-SENTINEL-abcdefghijklmnopqrstuvwxyz123456",
        "source_path" => "/Users/andy/private/project/input.txt",
        "endpoint" => "https://issue-user:issue-pass-SENTINEL@api.example.test/v1/chat",
        "signed_url" => "https://storage.googleapis.com/bucket/file?X-Goog-Signature=UPSTREAM-GCS-SIGNATURE-SENTINEL"
      }
    )
  end

  test "posts a candidate, displays the append-only Artifact, and downloads a redacted Markdown draft" do
    post upstream_candidates_run_path(@run), params: { upstream_candidate: valid_attributes }

    assert_response :see_other
    assert_redirected_to run_path(@run, anchor: "upstream-candidates")
    candidate = @run.artifacts.find_by!(kind: "report", name: "Upstream candidate: RubyLLM response mismatch")
    assert_equal true, candidate.metadata_json.fetch("append_only")

    get run_path(@run)
    assert_response :success
    assert_select "#upstream-candidates", text: /RubyLLM response mismatch/
    assert_select "#upstream-candidates a[href=?]", upstream_issue_draft_run_path(@run, artifact_id: candidate.id), text: "Download issue draft"

    get upstream_issue_draft_run_path(@run, artifact_id: candidate.id)

    assert_response :success
    assert_equal "text/markdown", response.media_type
    assert_equal "private, no-store", response.headers.fetch("Cache-Control")
    assert_match(/attachment; filename="run-#{@run.id}-upstream-candidate-#{candidate.id}\.md"/, response.headers.fetch("Content-Disposition"))
    assert_includes response.body, "# RubyLLM response mismatch"
    assert_includes response.body, "## Triage"
    assert_includes response.body, "- Category: `ruby_llm_gap`"
    assert_includes response.body, "- Run: ##{@run.id}"
    assert_includes response.body, "- Provider: `#{@chat.provider}`"
    assert_includes response.body, "- Model: `#{@chat.model_id}`"
    assert_includes response.body, "- App version: `workbench-test-version`"
    assert_includes response.body, "- RubyLLM version: `2.0.0`"
    assert_includes response.body, "## Expected behavior\n\nThe request metadata is preserved."
    assert_includes response.body, "## Observed behavior\n\nThe request metadata is missing."
    assert_includes response.body, "## Minimal reproduction steps\n\nSend one deterministic request."
    assert_includes response.body, "## Regression test\n\ntest/integration/provider_flow_test.rb"
    assert_includes response.body, "## Redacted Run reproduction JSON"
    assert_includes response.body, "https://REDACTED@api.example.test/v1/chat"
    assert_includes response.body, "https://storage.googleapis.com/bucket/file?X-Goog-Signature=[REDACTED]"
    refute_includes response.body, "SENTINEL"
    refute_includes response.body, "UPSTREAM-GCS-SIGNATURE-SENTINEL"
    refute_includes response.body, "/Users/andy"

    embedded_json = JSON.pretty_generate(candidate.content_json.fetch("reproduction"))
    longest_backtick_run = embedded_json.scan(/`+/).map(&:length).max || 0
    expected_fence = "`" * [ 3, longest_backtick_run + 1 ].max
    assert_includes response.body, "#{expected_fence}json\n#{embedded_json}\n#{expected_fence}"
  end

  test "invalid candidate submission redirects without creating an Artifact" do
    assert_no_difference -> { @run.artifacts.count } do
      post upstream_candidates_run_path(@run), params: {
        upstream_candidate: valid_attributes.merge(category: "not-a-category")
      }
    end

    assert_response :redirect
    assert_redirected_to run_path(@run, anchor: "upstream-candidates")
    assert_equal "Choose a valid candidate category.", flash[:alert]
  end

  test "draft download is scoped to its Run and accepts only candidate reports" do
    candidate = Ai::UpstreamCandidateRecorder.call(run: @run, attributes: valid_attributes)
    other_chat = create_chat(@project)
    other_run = other_chat.runs.create!(
      project: @project,
      operation: "chat",
      status: :failed,
      requested_by: "local_user"
    )
    non_candidate = @run.artifacts.create!(
      kind: "report",
      name: "Research report",
      content_json: { "report_type" => "agent_research_report" },
      content_text: "This is not an upstream candidate."
    )

    get upstream_issue_draft_run_path(other_run, artifact_id: candidate.id)
    assert_response :not_found

    get upstream_issue_draft_run_path(@run, artifact_id: non_candidate.id)
    assert_response :not_found
  end

  private

  def valid_attributes
    {
      category: "ruby_llm_gap",
      title: "RubyLLM response mismatch",
      expected_behavior: "The request metadata is preserved.",
      observed_behavior: "The request metadata is missing.",
      reproduction_steps: "Send one deterministic request.",
      regression_test_reference: "test/integration/provider_flow_test.rb"
    }
  end
end

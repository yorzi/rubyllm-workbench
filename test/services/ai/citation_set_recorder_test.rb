require "test_helper"

class Ai::CitationSetRecorderTest < ActiveSupport::TestCase
  Response = Data.define(:citations)

  setup do
    @project = create_project(name: "Citation recorder project")
    @chat = create_chat(@project)
    @run = @chat.runs.create!(
      project: @project,
      operation: "chat",
      status: :succeeded,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "search", "provider_tools" => [ "web_search" ] }
    )
    @attempt = @run.attempts.create!(
      sequence: 1,
      provider: @chat.provider,
      model_id: @chat.model_id,
      status: :succeeded
    )
    @chat.messages.create!(role: "assistant", content: "Earlier answer")
    @source_message = @chat.messages.create!(role: "assistant", content: "Cited answer")
  end

  test "persists sanitized citations with their source assistant message ID" do
    citations = [
      {
        "title" => "RubyLLM guide",
        "url" => "https://example.test/guide",
        "api_token" => "private-token-value",
        "metadata" => {
          "authorization" => "Bearer private-auth-value",
          "excerpt" => "A public excerpt"
        }
      }
    ]

    artifact = Ai::CitationSetRecorder.new(
      run: @run,
      attempt: @attempt,
      response: Response.new(citations)
    ).call

    expected_citations = [
      {
        "title" => "RubyLLM guide",
        "url" => "https://example.test/guide",
        "api_token" => "[REDACTED]",
        "metadata" => {
          "authorization" => "[REDACTED]",
          "excerpt" => "A public excerpt"
        }
      }
    ]

    assert_equal "citation_set", artifact.kind
    assert_equal expected_citations, artifact.content_json
    assert_equal expected_citations, JSON.parse(artifact.content_text)
    assert_equal @run.id, artifact.run_id
    assert_equal @attempt.id, artifact.attempt_id
    assert_equal @source_message.id, artifact.metadata_json.fetch("source_message_id")
    assert_equal 1, artifact.metadata_json.fetch("citation_count")
    assert_equal [ "web_search" ], artifact.metadata_json.fetch("provider_tools")
    refute_includes artifact.content_text, "private-token-value"
    refute_includes artifact.content_text, "private-auth-value"
  end
end

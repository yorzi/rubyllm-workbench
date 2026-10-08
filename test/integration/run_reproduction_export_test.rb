require "test_helper"
require "stringio"

class RunReproductionExportTest < ActionDispatch::IntegrationTest
  test "downloads a sanitized reproduction bundle with prompts and execution context" do
    project = create_project(name: "Reproduction export project")
    chat = create_chat(project)
    run = chat.runs.create!(
      project:,
      operation: "chat",
      status: :failed,
      requested_by: "local_user",
      input_snapshot_json: {
        "prompt" => "Keep this prompt so the run can be reproduced.",
        "provider_options" => {
          "api_key" => "sk-openrouter-SENTINEL-abcdefghijklmnopqrstuvwxyz123456",
          "apiKey" => "camelCase-secret-SENTINEL",
          "authorization" => "Bearer bearer-SENTINEL-abcdefghijklmnopqrstuvwxyz123456",
          "source_path" => "/Users/andy/private/project/input.txt",
          "opaque_json" => "{\"token\":\"OPAQUE-JSON-SENTINEL\"}",
          "signed_urls" => {
            "aws" => "https://bucket.s3.amazonaws.com/file?X-Amz-Expires=600&X-Amz-Signature=AWS-SIGNATURE-SENTINEL",
            "aws_session" => "https://bucket.s3.amazonaws.com/file?X-Amz-Security-Token=AWS-SESSION-SENTINEL&X-Amz-Signature=AWS-SESSION-SIGNATURE-SENTINEL&X-Amz-Expires=600",
            "gcs" => "https://storage.googleapis.com/bucket/file?X-Goog-Signature=GCS-SIGNATURE-SENTINEL",
            "azure_sas" => "https://account.blob.core.windows.net/container/file?sv=2025-01-01&sig=AZURE-SAS-SENTINEL",
            "generic" => "https://example.test/file?signature=GENERIC-SIGNATURE-SENTINEL"
          }
        },
        "endpoint" => "https://url-user:https-pass-SENTINEL@api.example.test/v1/chat",
        "database_url" => "postgresql://db-user:db-pass-SENTINEL@db.example.test:5432/workbench"
      },
      result_summary_json: { "partial_output" => "Useful partial result." },
      error_summary: "OPENAI_API_KEY=assignment-SENTINEL-abcdefghijklmnopqrstuvwxyz123456"
    )
    run.attempts.create!(
      sequence: 1,
      provider: chat.provider,
      model_id: chat.model_id,
      status: :failed,
      error_message: "Request failed with sk-openrouter-ERROR-SENTINEL-abcdefghijklmnopqrstuvwxyz",
      recorded_cost: 0.02,
      cost_status: "recorded",
      metadata_json: {
        "session_token" => "session-SENTINEL",
        "retry_count" => 2
      }
    )
    run.tool_invocations.create!(
      tool_call_id: "call-1",
      tool_key: "lookup",
      status: :failed,
      arguments_json: { "query" => "public docs", "client_secret" => "tool-secret-SENTINEL" },
      result_json: { "text" => "Bearer result-SENTINEL-abcdefghijklmnopqrstuvwxyz" },
      error_message: "failed under /Users/andy/private/project"
    )
    run.lifecycle_events.create!(
      name: "ai.provider.video",
      source: "test",
      occurred_at: Time.current,
      event_key: "reproduction-export-test-#{run.id}",
      payload_json: {
        "status" => "failed",
        "api_key" => "event-secret-SENTINEL",
        "provider_job_id" => "provider-job-SENTINEL"
      }
    )
    text_artifact = run.artifacts.create!(
      kind: "report",
      name: "safe summary",
      content_text: "This textual artifact is useful. secret_token=artifact-SENTINEL-abcdefghijklmnopqrstuvwxyz"
    )
    audio_artifact = run.artifacts.create!(kind: "audio", name: "voice.mp3", content_text: "must not export binary placeholder")
    audio_artifact.audio_file.attach(
      io: StringIO.new("AUDIO-BINARY-SENTINEL"),
      filename: "voice.mp3",
      content_type: "audio/mpeg"
    )

    get reproduction_run_path(run)

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_equal "private, no-store", response.headers.fetch("Cache-Control")
    assert_match(/attachment; filename="run-#{run.id}-reproduction.json"/, response.headers.fetch("Content-Disposition"))

    bundle = JSON.parse(response.body)
    serialized = JSON.generate(bundle)
    assert_equal 2, bundle.fetch("format_version")
    assert_equal "recorded", bundle.dig("attempts", 0, "cost", "status")
    assert_equal "0.02", bundle.dig("attempts", 0, "cost", "recorded")
    assert_includes bundle.dig("run", "input_snapshot", "prompt"), "Keep this prompt"
    assert_includes bundle.dig("run", "result_summary", "partial_output"), "Useful partial result"
    assert_equal "https://REDACTED@api.example.test/v1/chat", bundle.dig("run", "input_snapshot", "endpoint")
    assert_equal "postgresql://REDACTED@db.example.test:5432/workbench", bundle.dig("run", "input_snapshot", "database_url")
    assert_equal "[REDACTED]", bundle.dig("run", "input_snapshot", "provider_options", "api_key")
    assert_equal "[REDACTED]", bundle.dig("run", "input_snapshot", "provider_options", "apiKey")
    assert_equal "{\"token\":\"[REDACTED]\"}", bundle.dig("run", "input_snapshot", "provider_options", "opaque_json")
    assert_equal "https://bucket.s3.amazonaws.com/file?X-Amz-Expires=600&X-Amz-Signature=[REDACTED]",
      bundle.dig("run", "input_snapshot", "provider_options", "signed_urls", "aws")
    assert_equal "https://bucket.s3.amazonaws.com/file?X-Amz-Security-Token=[REDACTED]&X-Amz-Signature=[REDACTED]&X-Amz-Expires=600",
      bundle.dig("run", "input_snapshot", "provider_options", "signed_urls", "aws_session")
    assert_equal "https://storage.googleapis.com/bucket/file?X-Goog-Signature=[REDACTED]",
      bundle.dig("run", "input_snapshot", "provider_options", "signed_urls", "gcs")
    assert_equal "https://account.blob.core.windows.net/container/file?sv=2025-01-01&sig=[REDACTED]",
      bundle.dig("run", "input_snapshot", "provider_options", "signed_urls", "azure_sas")
    assert_equal "https://example.test/file?signature=[REDACTED]",
      bundle.dig("run", "input_snapshot", "provider_options", "signed_urls", "generic")
    assert_equal "[REDACTED]", bundle.dig("attempts", 0, "metadata", "session_token")
    assert_equal 2, bundle.dig("attempts", 0, "metadata", "retry_count")
    video_event = bundle.fetch("events").find { |event| event.fetch("name") == "ai.provider.video" }
    assert_equal "[REDACTED]", video_event.dig("payload", "provider_job_id")
    assert_includes bundle.fetch("artifacts").find { |artifact| artifact["kind"] == "report" }.fetch("content_text"), "This textual artifact is useful"
    assert_equal false, bundle.fetch("artifacts").find { |artifact| artifact["kind"] == "audio" }.dig("binary", "included")
    refute_includes serialized, "SENTINEL"
    refute_includes serialized, "AWS-SIGNATURE-SENTINEL"
    refute_includes serialized, "AWS-SESSION-SENTINEL"
    refute_includes serialized, "AWS-SESSION-SIGNATURE-SENTINEL"
    refute_includes serialized, "GCS-SIGNATURE-SENTINEL"
    refute_includes serialized, "AZURE-SAS-SENTINEL"
    refute_includes serialized, "GENERIC-SIGNATURE-SENTINEL"
    refute_includes serialized, "OPAQUE-JSON-SENTINEL"
    refute_includes serialized, "AUDIO-BINARY-SENTINEL"
    refute_includes serialized, "must not export binary placeholder"
    refute_includes serialized, "/Users/andy"

    assert_includes text_artifact.content_text, "artifact-SENTINEL"
  end

  test "exports frozen prior chat history and only messages written by this Run" do
    project = create_project(name: "Chat context export project")
    chat = create_chat(project)
    prior_message = chat.messages.create!(role: "user", content: "Prior question")
    prior_message.attachments.attach(
      io: StringIO.new("CONTEXT-ATTACHMENT-BYTES"),
      filename: "context.txt",
      content_type: "text/plain"
    )
    frozen_context = Ai::ChatContextSnapshot.call(chat)
    high_watermark = chat.messages.maximum(:id)
    run = chat.runs.create!(
      project:,
      operation: "chat",
      status: :succeeded,
      requested_by: "local_user",
      input_snapshot_json: {
        "prompt" => "Run prompt",
        "conversation_context" => frozen_context,
        "conversation_message_high_watermark" => high_watermark
      },
      result_summary_json: {}
    )
    run_prompt = chat.messages.create!(role: "user", content: "Run prompt")
    run_answer = chat.messages.create!(role: "assistant", content: "Run answer")
    run.update!(result_summary_json: { "conversation_message_end_id" => run_answer.id })
    chat.messages.create!(role: "user", content: "Message from a later Run")

    get reproduction_run_path(run)

    assert_response :success
    bundle = JSON.parse(response.body)
    context = bundle.fetch("chat_context")
    assert_equal "Prior question", context.dig("prior_messages", 0, "content")
    assert_equal [ "Run prompt", "Run answer" ], context.fetch("run_messages").map { |message| message.fetch("content") }
    refute_includes context.fetch("run_messages").map { |message| message.fetch("content") }, "Message from a later Run"
    assert_equal "frozen_before_prompt", context.fetch("prior_context_capture")
    assert_equal "frozen_at_completion", context.fetch("run_context_capture")
    assert_equal false, context.fetch("attachment_payloads_included")
    assert_equal true, context.fetch("attachment_payloads_omitted")
    assert_equal false, context.dig("prior_messages", 0, "attachments", 0, "included")
    refute_includes response.body, "CONTEXT-ATTACHMENT-BYTES"
  end

  test "freezes the reproduction boundary while a Run waits for approval" do
    project = create_project(name: "Approval context export project")
    chat = create_chat(project)
    frozen_context = Ai::ChatContextSnapshot.call(chat)
    high_watermark = chat.messages.maximum(:id) || 0
    run = chat.runs.create!(
      project:,
      operation: "chat",
      status: :queued,
      requested_by: "local_user",
      input_snapshot_json: {
        "prompt" => "Call the tool",
        "conversation_context" => frozen_context,
        "conversation_message_high_watermark" => high_watermark
      }
    )
    tool_request = chat.messages.create!(role: "assistant", content: "Waiting for tool approval")
    run.wait_for_approval!({ "pending_tool_calls" => [ "lookup" ] })

    get reproduction_run_path(run)

    assert_response :success
    context = JSON.parse(response.body).fetch("chat_context")
    assert_equal tool_request.id, run.reload.result_summary.fetch("conversation_message_end_id")
    assert_equal [ "Waiting for tool approval" ], context.fetch("run_messages").map { |message| message.fetch("content") }
    assert_equal "current_run_state", context.fetch("run_context_capture")

    chat.messages.create!(role: "user", content: "A continuation message arrived later")
    continuation_message = chat.messages.create!(role: "assistant", content: "Approved continuation answer")
    run.succeed!({ "partial_output" => continuation_message.content })
    chat.messages.create!(role: "user", content: "Message from a later Run")

    get reproduction_run_path(run)

    assert_response :success
    completed_context = JSON.parse(response.body).fetch("chat_context")
    assert_equal [ "Waiting for tool approval", "A continuation message arrived later", "Approved continuation answer" ],
      completed_context.fetch("run_messages").map { |message| message.fetch("content") }
    assert_equal "frozen_at_completion", completed_context.fetch("run_context_capture")
  end
end

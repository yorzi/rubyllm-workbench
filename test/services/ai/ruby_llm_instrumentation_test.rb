require "test_helper"

class Ai::RubyLlmInstrumentationTest < ActiveSupport::TestCase
  class SyntheticProviderError < StandardError; end

  setup do
    @project = create_project(name: "Instrumentation project")
    @chat = create_chat(@project)
    @run = @chat.runs.create!(
      project: @project,
      operation: "chat",
      status: :running,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "hello" }
    )
    @attempt = @run.attempts.create!(sequence: 1, provider: @chat.provider, model_id: @chat.model_id, status: :running)
  end

  test "maps a chat completion event onto a run-scoped lifecycle event" do
    tokens = Struct.new(:input, :output).new(120, 30)
    cost = Struct.new(:total_cost).new(0.0042)
    payload = {
      chat: @chat,
      provider: "openrouter",
      provider_class: "RubyLLM::Providers::OpenRouter",
      model: @chat.model_id,
      streaming: true,
      tokens: tokens,
      cost: cost,
      response: Struct.new(:finish_reason).new("stop"),
      job_id: "ignored-outside-video-job-event"
    }

    record_event("chat.ruby_llm", payload)

    event = LifecycleEvent.find_by!(name: "ai.provider.chat")
    assert_equal @run.id, event.run_id
    assert_equal @attempt.id, event.attempt_id
    assert_equal "ruby_llm", event.source
    assert_equal "openrouter", event.payload["provider"]
    assert_equal @chat.model_id, event.payload["model_id"]
    assert_equal "chat", event.payload["operation"]
    assert_equal 120, event.payload["input_tokens"]
    assert_equal 30, event.payload["output_tokens"]
    assert_in_delta 0.0042, event.payload["total_cost"], 1e-9
    assert_equal "stop", event.payload["finish_reason"]
    assert_equal "succeeded", event.payload["status"]
    assert_nil event.payload["provider_job_id"]
    assert event.duration_ms.to_i >= 0
  end

  test "maps a tool call event and records failures without leaking payload objects" do
    payload = {
      chat: @chat,
      provider: "openrouter",
      tool_name: "project_snapshot",
      tool_call_id: "call_123",
      error: RubyLLM::Error.new("boom", response: nil)
    }

    record_event("tool_call.ruby_llm", payload)

    event = LifecycleEvent.find_by!(name: "ai.provider.tool")
    assert_equal "project_snapshot", event.payload["tool_name"]
    assert_equal "call_123", event.payload["tool_call_id"]
    assert_equal "failed", event.payload["status"]
    assert_equal "RubyLLM::Error", event.payload["error_class"]
    assert_nil event.payload["chat"]
  end

  test "a raised notification exception records failed transport without persisting its content" do
    Ai::RubyLlmInstrumentation.subscribe!
    secret = "synthetic-provider-secret-and-generated-content"

    assert_raises(SyntheticProviderError) do
      Ai::ExecutionContext.with(run_id: @run.id, attempt_id: @attempt.id) do
        ActiveSupport::Notifications.instrument("chat.ruby_llm", {
          chat: Object.new, provider: "openrouter", model: @chat.model_id
        }) do
          raise SyntheticProviderError, secret
        end
      end
    end

    event = LifecycleEvent.find_by!(name: "ai.provider.chat", run_id: @run.id)
    assert_equal @attempt.id, event.attempt_id
    assert_equal "failed", event.payload.fetch("status")
    assert_equal SyntheticProviderError.name, event.payload.fetch("error_class")
    assert_equal "failed", Ai::EvaluationCaseOutcome.call(@run.reload).transport_status
    %w[error exception exception_object error_message message chat].each do |key|
      assert_not event.payload.key?(key), "raw #{key} must not be persisted"
    end
    assert_not_includes event.to_json, secret
  end

  test "exception tuples retain only a safe class name when the exception object is unavailable" do
    secret = "synthetic-exception-message-and-secret"
    Ai::ExecutionContext.with(run_id: @run.id, attempt_id: @attempt.id) do
      record_event("chat.ruby_llm", { exception: [ "RubyLLM::BadRequestError", secret ] })
    end

    event = LifecycleEvent.find_by!(name: "ai.provider.chat", run_id: @run.id)
    assert_equal "failed", event.payload.fetch("status")
    assert_equal "RubyLLM::BadRequestError", event.payload.fetch("error_class")
    assert_equal "failed", Ai::EvaluationCaseOutcome.call(@run.reload).transport_status
    assert_not event.payload.key?("exception")
    assert_not_includes event.to_json, secret
  end

  test "malformed exception tuples never become persisted error class content" do
    [ "not a class; synthetic secret", "S" * 201, Object.new ].each do |name|
      Ai::ExecutionContext.with(run_id: @run.id, attempt_id: @attempt.id) do
        record_event("chat.ruby_llm", { exception: [ name, "synthetic message" ] })
      end
    end

    events = LifecycleEvent.where(name: "ai.provider.chat", run_id: @run.id)
    assert_equal 3, events.count
    events.each do |event|
      assert_equal "failed", event.payload.fetch("status")
      assert_not event.payload.key?("error_class")
      assert_not event.payload.key?("exception")
      assert_not_includes event.to_json, "synthetic"
    end
  end

  test "persists video provider job references as submitted support evidence" do
    Ai::ExecutionContext.with(run_id: @run.id, attempt_id: @attempt.id) do
      record_event("video_job.ruby_llm", {
        provider: "xai",
        provider_class: "RubyLLM::Providers::XAI",
        model: "grok-imagine-video",
        job_id: "provider-video-job-123"
      })
    end

    event = LifecycleEvent.find_by!(name: "ai.provider.video")
    assert_equal @run.id, event.run_id
    assert_equal @attempt.id, event.attempt_id
    assert_equal "video", event.payload.fetch("operation")
    assert_equal "xai", event.payload.fetch("provider")
    assert_equal "grok-imagine-video", event.payload.fetch("model_id")
    assert_equal "provider-video-job-123", event.payload.fetch("provider_job_id")
    assert_equal "submitted", event.payload.fetch("status")
  end

  test "ignores non-string provider job references" do
    Ai::ExecutionContext.with(run_id: @run.id, attempt_id: @attempt.id) do
      record_event("video_job.ruby_llm", {
        provider: "xai",
        job_id: Object.new
      })
    end

    event = LifecycleEvent.find_by!(name: "ai.provider.video")
    assert_nil event.payload["provider_job_id"]
  end

  test "bounds video provider job references" do
    job_id = "v" * 250
    Ai::ExecutionContext.with(run_id: @run.id, attempt_id: @attempt.id) do
      record_event("video_job.ruby_llm", { job_id: })
    end

    event = LifecycleEvent.find_by!(name: "ai.provider.video")
    persisted_id = event.payload.fetch("provider_job_id")
    assert_equal job_id.truncate(200), persisted_id
    assert_operator persisted_id.length, :<=, 200
  end

  test "is idempotent for the same notification" do
    payload = { chat: @chat, provider: "openrouter", model: @chat.model_id }

    2.times { record_event("chat.ruby_llm", payload, notification_id: "fixed-id") }

    assert_equal 1, LifecycleEvent.where(name: "ai.provider.chat").count
  end

  test "ignores events that cannot be tied to a run" do
    record_event("embedding.ruby_llm", { provider: "openrouter", model: "test-embed" })
    record_event("models.refresh.ruby_llm", { provider: "openrouter" })

    assert_equal 0, LifecycleEvent.where("name LIKE ?", "ai.provider.%").count
  end

  test "falls back to the most recent run when no run is active" do
    @run.update!(status: :succeeded)
    record_event("chat.ruby_llm", { chat: @chat, provider: "openrouter" })

    event = LifecycleEvent.find_by!(name: "ai.provider.chat")
    assert_equal @run.id, event.run_id
  end

  test "subscribe! hooks the notification bus and records real events" do
    Ai::RubyLlmInstrumentation.subscribe!

    ActiveSupport::Notifications.instrument("chat.ruby_llm", { chat: @chat, provider: "openrouter", model: @chat.model_id })

    assert LifecycleEvent.exists?(name: "ai.provider.chat", run_id: @run.id)
  end

  test "correlates RubyLLM's internal chat object with the run in the execution context" do
    internal_chat = Object.new

    Ai::ExecutionContext.with(run_id: @run.id, attempt_id: @attempt.id) do
      record_event("chat.ruby_llm", { chat: internal_chat, provider: "openrouter", model: @chat.model_id })
    end

    event = LifecycleEvent.find_by!(name: "ai.provider.chat")
    assert_equal @run.id, event.run_id
    assert_equal @attempt.id, event.attempt_id
  end

  private

  def record_event(name, payload, notification_id: SecureRandom.uuid)
    Ai::RubyLlmInstrumentation.new(
      name: name,
      started_at: Time.current,
      finished_at: Time.current + 0.01,
      notification_id: notification_id,
      payload: payload
    ).record
  end
end

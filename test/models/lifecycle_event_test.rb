require "test_helper"

class LifecycleEventTest < ActiveSupport::TestCase
  setup do
    @project = create_project(name: "Lifecycle event project")
    @chat = create_chat(@project)
    @run = @chat.runs.create!(
      project: @project,
      operation: "chat",
      status: :queued,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "hello" }
    )
  end

  test "records an ordered run, attempt, streaming, artifact, and completion timeline" do
    @run.start!
    attempt = @run.attempts.create!(
      sequence: 1,
      provider: @chat.provider,
      model_id: @chat.model_id,
      status: :queued
    )
    attempt.start!
    Ai::LifecycleEventRecorder.emit(
      "ai.attempt.streaming",
      run_id: @run.id,
      attempt_id: attempt.id,
      time_to_first_output_ms: 42,
      content: "this must not enter the event payload",
      event_key: "attempt:#{attempt.id}:streaming"
    )
    artifact = @run.artifacts.create!(kind: "text", content_text: "durable output")
    attempt.finish!(status: :succeeded, finished_at: Time.current)
    @run.succeed!("finish_reason" => "stop")

    events = @run.lifecycle_events.reload.chronological.to_a

    assert_equal %w[
      ai.run.created
      ai.run.started
      ai.attempt.started
      ai.attempt.streaming
      ai.artifact.created
      ai.attempt.succeeded
      ai.run.succeeded
    ], events.map(&:name)
    assert_equal artifact.id, events.find { |event| event.name == "ai.artifact.created" }.artifact_id
    assert_equal 42, events.find { |event| event.name == "ai.attempt.streaming" }.payload.fetch("time_to_first_output_ms")
    assert_not_includes events.find { |event| event.name == "ai.attempt.streaming" }.payload, "content"
  end

  test "deduplicates a repeated lifecycle notification by event key" do
    @run.start!

    Ai::LifecycleEventRecorder.emit(
      "ai.run.started",
      run_id: @run.id,
      status: "running",
      event_key: "run:#{@run.id}:started"
    )

    assert_equal 1, @run.lifecycle_events.where(name: "ai.run.started").count
  end

  test "keeps repeated approval pauses and resumptions distinct by attempt" do
    first_attempt = @run.attempts.create!(
      sequence: 1,
      provider: @chat.provider,
      model_id: @chat.model_id,
      status: :queued
    )
    first_attempt.start!
    @run.start!
    @run.wait_for_approval!({}, attempt_id: first_attempt.id)

    second_attempt = @run.attempts.create!(
      sequence: 2,
      provider: @chat.provider,
      model_id: @chat.model_id,
      status: :queued
    )
    second_attempt.start!
    @run.start!
    @run.wait_for_approval!({}, attempt_id: second_attempt.id)

    third_attempt = @run.attempts.create!(
      sequence: 3,
      provider: @chat.provider,
      model_id: @chat.model_id,
      status: :queued
    )
    third_attempt.start!
    @run.start!

    assert_equal 2, @run.lifecycle_events.where(name: "ai.run.waiting_for_approval").count
    assert_equal 2, @run.lifecycle_events.where(name: "ai.run.resumed").count
  end
end

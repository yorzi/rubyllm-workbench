require "test_helper"

class SpeechRunRecoveryJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "fails stale speech Runs without replaying the provider request" do
    project = create_project
    chat = create_chat(project)
    stale_run = build_speech_run(project, chat, "Stale speech")
    stale_run.update!(status: :running, started_at: 1.hour.ago)
    stale_attempt = stale_run.attempts.first
    stale_attempt.update!(status: :running, started_at: 1.hour.ago)
    recent_run = build_speech_run(project, chat, "Recent speech")
    recent_run.update!(status: :running, started_at: 5.minutes.ago)
    recent_run.attempts.first.update!(status: :running, started_at: 5.minutes.ago)

    assert_no_difference -> { Artifact.where(run: stale_run).count } do
      SpeechRunRecoveryJob.perform_now
    end

    assert stale_run.reload.failed?
    assert stale_attempt.reload.failed?
    assert_equal "worker_interrupted", stale_run.result_summary.dig("recovery", "reason")
    assert_equal false, stale_run.result_summary.dig("recovery", "automatic_replay")
    assert_includes stale_run.error_summary, "Start a new speech Run to retry"
    assert recent_run.reload.running?
  end

  test "fails stale queued speech Runs without enqueueing a provider job" do
    project = create_project
    chat = create_chat(project)
    stale_run = build_speech_run(project, chat, "Stale queued speech")
    stale_run.update!(created_at: 1.hour.ago)
    recent_run = build_speech_run(project, chat, "Recent queued speech")

    assert_no_enqueued_jobs(only: SpeechRunJob) do
      SpeechRunRecoveryJob.perform_now
    end

    stale_attempt = stale_run.attempts.first
    assert stale_run.reload.failed?
    assert stale_attempt.reload.failed?
    assert_equal "worker_not_started", stale_run.result_summary.dig("recovery", "reason")
    assert_equal false, stale_run.result_summary.dig("recovery", "automatic_replay")
    assert_empty stale_run.artifacts
    assert recent_run.reload.queued?
    assert recent_run.attempts.first.queued?
  end

  private

  def build_speech_run(project, chat, text)
    run = chat.runs.create!(
      project:,
      operation: "speech",
      status: :queued,
      requested_by: "test",
      input_snapshot_json: { "speech" => { "text" => text } }
    )
    run.attempts.create!(
      sequence: 1,
      provider: chat.provider,
      model_id: chat.model_id,
      status: :queued
    )
    run
  end
end

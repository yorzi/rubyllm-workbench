require "test_helper"

class MediaRunRecoveryJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "fails stale media Runs without replay and leaves recent work running" do
    project = create_project(name: "Media recovery project")
    chat = create_chat(project)
    stale_runs = %w[image transcription video].map do |operation|
      build_running_run(project:, chat:, operation:, started_at: 45.minutes.ago)
    end
    recent_run = build_running_run(project:, chat:, operation: "video", started_at: 5.minutes.ago)

    assert_no_enqueued_jobs do
      MediaRunRecoveryJob.perform_now
    end

    stale_runs.each do |run|
      run.reload
      attempt = run.attempts.first.reload
      assert run.failed?
      assert attempt.failed?
      assert_equal "worker_interrupted", run.result_summary.dig("recovery", "reason")
      assert_equal false, run.result_summary.dig("recovery", "automatic_replay")
      assert_includes run.error_summary, "Start a new Run to retry."
      assert_equal 0, run.artifacts.count
    end

    assert recent_run.reload.running?
    assert recent_run.attempts.first.running?
  end

  test "fails stale queued Runs without enqueueing and leaves recent queued work" do
    project = create_project(name: "Queued media recovery project")
    chat = create_chat(project)
    stale_runs = %w[image transcription video].map do |operation|
      build_queued_run(project:, chat:, operation:, created_at: 45.minutes.ago)
    end
    recent_run = build_queued_run(project:, chat:, operation: "image", created_at: 5.minutes.ago)

    transcription = stale_runs.find { |run| run.operation == "transcription" }
    source = transcription.artifacts.build(
      attempt: transcription.attempts.first,
      kind: "audio",
      name: "source.mp3",
      metadata_json: { "role" => "transcription_input" }
    )
    source.audio_file.attach(io: StringIO.new("source-audio"), filename: "source.mp3", content_type: "audio/mpeg")
    source.save!

    assert_no_enqueued_jobs do
      MediaRunRecoveryJob.perform_now
    end

    stale_runs.each do |run|
      run.reload
      attempt = run.attempts.first.reload
      assert run.failed?
      assert attempt.failed?
      assert_equal "worker_not_started", run.result_summary.dig("recovery", "reason")
      assert_equal false, run.result_summary.dig("recovery", "automatic_replay")
      assert_includes run.error_summary, "No provider request was started"
      assert_empty run.artifacts.where(kind: %w[image video transcript])
    end

    assert transcription.artifacts.find(source.id).audio_file.attached?
    assert recent_run.reload.queued?
    assert recent_run.attempts.first.queued?
  end

  private

  def build_running_run(project:, chat:, operation:, started_at:)
    run = chat.runs.create!(
      project:,
      operation:,
      status: :running,
      requested_by: "test",
      started_at:,
      input_snapshot_json: {
        operation => {
          "provider" => chat.provider,
          "model_id" => chat.model_id,
          "prompt" => "synthetic media work"
        }
      }
    )
    run.attempts.create!(
      sequence: 1,
      provider: chat.provider,
      model_id: chat.model_id,
      status: :running,
      started_at:
    )
    run
  end

  def build_queued_run(project:, chat:, operation:, created_at:)
    run = chat.runs.create!(
      project:,
      operation:,
      status: :queued,
      requested_by: "test",
      created_at:,
      input_snapshot_json: {
        operation => {
          "provider" => chat.provider,
          "model_id" => chat.model_id,
          "prompt" => "synthetic media work"
        }
      }
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

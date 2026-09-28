class MediaRunRecoveryJob < ApplicationJob
  queue_as :maintenance

  STALE_AFTER = 30.minutes
  BATCH_SIZE = 100
  OPERATIONS = %w[image transcription video].freeze

  class WorkerInterruptedError < StandardError
    def code
      "worker_interrupted"
    end
  end

  class WorkerNotStartedError < StandardError
    def code
      "worker_not_started"
    end
  end

  def perform(now = Time.current)
    cutoff = now - STALE_AFTER
    Run.where(operation: OPERATIONS, status: "queued")
      .where("created_at <= ?", cutoff)
      .find_each(batch_size: BATCH_SIZE) do |run|
        recover_queued(run)
      end

    Run.where(operation: OPERATIONS, status: "running")
      .where("started_at <= ?", cutoff)
      .find_each(batch_size: BATCH_SIZE) do |run|
        recover(run, cutoff)
      end
  end

  private

  def recover_queued(run)
    recovered_at = Time.current
    error = WorkerNotStartedError.new(
      "The media worker did not claim this Run within 30 minutes. No provider request was started; create a new Run to retry."
    )

    run.fail_queued_execution!(
      operation: run.operation,
      error:,
      summary: {
        "recovery" => {
          "reason" => error.code,
          "automatic_replay" => false,
          "recovered_at" => recovered_at.iso8601
        }
      }
    ) do
      attempt = run.attempts.where(status: "queued").reorder(sequence: :desc, id: :desc).first
      attempt&.finish!(
        status: :failed,
        finished_at: recovered_at,
        error_class: error.class.name,
        error_code: error.code,
        error_message: error.message
      )
    end
  end

  def recover(run, cutoff)
    recovered_at = Time.current
    error = WorkerInterruptedError.new(
      "Media generation or transcription did not finish within 30 minutes. Start a new Run to retry."
    )

    run.finish_running_execution!(
      operation: run.operation,
      status: :failed,
      error:,
      started_before: cutoff,
      summary: {
        "recovery" => {
          "reason" => error.code,
          "automatic_replay" => false,
          "recovered_at" => recovered_at.iso8601
        }
      }
    ) do
      attempt = run.attempts.where(status: %w[queued running]).reorder(sequence: :desc, id: :desc).first
      attempt&.finish!(
        status: :failed,
        finished_at: recovered_at,
        error_class: error.class.name,
        error_code: error.code,
        error_message: error.message
      )
    end
  end
end

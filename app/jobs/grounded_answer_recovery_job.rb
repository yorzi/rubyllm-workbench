class GroundedAnswerRecoveryJob < ApplicationJob
  queue_as :maintenance
  STALE_AFTER = 30.minutes

  class WorkerError < StandardError
    attr_reader :code

    def initialize(code, message)
      @code = code
      super(message)
    end
  end

  def perform(now = Time.current)
    cutoff = now - STALE_AFTER
    Run.where(operation: Ai::Knowledge::GroundedAnswer::OPERATION, status: "queued")
      .where("created_at <= ?", cutoff).find_each { |run| recover(run, queued: true, cutoff:) }
    Run.where(operation: Ai::Knowledge::GroundedAnswer::OPERATION, status: "running")
      .where("started_at <= ?", cutoff).find_each { |run| recover(run, queued: false, cutoff:) }
  end

  private

  def recover(run, queued:, cutoff:)
    code = queued ? "worker_not_started" : "worker_interrupted"
    error = WorkerError.new(code, "The answer worker did not finish within 30 minutes. The provider outcome may be unknown for a running Run; create a new Run to retry.")
    summary = { "recovery" => { "reason" => code, "automatic_replay" => false, "recovered_at" => Time.current.iso8601 } }
    finish_attempt = lambda do
      run.attempts.where(status: %w[queued running]).each do |attempt|
        attempt.finish!(status: :failed, finished_at: Time.current,
          error_class: error.class.name, error_code: code, error_message: error.message)
      end
    end
    if queued
      run.fail_queued_execution!(operation: run.operation, error:, summary:, &finish_attempt)
    else
      run.finish_running_execution!(operation: run.operation, status: :failed, error:, summary:, started_before: cutoff, &finish_attempt)
    end
  end
end

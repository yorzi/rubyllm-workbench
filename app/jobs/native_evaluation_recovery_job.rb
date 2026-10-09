class NativeEvaluationRecoveryJob < ApplicationJob
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
    operation = Ai::Knowledge::NativeEvaluation::OPERATION
    Run.where(operation:, status: "queued").where("created_at <= ?", cutoff)
      .find_each { |run| recover(run, queued: true, cutoff:) }
    Run.where(operation:, status: "running").where("started_at <= ?", cutoff)
      .find_each { |run| recover(run, queued: false, cutoff:) }
  end

  private

  def recover(run, queued:, cutoff:)
    code = queued ? "worker_not_started" : "worker_interrupted"
    error = WorkerError.new(code, "The evaluation worker did not finish within 30 minutes. A started provider outcome may be unknown; automatic replay is disabled.")
    summary = { "recovery" => { "reason" => code, "automatic_replay" => false, "submission_unknown" => !queued } }
    finish_attempts = lambda do
      run.attempts.where(status: %w[queued running]).each do |attempt|
        attempt.finish!(status: :failed, error_class: error.class.name, error_code: code, error_message: error.message)
      end
    end
    if queued
      run.fail_queued_execution!(operation: run.operation, error:, summary:, &finish_attempts)
    else
      run.finish_running_execution!(operation: run.operation, status: :failed, error:, summary:, started_before: cutoff, &finish_attempts)
    end
  end
end

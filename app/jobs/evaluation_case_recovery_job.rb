class EvaluationCaseRecoveryJob < ApplicationJob
  queue_as :maintenance

  STALE_AFTER = 30.minutes
  BATCH_SIZE = 100

  class WorkerInterruptedError < StandardError
    def code
      "worker_interrupted"
    end
  end

  def perform(now = Time.current)
    cutoff = now - STALE_AFTER
    error = WorkerInterruptedError.new(
      "Evaluation worker did not finish within 30 minutes. Resume will only queue cases that have not started."
    )
    EvaluationCaseResult.joins(:evaluation_execution)
      .where(status: "running")
      .where.not(evaluation_executions: { execution_mode: "provider_batch" })
      .where("evaluation_case_results.started_at <= ?", cutoff)
      .find_each(batch_size: BATCH_SIZE) do |result|
        result.recover_stale!(cutoff:, error:)
      end
  end
end

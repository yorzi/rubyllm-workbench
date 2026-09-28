class EvaluationBatchRecoveryJob < ApplicationJob
  queue_as :maintenance

  STALE_AFTER = 30.minutes
  BATCH_SIZE = 100

  class WorkerInterruptedError < StandardError
    def code
      "worker_interrupted"
    end
  end

  class SubmissionUnknownError < StandardError
    def code
      "provider_batch_submission_unknown"
    end
  end

  def perform(now = Time.current)
    cutoff = now - STALE_AFTER
    EvaluationExecution.where(execution_mode: "provider_batch", status: "preparing")
      .where("updated_at <= ?", cutoff)
      .find_each(batch_size: BATCH_SIZE) do |execution|
        execution.recover_provider_batch_preparation!(
          error: WorkerInterruptedError.new("Evaluation worker stopped before provider batch submission.")
        )
      end

    EvaluationExecution.where(execution_mode: "provider_batch", status: %w[submitting submission_unknown])
      .where("updated_at <= ?", cutoff)
      .find_each(batch_size: BATCH_SIZE) do |execution|
        execution.recover_provider_batch_submission!(
          error: SubmissionUnknownError.new(
            "Provider batch submission may have been accepted, but no provider batch ID was saved. The request was not replayed."
          )
        )
      end
  end
end

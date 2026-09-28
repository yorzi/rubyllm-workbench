class EvaluationCaseJudgmentRecoveryJob < ApplicationJob
  queue_as :maintenance

  STALE_AFTER = 30.minutes
  BATCH_SIZE = 100

  class JudgeWorkerInterruptedError < StandardError
    def code
      "evaluation_judge_submission_unknown"
    end
  end

  def perform(now = Time.current)
    recover_unstarted_judgments

    cutoff = now - STALE_AFTER
    error = JudgeWorkerInterruptedError.new(
      "Automated judge worker stopped after starting the request. The provider outcome may be unknown; automatic replay is disabled."
    )
    EvaluationCaseJudgment.where(status: "running")
      .where("started_at <= ?", cutoff)
      .find_each(batch_size: BATCH_SIZE) do |judgment|
        judgment.recover_stale!(cutoff:, error:)
      end
  end

  private

  def recover_unstarted_judgments
    EvaluationCaseJudgment.where(status: "queued")
      .where(error_summary: nil)
      .find_each(batch_size: BATCH_SIZE) do |judgment|
        run = judgment.run
        next unless run&.queued? && run.started_at.nil? && run.attempts.all?(&:queued?)

        Ai::EvaluationCaseJudgeEnqueuer.enqueue_existing(judgment)
      end
  end
end

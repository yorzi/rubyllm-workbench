class EvaluationCaseJudgeJob < ApplicationJob
  queue_as :default

  def perform(judgment_id)
    @judgment = EvaluationCaseJudgment.includes(:run).find(judgment_id)
    return unless @judgment.claim!

    Ai::StructuredExecutor.new(@judgment.run_id).call
    @judgment.reload.complete_from_run!
  rescue StandardError => error
    @judgment&.fail!(error)
  end
end

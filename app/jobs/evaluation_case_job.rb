class EvaluationCaseJob < ApplicationJob
  queue_as :default

  def perform(case_result_id)
    @case_result = EvaluationCaseResult.includes(:run, :evaluation_execution).find(case_result_id)
    return unless @case_result.claim!

    Ai::StructuredExecutor.new(@case_result.run_id).call
    @case_result.reload.evaluate_run!
  rescue StandardError => error
    @case_result&.fail!(error)
  ensure
    @case_result&.evaluation_execution&.refresh_status!
  end
end

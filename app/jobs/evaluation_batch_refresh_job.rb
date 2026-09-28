class EvaluationBatchRefreshJob < ApplicationJob
  queue_as :default

  def perform(execution_id)
    execution = EvaluationExecution.includes(evaluation_case_results: [ :run ]).find(execution_id)
    return unless execution.claim_provider_batch_refresh!

    batch = RubyLLM::Batch.find(execution.provider_batch_id, provider: execution.provider).refresh
    execution.record_provider_batch_refresh!(batch)
    return execution.refresh_status! unless batch.complete?

    case_results = execution.evaluation_case_results.order(:case_position, :id).to_a
    raise "Provider batch case count no longer matches the frozen evaluation." unless case_results.size == execution.case_count
    messages = Array(Ai::EvaluationBatchResults.call(batch, expected_count: execution.case_count))
    raise "Provider batch result count does not match the frozen evaluation case count." unless messages.size == case_results.size

    case_results.each_with_index do |case_result, position|
      next if case_result.completed? || case_result.failed? || case_result.submission_unknown?

      Ai::EvaluationBatchResultProcessor.new(
        case_result:,
        message: messages[position],
        batch_status: batch.statuses[position]
      ).call
    end
    execution.refresh_status!
  rescue StandardError => error
    execution&.record_provider_batch_refresh_error!(error)
    Rails.logger.warn("Evaluation batch refresh stopped for execution ##{execution_id}: #{error.class}")
  end
end

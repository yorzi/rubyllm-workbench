class EvaluationBatchSubmissionJob < ApplicationJob
  queue_as :default

  def perform(execution_id)
    execution = EvaluationExecution.includes(evaluation_case_results: [ :run, :evaluation_dataset_revision ]).find(execution_id)
    return unless execution.begin_provider_batch_preparation!

    chats = execution.evaluation_case_results.map { |result| prepare_case(result) }
    validate_provider_batch!(chats)
    unless execution.begin_provider_batch_submission!
      execution.reload
      raise "Evaluation cases changed before provider batch submission." if execution.preparing?

      return
    end

    batch = RubyLLM.batch(chats)
    execution.record_provider_batch!(batch)
  rescue StandardError => error
    execution&.reload
    if execution&.submitting?
      execution.reconcile_provider_batch_from_store! || execution.mark_submission_unknown!(error)
    elsif execution&.preparing?
      execution.recover_provider_batch_preparation!(error:)
    end
    Rails.logger.warn("Evaluation batch submission stopped for execution ##{execution_id}: #{error.class}")
  end

  private

  def prepare_case(result)
    raise "Evaluation case #{result.id} could not be claimed." unless result.claim!

    run = result.run
    raise "Evaluation Run #{run.id} could not be claimed." unless run.claim_queued_execution!(operation: "structured")

    attempt = run.attempts.order(:sequence, :id).first
    raise "Evaluation Run #{run.id} has no queued Attempt." unless attempt&.queued?

    attempt.start!
    chat = run.chat
    experiment = run.input_snapshot.fetch("experiment")
    definition = Ai::SchemaDefinition.parse(experiment.fetch("schema"))
    chat.with_instructions(experiment["system_prompt"], persist: false) if experiment["system_prompt"].present?
    chat.with_schema(definition.payload)

    options = experiment["generation_options"] || {}
    chat.with_temperature(options["temperature"]) if options["temperature"]
    chat.with_max_output_tokens(options["max_output_tokens"]) if options["max_output_tokens"]
    chat.ask_later(experiment.fetch("input_prompt"))
    chat
  end

  def validate_provider_batch!(chats)
    records = Array(chats).map { |chat| chat.respond_to?(:to_llm) ? chat.to_llm : chat }
    raise ArgumentError, "Cannot submit an empty provider batch." if records.empty?

    awaiting_roles = %i[user tool]
    unless records.all? { |chat| !chat.complete? && awaiting_roles.include?(chat.messages.last&.role&.to_sym) }
      raise ArgumentError, "Every evaluation chat must be awaiting the model before batch submission."
    end

    providers = records.map { |chat| chat.provider.slug }.uniq
    raise ArgumentError, "Provider batch requests must use one provider." unless providers.one?

    provider = records.first.provider
    raise ArgumentError, "The selected provider does not support batch requests." unless provider.batches?

    records.each(&:render)
  end
end

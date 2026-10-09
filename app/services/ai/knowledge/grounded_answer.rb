module Ai
  module Knowledge
    class GroundedAnswer
      OPERATION = "grounded_answer".freeze

      def self.enqueue(collection:, question:, model_reference:, requested_by: "local_user", model_catalog: Ai::ModelCatalog.new,
                       mode: "lexical", rerank: false, rerank_model_id: nil)
        question = question.to_s.strip
        raise ArgumentError, "Enter a question of 1 to 500 characters." if question.blank? || question.length > 500

        provider, model_id = model_reference.to_s.split("|", 2)
        entry = model_catalog.entries(capability: "structured_output", configured: "true").find do |candidate|
          candidate.provider == provider && candidate.id == model_id && candidate.interactive?
        end
        raise ArgumentError, "Choose a configured structured-output model." unless entry

        raise ArgumentError, "Choose lexical, semantic or hybrid retrieval." unless Search::MODES.include?(mode.to_s)
        mode = mode.to_s
        rerank = rerank.to_s.in?(%w[1 true])
        rerank_model_id = rerank_model_id.to_s.strip.presence
        if rerank && (rerank_model_id.nil? || rerank_model_id.length > 200)
          raise ArgumentError, "Choose a rerank model when reranking is enabled."
        end

        rerank_provider = nil
        if rerank
          rerank_provider, rerank_model_id = rerank_model_id.split("|", 2) if rerank_model_id.include?("|")
          availability = RerankCatalog.availability(rerank_model_id, provider: rerank_provider)
          raise ArgumentError, availability.reason unless availability.available

          rerank_provider = availability.entry.provider
        end

        run = nil
        collection.transaction do
          snapshot = if mode == "lexical" && !rerank
            EvidenceSnapshot.capture(collection:, question:)
          else
            EvidenceSnapshot.prepare(collection:, question:, mode:, rerank:, rerank_model_id:, rerank_provider:)
          end
          snapshot = snapshot.merge(
            "instructions" => GroundedResponse::INSTRUCTIONS, "schema_json" => JSON.generate(GroundedResponse::SCHEMA),
            "generation_options" => { "max_output_tokens" => 2_048 }
          )
          chat = collection.project.chats.create!(
            title: "Source answer · #{question.truncate(120)}", model_id: model_id, provider: provider
          )
          run = chat.runs.create!(
            project: collection.project, operation: OPERATION, status: :queued, requested_by:,
            input_snapshot_json: { "grounded_answer" => snapshot, "target" => { "provider" => provider, "model_id" => model_id } },
            app_version: ENV.fetch("APP_VERSION", "local"), ruby_llm_version: Gem.loaded_specs.fetch("ruby_llm").version.to_s
          )
          # A local refusal has no provider Attempt or fabricated token/cost row.
          run.attempts.create!(sequence: 1, provider:, model_id:, status: :queued) if snapshot.fetch("evidence").any?
        end
        enqueue_job(run)
        run
      end

      def self.enqueue_job(run)
        job = GroundedAnswerJob.perform_later(run.id)
        unless job.respond_to?(:successfully_enqueued?) && job.successfully_enqueued?
          raise job.enqueue_error if job.respond_to?(:enqueue_error) && job.enqueue_error

          raise ActiveJob::EnqueueError, "Grounded answer was not accepted by the queue adapter."
        end
      rescue StandardError => error
        run.fail_queued_execution!(operation: OPERATION, error:) do
          run.attempts.first&.finish!(
            status: :failed, finished_at: Time.current, error_class: error.class.name,
            error_code: Ai::ErrorClassifier.code(error), error_message: Ai::ErrorText.redact(error.message).to_s.truncate(2_000)
          )
        end
        raise ArgumentError, "Answer could not be queued: #{Ai::ErrorText.redact(error.message)}"
      end
      private_class_method :enqueue_job
    end
  end
end

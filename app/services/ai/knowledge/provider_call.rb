module Ai
  module Knowledge
    # One-shot operations use RubyLLM's native physical-request ledger. A
    # collection owns interactive retrieval; an Attempt owns retrieval for a Run.
    class ProviderCall
      class ExecutionStopped < StandardError
        def code
          "execution_stopped"
        end
      end

      class RequestGuard
        def initialize(delegate, run_id:)
          @delegate, @run_id = delegate, run_id
        end

        def instrument(name, payload, &block)
          if name == "request.ruby_llm" && payload[:method].to_s == "post" && !Run.find(@run_id).running?
            raise ExecutionStopped, "This retrieval Run is no longer running."
          end
          @delegate.instrument(name, payload, &block)
        end
      end

      def self.call(owner:, run: nil, phase:, provider:, model_id:)
        new(owner:, run:, phase:, provider:, model_id:).call { |native_owner, context| yield native_owner, context }
      end

      def initialize(owner:, run:, phase:, provider:, model_id:)
        @owner, @run, @phase, @provider, @model_id = owner, run, phase, provider, model_id
      end

      def call
        attempt = start_attempt
        raise ExecutionStopped, "This retrieval Run is no longer running." if @run && !@run.reload.running?

        native_owner = attempt || @owner
        context = if @run
          RubyLLM.context do |config|
            config.instrumenter = RequestGuard.new(config.instrumenter || ActiveSupport::Notifications, run_id: @run.id)
          end
        end
        result = Ai::ExecutionContext.with(run_id: @run&.id, attempt_id: attempt&.id) do
          yield native_owner, context
        end
        finish(attempt, result:)
        result
      rescue StandardError => error
        finish(attempt, error:) if attempt
        raise
      end

      private

      def start_attempt
        return unless @run

        @run.with_lock do
          raise ExecutionStopped, "This retrieval Run is no longer running." unless @run.running?

          @run.attempts.create!(
            sequence: @run.attempts.maximum(:sequence).to_i + 1,
            provider: @provider, model_id: @model_id, status: :running, started_at: Time.current,
            metadata_json: { "phase" => @phase, "collection_id" => @owner&.id }
          )
        end
      end

      def finish(attempt, result: nil, error: nil)
        return unless attempt

        # Native usage persists independently, including late/cancelled calls.
        # Terminal Runs retain their state; never revive an Attempt or save output.
        @run.with_lock do
          rows = attempt.ruby_llm_usages.chronological.to_a
          unless @run.running?
            preserve_late_usage(attempt, rows)
            next
          end
          if rows.empty?
            attributes = result ? Ai::CostNormalizer.for(result, category: :embeddings) : {}
            attributes.merge!(token_attributes(result.tokens)) if result&.respond_to?(:tokens)
            finish_row(attempt, attributes, error:)
          else
            rows.each_with_index do |usage, index|
              row = index.zero? ? attempt : @run.attempts.create!(
                sequence: @run.attempts.maximum(:sequence).to_i + 1, provider: usage.provider, model_id: usage.model,
                status: :running, started_at: attempt.started_at, metadata_json: attempt.metadata_json
              )
              attributes = token_attributes(usage.tokens).merge(Ai::CostNormalizer.for(usage))
              attributes[:ruby_llm_usage_ids_json] = [ usage.id ]
              finish_row(row, attributes, error:, status: usage.status)
            end
          end
        end
      end

      def preserve_late_usage(attempt, rows)
        return if rows.empty?

        attributes = { ruby_llm_usage_ids_json: rows.map(&:id),
          metadata_json: attempt.metadata_json.merge("late_usage_recorded" => true) }
        Ai::AttemptRecorder::TOKEN_FIELDS.each do |field, reader|
          counts = rows.map { |usage| usage.tokens.public_send(reader) }
          attributes[field] = counts.sum if counts.none?(&:nil?)
        end
        amounts = rows.map { |usage| Ai::CostNormalizer.for(usage)[:recorded_cost] }
        complete = amounts.none?(&:nil?)
        attributes.merge!(reported_cost: nil, estimated_cost: nil,
          recorded_cost: complete ? amounts.sum : nil,
          cost_status: complete ? "recorded" : "unknown", currency: "USD")
        attempt.update!(attributes)
      end

      def finish_row(attempt, attributes, error:, status: "succeeded")
        if error
          attributes.merge!(error_class: error.class.name, error_code: Ai::ErrorClassifier.code(error),
            error_message: Ai::ErrorText.safe(error.message, limit: 500))
        end
        attempt.finish!(**attributes, status: error ? :failed : status,
          duration_ms: ((Time.current - attempt.started_at) * 1_000).round)
      end

      def token_attributes(tokens)
        Ai::AttemptRecorder::TOKEN_FIELDS.to_h { |field, reader| [ field, tokens.public_send(reader) ] }
      end
    end
  end
end

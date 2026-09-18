module Ai
  # Maps RubyLLM 2.0 instrumentation onto the local lifecycle catalog.
  #
  # The Specs require provider instrumentation to be consumed through an
  # adapter so the domain model never depends on unstable payload fields. This
  # adapter whitelists a handful of scalars, resolves the Run behind the event's
  # chat when there is one, and records a `ai.provider.*` event with
  # `source = ruby_llm`. Events that cannot be tied to a Run (embedding and
  # rerank calls in the Knowledge flow) are intentionally not recorded: the
  # lifecycle catalog is Run-scoped evidence, not a general event log.
  class RubyLlmInstrumentation
    EVENT_PATTERN = /\.ruby_llm\z/.freeze
    SOURCE = "ruby_llm".freeze

    OPERATIONS = {
      "chat.ruby_llm" => "chat",
      "tool_call.ruby_llm" => "tool",
      "embedding.ruby_llm" => "embedding",
      "rerank.ruby_llm" => "rerank"
    }.freeze

    ACTIVE_RUN_STATUSES = %w[queued running waiting_for_approval].freeze

    class << self
      def subscribe!
        return @subscription if @subscription

        @subscription = ActiveSupport::Notifications.subscribe(EVENT_PATTERN) do |name, started_at, finished_at, notification_id, payload|
          new(
            name: name.to_s,
            started_at: started_at,
            finished_at: finished_at,
            notification_id: notification_id,
            payload: payload
          ).record
        end
      end

      def unsubscribe!
        return unless @subscription

        ActiveSupport::Notifications.unsubscribe(@subscription)
        @subscription = nil
      end

      def subscription
        @subscription
      end
    end

    def initialize(name:, started_at:, finished_at:, notification_id:, payload:)
      @name = name.to_s
      @started_at = started_at
      @finished_at = finished_at
      @notification_id = notification_id
      @payload = payload.is_a?(Hash) ? payload : {}
    end

    def record
      return unless LifecycleEvent.table_exists?

      operation = OPERATIONS[@name]
      return if operation.nil?

      run = resolve_run
      return if run.nil?

      attempt_id = Ai::ExecutionContext.attempt_id || run.attempts.order(:sequence, :id).last&.id

      Ai::LifecycleEventRecorder.persist(
        event_name,
        payload: {
          run_id: run.id,
          attempt_id: attempt_id,
          operation: operation,
          provider: string_value(@payload[:provider]),
          provider_class: string_value(@payload[:provider_class]),
          model_id: model_id,
          streaming: @payload[:streaming],
          tool_name: string_value(@payload[:tool_name]),
          tool_call_id: string_value(@payload[:tool_call_id]),
          input_tokens: token_value(:input),
          output_tokens: token_value(:output),
          total_cost: cost_value,
          finish_reason: finish_reason,
          error_class: error_class,
          status: @payload[:error].present? ? "failed" : "succeeded",
          event_key: "provider:#{@notification_id}"
        }.compact,
        started_at: @started_at,
        finished_at: @finished_at,
        notification_id: @notification_id,
        source: SOURCE
      )
    rescue StandardError => error
      Rails.logger.debug("RubyLLM instrumentation mapping failed: #{error.class}: #{error.message}")
      nil
    end

    private

    def event_name
      "ai.provider.#{OPERATIONS[@name]}"
    end

    def resolve_run
      run_from_context || run_from_chat
    end

    def run_from_context
      run_id = Ai::ExecutionContext.run_id
      return nil if run_id.blank?

      Run.find_by(id: run_id)
    rescue StandardError
      nil
    end

    def run_from_chat
      chat = @payload[:chat]
      return nil unless chat.respond_to?(:runs)

      chat.runs.where(status: ACTIVE_RUN_STATUSES).order(:id).last || chat.runs.order(:id).last
    rescue StandardError
      nil
    end

    def model_id
      value = @payload[:model].presence || @payload[:response_model].presence
      value ||= @payload[:model_info].id if @payload[:model_info].respond_to?(:id)
      string_value(value)
    end

    def token_value(kind)
      tokens = @payload[:tokens]
      return nil unless tokens.respond_to?(kind)

      value = tokens.public_send(kind)
      value.is_a?(Numeric) ? value.to_i : nil
    rescue StandardError
      nil
    end

    def cost_value
      cost = @payload[:cost]
      return nil unless cost.respond_to?(:total_cost)

      value = cost.total_cost
      value.is_a?(Numeric) ? value.to_f : nil
    rescue StandardError
      nil
    end

    def finish_reason
      response = @payload[:response]
      return nil unless response.respond_to?(:finish_reason)

      string_value(response.finish_reason)
    rescue StandardError
      nil
    end

    def error_class
      error = @payload[:error]
      return nil if error.blank?

      error.is_a?(Class) ? error.name : error.class.name
    end

    def string_value(value)
      return nil if value.nil?

      value.to_s.presence
    end
  end
end

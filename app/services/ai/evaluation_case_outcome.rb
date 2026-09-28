module Ai
  class EvaluationCaseOutcome
    Outcome = Data.define(:transport_status, :schema_status)

    PROVIDER_FAILURE_CODES = %w[provider_error provider_batch_request_failed transport_error].freeze
    PROVIDER_CANCELLATION_CODES = %w[provider_batch_cancelled].freeze

    def self.call(run)
      new(run).call
    end

    def initialize(run)
      @run = run
    end

    def call
      return outcome("not_attempted", "not_attempted") unless @run

      attempt = @run.attempts.to_a.last
      event_status = provider_event_status(attempt)
      error_code = attempt&.error_code.to_s

      transport_status = if schema_invalid?(error_code)
        "received"
      elsif schema_valid?
        "received"
      elsif event_status == "succeeded"
        "received"
      elsif event_status == "failed" || PROVIDER_FAILURE_CODES.include?(error_code)
        "failed"
      elsif PROVIDER_CANCELLATION_CODES.include?(error_code)
        "cancelled"
      elsif request_not_started?(attempt)
        "not_attempted"
      else
        "unknown"
      end

      outcome(transport_status, schema_status(transport_status, error_code))
    end

    private

    def provider_event_status(attempt)
      event = @run.lifecycle_events.to_a.reverse.find do |candidate|
        candidate.name == "ai.provider.chat" &&
          candidate.source == "ruby_llm" &&
          (attempt ? candidate.attempt_id == attempt.id : candidate.attempt_id.nil?)
      end
      event&.payload&.fetch("status", nil)
    end

    def request_not_started?(attempt)
      return false if @run.succeeded? || schema_invalid?(attempt&.error_code.to_s)

      @run.started_at.nil? && attempt&.started_at.nil?
    end

    def schema_valid?
      @run.result_summary["schema_validation"] == "valid"
    end

    def schema_invalid?(error_code)
      error_code == "schema_validation"
    end

    def schema_status(transport_status, error_code)
      return "valid" if schema_valid?
      return "invalid" if schema_invalid?(error_code)
      return "not_attempted" if %w[not_attempted cancelled].include?(transport_status)

      "unknown"
    end

    def outcome(transport_status, schema_status)
      Outcome.new(transport_status:, schema_status:)
    end
  end
end

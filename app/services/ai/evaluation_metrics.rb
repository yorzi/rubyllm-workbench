module Ai
  class EvaluationMetrics
    LATENCY_P95_MINIMUM_SAMPLES = 20

    Metrics = Data.define(
      :case_count,
      :transport_received_count,
      :transport_failed_count,
      :transport_cancelled_count,
      :transport_not_attempted_count,
      :transport_unknown_count,
      :transport_success_rate,
      :schema_valid_count,
      :schema_invalid_count,
      :schema_not_attempted_count,
      :schema_unknown_count,
      :schema_valid_rate,
      :latency_sample_count,
      :latency_median_ms,
      :latency_p95_ms,
      :input_tokens_total,
      :input_tokens_sample_count,
      :input_tokens_attempt_count,
      :output_tokens_total,
      :output_tokens_sample_count,
      :output_tokens_attempt_count,
      :reported_cost_totals,
      :estimated_cost_totals,
      :known_cost_attempt_count,
      :unknown_cost_attempt_count,
      :cost_attempt_count
    )

    def self.call(execution)
      new(execution).call
    end

    def initialize(execution)
      @execution = execution
    end

    def call
      outcomes = case_results.map do |case_result|
        stored = Ai::EvaluationCaseOutcome::Outcome.new(
          case_result.transport_status.presence || "",
          case_result.schema_status.presence || ""
        )
        derived = Ai::EvaluationCaseOutcome.call(case_result.run)
        [ case_result, Ai::EvaluationCaseOutcome::Outcome.new(
          stored.transport_status.presence || derived.transport_status,
          stored.schema_status.presence || derived.schema_status
        ) ]
      end
      transport_statuses = outcomes.map { |_case_result, outcome| outcome.transport_status }
      schema_statuses = outcomes.map { |_case_result, outcome| outcome.schema_status }
      provider_attempts = request_attempts(outcomes)
      latencies = latency_samples(outcomes)
      input_samples = provider_attempts.filter_map(&:input_tokens)
      output_samples = provider_attempts.filter_map(&:output_tokens)
      reported_cost_totals = cost_totals(provider_attempts, "reported")
      estimated_cost_totals = cost_totals(provider_attempts, "estimated")
      known_cost_attempt_count = provider_attempts.count do |attempt|
        %w[reported estimated].include?(attempt.cost_status.to_s) &&
          (attempt.reported_cost.present? || attempt.estimated_cost.present?)
      end

      Metrics.new(
        case_count: outcomes.size,
        transport_received_count: transport_statuses.count("received"),
        transport_failed_count: transport_statuses.count("failed"),
        transport_cancelled_count: transport_statuses.count("cancelled"),
        transport_not_attempted_count: transport_statuses.count("not_attempted"),
        transport_unknown_count: transport_statuses.count("unknown"),
        transport_success_rate: rate(transport_statuses.count("received"), transport_statuses.count { |status| %w[received failed].include?(status) }),
        schema_valid_count: schema_statuses.count("valid"),
        schema_invalid_count: schema_statuses.count("invalid"),
        schema_not_attempted_count: schema_statuses.count("not_attempted"),
        schema_unknown_count: schema_statuses.count("unknown"),
        schema_valid_rate: rate(schema_statuses.count("valid"), schema_statuses.count { |status| %w[valid invalid].include?(status) }),
        latency_sample_count: latencies.size,
        latency_median_ms: median(latencies),
        latency_p95_ms: percentile_95(latencies),
        input_tokens_total: input_samples.empty? ? nil : input_samples.sum,
        input_tokens_sample_count: input_samples.size,
        input_tokens_attempt_count: provider_attempts.size,
        output_tokens_total: output_samples.empty? ? nil : output_samples.sum,
        output_tokens_sample_count: output_samples.size,
        output_tokens_attempt_count: provider_attempts.size,
        reported_cost_totals:,
        estimated_cost_totals:,
        known_cost_attempt_count:,
        unknown_cost_attempt_count: provider_attempts.size - known_cost_attempt_count,
        cost_attempt_count: provider_attempts.size
      )
    end

    private

    def case_results
      @execution.evaluation_case_results.to_a
    end

    def request_attempts(outcomes)
      outcomes.flat_map do |case_result, outcome|
        next [] if outcome.transport_status == "not_attempted"

        Array(case_result.run&.attempts).select do |attempt|
          attempt.started_at.present? || !attempt.queued? || attempt.tokens.any? ||
            attempt.reported_cost.present? || attempt.estimated_cost.present?
        end
      end
    end

    def latency_samples(outcomes)
      return [] unless @execution.individual?

      outcomes.flat_map do |case_result, outcome|
        next [] unless %w[received failed].include?(outcome.transport_status)

        Array(case_result.run&.attempts).filter_map do |attempt|
          attempt.duration_ms if attempt.duration_ms.is_a?(Numeric) && attempt.duration_ms >= 0
        end
      end
    end

    def cost_totals(attempts, status)
      field = status == "reported" ? :reported_cost : :estimated_cost
      attempts.each_with_object(Hash.new { |totals, currency| totals[currency] = 0.to_d }) do |attempt, totals|
        next unless attempt.cost_status.to_s == status

        amount = attempt.public_send(field)
        next if amount.nil?

        currency = attempt.currency.presence || "Currency unknown"
        totals[currency] += amount.to_d
      end.to_h
    end

    def rate(numerator, denominator)
      return if denominator.zero?

      numerator.to_f / denominator
    end

    def median(values)
      sorted = values.sort
      return if sorted.empty?

      middle = sorted.size / 2
      return sorted[middle] if sorted.size.odd?

      ((sorted[middle - 1] + sorted[middle]) / 2.0).round
    end

    def percentile_95(values)
      return if values.size < LATENCY_P95_MINIMUM_SAMPLES

      sorted = values.sort
      sorted[(0.95 * sorted.size).ceil - 1]
    end
  end
end

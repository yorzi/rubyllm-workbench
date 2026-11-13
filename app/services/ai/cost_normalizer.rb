module Ai
  class CostNormalizer
    def self.for(usage_or_response, model: nil, category: :text_tokens)
      new(usage_or_response, model:, category:).call
    end

    def initialize(usage_or_response, model: nil, category: :text_tokens)
      @value = usage_or_response
      @model = model
      @category = category
    end

    def call
      tokens = @value.respond_to?(:tokens) ? @value.tokens : RubyLLM::Tokens.new
      cost = @value.respond_to?(:cost) ? @value.cost : nil

      if cost&.total && reported_cost?(cost, tokens)
        return { reported_cost: cost.total, recorded_cost: nil, estimated_cost: nil, cost_status: "reported", currency: "USD" }
      end

      # A persisted RubyLLM usage row retains the cost calculated at request
      # time, but does not retain whether that total was provider-reported or
      # estimated. Preserve it without repricing history or inventing provenance.
      if @value.respond_to?(:total_cost)
        total = @value.total_cost
        # RubyLLM can record zero counters for an unsuccessful request without
        # usage. Keep the raw row, but only count zero when it has evidence.
        if total == 0 && (unmeasured?(tokens) || (failed_usage? && zero_counters?(tokens)))
          total = nil
        end
        return { recorded_cost: total, reported_cost: nil, estimated_cost: nil,
          cost_status: total.nil? ? "unknown" : "recorded", currency: "USD" }
      end

      if @model && tokens.to_h.any? && !unmeasured?(tokens)
        estimated = RubyLLM::Cost.new(tokens:, model: @model, category: @category).total
        return { reported_cost: nil, recorded_cost: nil, estimated_cost: estimated, cost_status: "estimated", currency: "USD" } if estimated
      end

      { reported_cost: nil, recorded_cost: nil, estimated_cost: nil, cost_status: "unknown", currency: "USD" }
    end

    private

    def unmeasured?(tokens)
      tokens.input.nil? && tokens.output.nil? && zero_counters?(tokens)
    end

    def zero_counters?(tokens)
      tokens.to_h.values.all? { |value| value == 0 || (value.respond_to?(:empty?) && value.empty?) }
    end

    def failed_usage?
      @value.respond_to?(:status) && @value.status == "failed"
    end

    def reported_cost?(cost, tokens)
      return true if tokens.respond_to?(:reported_cost) && tokens.reported_cost

      cost.respond_to?(:reported?) && cost.reported?
    end
  end
end

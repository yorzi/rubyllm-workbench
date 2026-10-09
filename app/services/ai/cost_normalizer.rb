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
        # RubyLLM 2.1 may manufacture a zero cache count when chat usage is
        # absent. The native row loses reported/estimated provenance; this
        # ambiguous zero cannot establish a free request. Keep its raw ledger.
        total = nil if total == 0 && unmeasured?(tokens)
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
      tokens.input.nil? && tokens.output.nil? && tokens.to_h.values.all? { |value| value.nil? || value == 0 }
    end

    def reported_cost?(cost, tokens)
      return true if tokens.respond_to?(:reported_cost) && tokens.reported_cost

      cost.respond_to?(:reported?) && cost.reported?
    end
  end
end

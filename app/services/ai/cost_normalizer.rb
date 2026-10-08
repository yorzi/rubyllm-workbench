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
        return { recorded_cost: @value.total_cost, reported_cost: nil, estimated_cost: nil,
          cost_status: @value.total_cost.nil? ? "unknown" : "recorded", currency: "USD" }
      end

      if @model && tokens.to_h.any?
        estimated = RubyLLM::Cost.new(tokens:, model: @model, category: @category).total
        return { reported_cost: nil, recorded_cost: nil, estimated_cost: estimated, cost_status: "estimated", currency: "USD" } if estimated
      end

      { reported_cost: nil, recorded_cost: nil, estimated_cost: nil, cost_status: "unknown", currency: "USD" }
    end

    private

    def reported_cost?(cost, tokens)
      return true if tokens.respond_to?(:reported_cost) && tokens.reported_cost

      cost.respond_to?(:reported?) && cost.reported?
    end
  end
end

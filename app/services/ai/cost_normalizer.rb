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
        return { reported_cost: cost.total, estimated_cost: nil, cost_status: "reported", currency: "USD" }
      end

      if @model && tokens.to_h.any?
        estimated = RubyLLM::Cost.new(tokens:, model: @model, category: @category).total
        return { reported_cost: nil, estimated_cost: estimated, cost_status: "estimated", currency: "USD" } if estimated
      end

      { reported_cost: nil, estimated_cost: nil, cost_status: "unknown", currency: "USD" }
    end

    private

    def reported_cost?(cost, tokens)
      return true if tokens.respond_to?(:reported_cost) && tokens.reported_cost

      cost.respond_to?(:reported?) && cost.reported?
    end
  end
end

module Ai
  # Correlates provider-side RubyLLM notifications with the Run causing them.
  #
  # RubyLLM instruments its own chat object, which knows nothing about
  # application records. Instead of reaching into unstable payload internals,
  # the executor publishes the Run/Attempt it is executing and the
  # instrumentation adapter reads that context.
  class ExecutionContext < ActiveSupport::CurrentAttributes
    class ExecutionLeaseLost < StandardError; end

    attribute :run_id, :attempt_id, :agent_execution_token, :agent_execution_generation

    class << self
      def with(run_id:, attempt_id: nil, agent_execution_token: nil, agent_execution_generation: nil)
        previous = [ self.run_id, self.attempt_id, self.agent_execution_token, self.agent_execution_generation ]
        self.run_id = run_id
        self.attempt_id = attempt_id
        self.agent_execution_token = agent_execution_token
        self.agent_execution_generation = agent_execution_generation
        yield
      ensure
        self.run_id, self.attempt_id, self.agent_execution_token, self.agent_execution_generation = previous
      end
    end
  end
end

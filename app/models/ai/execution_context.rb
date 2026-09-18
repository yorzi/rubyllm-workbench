module Ai
  # Correlates provider-side RubyLLM notifications with the Run causing them.
  #
  # RubyLLM instruments its own chat object, which knows nothing about
  # application records. Instead of reaching into unstable payload internals,
  # the executor publishes the Run/Attempt it is executing and the
  # instrumentation adapter reads that context.
  class ExecutionContext < ActiveSupport::CurrentAttributes
    attribute :run_id, :attempt_id

    class << self
      def with(run_id:, attempt_id: nil)
        previous = [ self.run_id, self.attempt_id ]
        self.run_id = run_id
        self.attempt_id = attempt_id
        yield
      ensure
        self.run_id, self.attempt_id = previous
      end
    end
  end
end

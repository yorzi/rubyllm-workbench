module Ai
  class StructuredOutputError < StandardError
    attr_reader :code, :problems

    def initialize(problems)
      @code = "schema_validation"
      @problems = Array(problems)
      super("Structured output validation failed: #{@problems.join("; ")}")
    end
  end
end

module Ai
  module Knowledge
    # Evaluates a saved answer, rather than invoking its generating model again.
    class GroundedAnswerEvaluation < RubyLLM::Evaluation
      evaluator false

      def perform(input)
        input.fetch("answer_output")
      end

      def assertions
        assert_equal metadata.fetch("expected_status"), output.fetch("status"), "The saved answer status differs from the case reference."
        validated = GroundedResponse.parse!(JSON.generate(output), snapshot: input.fetch("answer_snapshot"))
        assert_equal output, validated
      end
    end
  end
end

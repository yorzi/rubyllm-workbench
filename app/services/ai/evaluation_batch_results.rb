module Ai
  class EvaluationBatchResults
    # Upstream candidate: RubyLLM 2.0.0 accepts duplicate, negative and
    # out-of-range normalized indices. Validate before Batch delivers ANY result
    # to a Chat/store. A check on batch.messages is already too late.
    # Keep this private-API workaround isolated to evaluation batch collection.
    module IndexValidation
      attr_accessor :workbench_expected_result_count

      private

      def result_slot_count(results)
        seen = {}
        results.each do |index, _result, _failure_status|
          unless index.is_a?(Integer) && index >= 0 && index < workbench_expected_result_count
            raise RubyLLM::Error, "Provider batch returned an invalid evaluation result index."
          end
          raise RubyLLM::Error, "Provider batch returned a duplicate evaluation result index." if seen[index]

          seen[index] = true
        end
        workbench_expected_result_count
      end
    end

    def self.call(batch, expected_count:)
      batch.extend(IndexValidation)
      batch.workbench_expected_result_count = expected_count
      batch.messages
    end
  end
end

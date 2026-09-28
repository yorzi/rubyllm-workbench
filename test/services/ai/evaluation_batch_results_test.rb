require "test_helper"

module Ai
  class EvaluationBatchResultsTest < ActiveSupport::TestCase
    class Provider
      attr_accessor :rows

      def batch_status(*) = :succeeded
      def batch_results(*) = rows
    end

    test "rejects every invalid collection before delivery or status mutation" do
      [ -1, 2, "0", nil, 0.5, 0 ].each do |invalid_index|
        batch = build_batch([ [ 0, Object.new, nil ], [ invalid_index, nil, :failed ] ])
        deliveries = []
        batch.define_singleton_method(:deliver) { |*args| deliveries << args }

        assert_raises(RubyLLM::Error) { EvaluationBatchResults.call(batch, expected_count: 2) }
        assert_empty deliveries
        assert_empty batch.statuses
      end
    end

    test "preserves unordered successful delivery and collects only once" do
      first, second = Object.new, Object.new
      batch = build_batch([ [ 1, second, nil ], [ 0, first, nil ] ])
      deliveries = []
      batch.define_singleton_method(:deliver) { |*args| deliveries << args }

      assert_equal [ first, second ], EvaluationBatchResults.call(batch, expected_count: 2)
      assert_equal [ first, second ], batch.messages
      assert_equal 2, deliveries.size
    end

    test "uses frozen evaluation count for partial results without provider count" do
      batch = build_batch([ [ 1, nil, :cancelled ] ], request_count: nil)

      assert_equal [ nil, nil ], EvaluationBatchResults.call(batch, expected_count: 2)
      assert_equal [ :failed, :cancelled ], batch.statuses
    end

    test "does not patch unrelated RubyLLM batches" do
      guarded = build_batch([])
      EvaluationBatchResults.call(guarded, expected_count: 2)

      refute build_batch([]).is_a?(EvaluationBatchResults::IndexValidation)
    end

    private

    def build_batch(rows, request_count: 2)
      provider = Provider.new
      provider.rows = rows
      RubyLLM::Batch.new(provider:, id: "synthetic", raw_status: "completed", completed: true, request_count:)
    end
  end
end

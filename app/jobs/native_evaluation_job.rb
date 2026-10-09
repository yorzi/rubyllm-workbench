class NativeEvaluationJob < ApplicationJob
  queue_as :default
  self.enqueue_after_transaction_commit = true

  def perform(run_id)
    Ai::Knowledge::NativeEvaluationExecutor.new(run_id).call
  end
end

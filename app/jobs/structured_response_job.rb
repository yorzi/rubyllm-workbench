class StructuredResponseJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    Ai::StructuredExecutor.new(run_id).call
  end
end

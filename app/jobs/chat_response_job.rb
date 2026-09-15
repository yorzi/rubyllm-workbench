class ChatResponseJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    Ai::ChatExecutor.new(run_id).call
  end
end

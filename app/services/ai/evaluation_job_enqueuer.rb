module Ai
  class EvaluationJobEnqueuer
    def self.call(job_class, *arguments)
      job = job_class.perform_later(*arguments)
      return job if job&.respond_to?(:successfully_enqueued?) && job.successfully_enqueued?

      enqueue_error = job.enqueue_error if job&.respond_to?(:enqueue_error)
      raise enqueue_error if enqueue_error

      raise ActiveJob::EnqueueError, "#{job_class.name} was not accepted by the queue adapter."
    end
  end
end

module Ai
  class QueueReadiness
    DELIVERY_TASK_KEY = "dispatch_agent_run_deliveries"
    REQUIRED_WORKER_QUEUE = "maintenance"
    Result = Struct.new(
      :state,
      :label,
      :details,
      :scheduler_ready,
      :dispatcher_ready,
      :maintenance_worker_ready,
      :due_agent_deliveries,
      keyword_init: true
    )

    def self.call
      new.call
    end

    def initialize(adapter: Rails.application.config.active_job.queue_adapter)
      @adapter = adapter.to_s
    end

    def call
      return test_adapter_result if @adapter == "test"
      return unmonitored_adapter_result unless solid_queue_adapter?

      processes = queue_processes

      scheduler_ready = processes.any? do |process|
        process.kind == "Scheduler" &&
          Array(process.metadata&.with_indifferent_access&.[](:recurring_schedule)).include?(DELIVERY_TASK_KEY)
      end
      dispatcher_ready = processes.any? { |process| process.kind == "Dispatcher" }
      maintenance_worker_ready = processes.any? do |process|
        process.kind == "Worker" && worker_handles_maintenance_queue?(process)
      end
      due_deliveries = due_agent_deliveries

      readiness_result(
        scheduler_ready:,
        dispatcher_ready:,
        maintenance_worker_ready:,
        due_deliveries:
      )
    rescue ActiveRecord::ActiveRecordError, SQLite3::Exception
      Result.new(
        state: :unknown,
        label: "Status unavailable",
        details: "Could not read the Solid Queue process records or Agent Run outbox.",
        scheduler_ready: false,
        dispatcher_ready: false,
        maintenance_worker_ready: false,
        due_agent_deliveries: nil
      )
    end

    private

    def solid_queue_adapter?
      @adapter == "solid_queue"
    end

    def queue_processes
      SolidQueue::Process.where(kind: %w[Scheduler Dispatcher Worker])
        .where(last_heartbeat_at: SolidQueue.process_alive_threshold.ago..)
        .to_a
    end

    def due_agent_deliveries
      AgentRunDelivery.ready_to_dispatch.count
    end

    def test_adapter_result
      Result.new(
        state: :test_adapter,
        label: "Test adapter",
        details: "Jobs are captured by the test process and are not run by Solid Queue.",
        scheduler_ready: nil,
        dispatcher_ready: nil,
        maintenance_worker_ready: nil,
        due_agent_deliveries: nil
      )
    end

    def unmonitored_adapter_result
      Result.new(
        state: :not_monitored,
        label: "Not monitored",
        details: "This panel checks Solid Queue process state; the configured job adapter is different.",
        scheduler_ready: nil,
        dispatcher_ready: nil,
        maintenance_worker_ready: nil,
        due_agent_deliveries: nil
      )
    end

    def worker_handles_maintenance_queue?(process)
      queues = process.metadata&.with_indifferent_access&.[](:queues).to_s.split(",")
      queues.include?("*") || queues.include?(REQUIRED_WORKER_QUEUE)
    end

    def readiness_result(scheduler_ready:, dispatcher_ready:, maintenance_worker_ready:, due_deliveries:)
      ready = scheduler_ready && dispatcher_ready && maintenance_worker_ready
      missing = []
      missing << "recurring Agent dispatcher schedule" unless scheduler_ready
      missing << "queue dispatcher" unless dispatcher_ready
      missing << "worker for the maintenance queue" unless maintenance_worker_ready

      Result.new(
        state: ready ? :ready : :needs_attention,
        label: ready ? "Ready" : "Needs attention",
        details: ready ? "Required process heartbeats were seen within the last five minutes." : "Missing recent heartbeat: #{missing.join(', ')}.",
        scheduler_ready:,
        dispatcher_ready:,
        maintenance_worker_ready:,
        due_agent_deliveries: due_deliveries
      )
    end
  end
end

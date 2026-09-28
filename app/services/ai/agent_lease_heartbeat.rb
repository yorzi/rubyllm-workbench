module Ai
  # Renews an Agent Run's execution lease from a background thread while a
  # long provider call is in flight. When a renewal is refused, or fails
  # non-transiently, the heartbeat marks the lease lost and stops; the worker
  # checks #lost? before each side effect.
  class AgentLeaseHeartbeat
    INTERVAL = 15.seconds
    # Stop retrying transient renewal errors this close to expiry.
    SAFETY_MARGIN = 5.seconds

    def initialize(run_id:, token:, generation:, expires_at:, interval: INTERVAL)
      @run_id = run_id
      @token = token
      @generation = generation
      @interval = interval
      @mutex = Mutex.new
      @condition = ConditionVariable.new
      @expires_at = expires_at
      @lost = false
      @stopped = false
    end

    def start
      @thread = Thread.new { beat until stop_requested? }
      self
    end

    def stop
      return unless @thread

      @mutex.synchronize do
        @stopped = true
        @condition.broadcast
      end
      @thread.join
      @thread = nil
    end

    def lost?
      @mutex.synchronize { @lost }
    end

    def expires_at
      @mutex.synchronize { @expires_at }
    end

    # Records a renewal made by the worker itself.
    def renewed!(at: Time.current)
      @mutex.synchronize { @expires_at = at + Run::AGENT_EXECUTION_LEASE_DURATION }
    end

    private

    def stop_requested?
      @mutex.synchronize do
        @condition.wait(@mutex, @interval) unless @stopped || @lost
        @stopped || @lost
      end
    end

    def beat
      renewed = ActiveRecord::Base.connection_pool.with_connection do
        Run.find(@run_id).renew_agent_execution_lease!(token: @token, generation: @generation)
      end
      renewed ? renewed! : mark_lost!
    rescue StandardError => error
      if Ai::TransientDatabaseError.match?(error) && Time.current < expires_at - SAFETY_MARGIN
        Rails.logger.warn("Agent Run ##{@run_id} lease heartbeat will retry: #{error.class}: #{error.message}")
        return
      end

      Rails.logger.error("Agent Run ##{@run_id} lease heartbeat failed: #{error.class}: #{error.message}")
      mark_lost!
    end

    def mark_lost!
      @mutex.synchronize { @lost = true }
    end
  end
end

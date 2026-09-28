require "test_helper"

class Ai::QueueReadinessTest < ActiveSupport::TestCase
  ProcessRow = Struct.new(:kind, :metadata)

  test "identifies the test adapter without claiming background jobs are healthy" do
    result = Ai::QueueReadiness.call

    assert_equal :test_adapter, result.state
    assert_equal "Test adapter", result.label
    assert_nil result.due_agent_deliveries
    assert_includes result.details, "not run by Solid Queue"
  end

  test "does not label a non-test non-Solid Queue adapter as the test adapter" do
    result = Ai::QueueReadiness.new(adapter: :async).call

    assert_equal :not_monitored, result.state
    assert_equal "Not monitored", result.label
    assert_includes result.details, "configured job adapter is different"
  end

  test "requires the recurring Agent schedule, dispatcher and maintenance worker" do
    processes = [
      ProcessRow.new("Scheduler", { "recurring_schedule" => [ Ai::QueueReadiness::DELIVERY_TASK_KEY ] }),
      ProcessRow.new("Dispatcher", {}),
      ProcessRow.new("Worker", { "queues" => "*" })
    ]
    result = readiness_for(processes, due_deliveries: 2).call

    assert_equal :ready, result.state
    assert_equal 2, result.due_agent_deliveries
    assert result.scheduler_ready
    assert result.dispatcher_ready
    assert result.maintenance_worker_ready
  end

  test "reports missing scheduler configuration and maintenance queue coverage" do
    processes = [
      ProcessRow.new("Scheduler", { "recurring_schedule" => [ "purge_stale_unattached_blobs" ] }),
      ProcessRow.new("Worker", { "queues" => "default" })
    ]
    result = readiness_for(processes, due_deliveries: 0).call

    assert_equal :needs_attention, result.state
    refute result.scheduler_ready
    refute result.dispatcher_ready
    refute result.maintenance_worker_ready
    assert_includes result.details, "queue dispatcher"
    assert_includes result.details, "worker for the maintenance queue"
  end

  private

  def readiness_for(processes, due_deliveries:)
    Ai::QueueReadiness.new(adapter: :solid_queue).tap do |readiness|
      readiness.define_singleton_method(:queue_processes) { processes }
      readiness.define_singleton_method(:due_agent_deliveries) { due_deliveries }
    end
  end
end

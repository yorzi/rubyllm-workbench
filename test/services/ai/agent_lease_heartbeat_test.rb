require "test_helper"

class Ai::AgentLeaseHeartbeatTest < ActiveSupport::TestCase
  # The heartbeat thread uses its own connection, so its writes must be
  # visible outside this test's transaction.
  self.use_transactional_tests = false

  setup do
    @project = create_project(name: "Heartbeat project #{SecureRandom.hex(3)}")
    @run = create_chat(@project).runs.create!(project: @project, operation: "agent", status: :queued, requested_by: "test", input_snapshot_json: {})
    assert @run.claim_agent_execution!(token: "worker-token", lease_duration: 2.seconds)
    @run.reload
  end

  teardown do
    @project&.destroy!
  end

  test "renews the lease until stopped" do
    heartbeat = Ai::AgentLeaseHeartbeat.new(run_id: @run.id, token: "worker-token", generation: @run.agent_execution_generation,
      expires_at: @run.agent_execution_expires_at, interval: 0.05).start
    sleep 0.3
    heartbeat.stop

    assert_not heartbeat.lost?
    assert_operator @run.reload.agent_execution_expires_at, :>, 4.minutes.from_now
  end

  test "marks the lease lost when renewal is refused" do
    heartbeat = Ai::AgentLeaseHeartbeat.new(run_id: @run.id, token: "stale-token", generation: @run.agent_execution_generation,
      expires_at: @run.agent_execution_expires_at, interval: 0.05).start
    sleep 0.3
    heartbeat.stop

    assert heartbeat.lost?
  end

  test "worker renewals move the known expiry forward" do
    heartbeat = Ai::AgentLeaseHeartbeat.new(run_id: @run.id, token: "worker-token", generation: 1, expires_at: 1.minute.ago)

    heartbeat.renewed!

    assert_operator heartbeat.expires_at, :>, 4.minutes.from_now
  end
end

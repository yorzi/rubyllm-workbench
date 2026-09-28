require "test_helper"
require "timeout"

class AgentRunCancellationRaceTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  PROVIDER_GATE_TIMEOUT = 10
  CANCELLATION_POLL_INTERVAL = 1.0

  class GatedProviderAgentRunJob < AgentRunJob
    class << self
      attr_accessor :provider_started, :provider_release
    end

    # Run the Agent step inline; continuation persistence has separate coverage.
    def step(_name, **, &block)
      continuation = Object.new
      continuation.define_singleton_method(:checkpoint!) { }
      block.arity.zero? ? block.call : block.call(continuation)
    end

    private

    def restore_agent
      super
      gates = self.class
      @run.chat.to_llm.define_singleton_method(:provider_completion) do |**_options|
        gates.provider_started << true
        gates.provider_release.pop
        RubyLLM::Message.new(role: :assistant, content: "Late response after cancellation.")
      end
    end
  end

  setup do
    GatedProviderAgentRunJob.provider_started = Queue.new
    GatedProviderAgentRunJob.provider_release = Queue.new
  end

  teardown do
    GatedProviderAgentRunJob.provider_release << true if @worker_thread&.alive?
    if @worker_thread&.join(PROVIDER_GATE_TIMEOUT).nil?
      @worker_thread.kill
      @worker_thread.join
    end
    @project&.destroy! if @project&.persisted?
  end

  test "cancellation during a blocked provider response prevents late assistant persistence" do
    @project = create_project(name: "Cancellation race #{SecureRandom.hex(4)}")
    chat = create_chat(@project)
    tools = Ai::ToolRegistry.snapshot(@project)
    run = chat.runs.create!(
      project: @project,
      operation: "agent",
      status: :queued,
      requested_by: "cancellation race test",
      input_snapshot_json: {
        "prompt" => "Wait for the response.",
        "tools" => tools,
        "tool_options" => {},
        "provider_tools" => [],
        "agent_definition" => {
          "id" => 94,
          "name" => "Cancellation race checker",
          "revision" => 1,
          "provider" => chat.provider.to_s,
          "model_id" => chat.model_id.to_s,
          "instructions" => "Reply after the provider returns.",
          "tool_keys" => tools.map { |tool| tool.fetch("key") },
          "provider_tools" => [],
          "options" => {}
        }
      }
    )
    delivery = AgentRunDelivery.record!(run:, intent: "execute", expected_generation: 0)

    @worker_thread = Thread.new do
      Rails.application.executor.wrap do
        ActiveRecord::Base.connection_pool.with_connection do
          with_provider_configuration(chat.provider) do
            GatedProviderAgentRunJob.perform_now(*delivery.job_arguments)
          end
        end
      end
    end

    Timeout.timeout(PROVIDER_GATE_TIMEOUT) { GatedProviderAgentRunJob.provider_started.pop }
    attempt = run.attempts.order(:sequence).last
    assert run.reload.running?
    assert attempt.running?

    Run.find(run.id).cancel!

    assert run.reload.cancelled?
    assert attempt.reload.cancelled?
    assert @worker_thread.alive?, "The worker should still be waiting at the provider boundary."

    # RubyLLM polls the persisted cancellation bit at one-second intervals.
    # Keep the response blocked until its post-response checkpoint will poll again.
    sleep CANCELLATION_POLL_INTERVAL + 0.1
    assert @worker_thread.alive?, "The provider response should remain blocked until explicitly released."
    GatedProviderAgentRunJob.provider_release << true

    assert @worker_thread.join(PROVIDER_GATE_TIMEOUT), "The Agent worker did not finish after cancellation."
    @worker_thread.value

    assert run.reload.cancelled?
    assert attempt.reload.cancelled?
    assert_not chat.messages.where(role: "assistant", content: "Late response after cancellation.").exists?
    assert_not run.result_summary.key?("agent_step_count")
    assert run.lifecycle_events.exists?(name: "ai.run.cancelled")
    refute run.lifecycle_events.where(name: "ai.agent.step").any? { |event|
      event.payload_json.fetch("step_status") == "completed"
    }
  ensure
    GatedProviderAgentRunJob.provider_release << true if @worker_thread&.alive?
  end
end

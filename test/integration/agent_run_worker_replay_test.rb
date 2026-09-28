require "test_helper"
require "tmpdir"

class AgentRunWorkerReplayTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  class CrashWindowAgent
    class << self
      attr_accessor :factory_marker_path, :effect_marker_path, :replay_marker_path
    end

    def initialize(chat, run)
      @chat = chat
      @run = run
    end

    def ask_later(prompt)
      @chat.messages.create!(role: "user", content: prompt)
    end

    def awaiting_approval?
      @run.tool_invocations.find_by(tool_key: "save_run_note")&.approval_pending? || false
    end

    def complete?
      @chat.messages.where(role: "assistant", content: "Replay completed.").exists?
    end

    def step
      tool_call = persisted_tool_calls.first
      message = if tool_call.nil?
        create_note_tool_call
      elsif tool_call.result.nil?
        execute_note_tool(tool_call)
      else
        @chat.messages.create!(role: "assistant", content: "Replay completed.")
      end

      yield Data.define(:content).new(message.content) if block_given?
      message
    end

    private

    def persisted_tool_calls
      RubyLLM::ActiveRecord::ToolCall.where(
        message_type: Message.polymorphic_name,
        message_id: @chat.messages.select(:id)
      ).order(:id)
    end

    def create_note_tool_call
      message = @chat.messages.create!(role: "assistant", content: "")
      RubyLLM::ActiveRecord::ToolCall.create!(
        message:,
        tool_call_id: SecureRandom.uuid,
        name: "save_run_note",
        arguments: { "note" => "Committed before worker interruption" },
        remote: false
      )
      message
    end

    def execute_note_tool(tool_call)
      result = Ai::Tools::SaveRunNote.new(project: @run.project, run: @run).execute(
        note: tool_call.arguments.fetch("note"),
        tool_call: tool_call.to_llm
      )

      marker = {
        "pid" => ::Process.pid,
        "artifact_id" => result.fetch("artifact_id"),
        "tool_call_id" => tool_call.tool_call_id
      }
      begin
        File.open(self.class.effect_marker_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
          file.write(JSON.generate(marker))
        end

        # The test kills this worker after the Artifact transaction commits but
        # before RubyLLM persists the ToolCall result.
        sleep 0.05 until false
      rescue Errno::EEXIST
        File.write(self.class.replay_marker_path, JSON.generate(marker), mode: "w", perm: 0o600)
      end

      result_message = @chat.messages.create!(role: "tool", content: JSON.generate(result))
      tool_call.update!(result: result_message)
      result_message
    end
  end

  setup do
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :solid_queue
    @drill_dir = Dir.mktmpdir("agent-run-worker-replay-")
    CrashWindowAgent.factory_marker_path = File.join(@drill_dir, "fake-agent.json")
    CrashWindowAgent.effect_marker_path = File.join(@drill_dir, "effect.json")
    CrashWindowAgent.replay_marker_path = File.join(@drill_dir, "replay.json")
  end

  teardown do
    stop_worker_supervisor
    restore_agent_factory
    if @project&.persisted?
      chat_ids = @project.chats.pluck(:id)
      message_ids = Message.where(chat_id: chat_ids).pluck(:id)
      RubyLLM::ActiveRecord::ToolCall.where(
        message_type: Message.polymorphic_name,
        message_id: message_ids
      ).delete_all
      @project.destroy!
    end
    ActiveJob::Base.queue_adapter = @original_queue_adapter
    FileUtils.remove_entry(@drill_dir) if @drill_dir && File.directory?(@drill_dir)
  end

  test "replays a committed local tool effect after a Solid Queue worker is killed" do
    @project = create_project(name: "Worker replay #{SecureRandom.hex(4)}")
    chat = create_chat(@project)
    tools = Ai::ToolRegistry.snapshot(@project)
    snapshot = {
      "prompt" => "Save a note, then report completion.",
      "tools" => tools,
      "tool_options" => {},
      "provider_tools" => [],
      "agent_definition" => {
        "id" => 93,
        "name" => "Worker replay checker",
        "revision" => 1,
        "provider" => chat.provider.to_s,
        "model_id" => chat.model_id.to_s,
        "instructions" => "Save the note and report completion.",
        "tool_keys" => tools.map { |tool| tool.fetch("key") },
        "provider_tools" => [],
        "options" => {}
      }
    }
    run = chat.runs.create!(
      project: @project,
      operation: "agent",
      status: :queued,
      requested_by: "worker replay test",
      input_snapshot_json: snapshot
    )
    initial_delivery = AgentRunDelivery.record!(run:, intent: "execute", expected_generation: 0)

    install_fake_agent_factory
    start_worker_supervisor
    dispatch_ready_deliveries
    wait_until("the first Agent step requests tool approval or reports a failure") do
      run.reload.waiting_for_approval? || run.failed?
    end
    assert File.exist?(CrashWindowAgent.factory_marker_path), "The provider-free fake Agent factory did not run."
    assert run.waiting_for_approval?, "#{run.status}: #{run.error_summary}"
    invocation = run.tool_invocations.find_by!(tool_key: "save_run_note")
    Ai::ApprovalService.decide!(invocation:, decision: "approved", note: "Approved for replay drill")

    dispatch_ready_deliveries
    wait_until("the approved tool commits its Artifact") { File.exist?(CrashWindowAgent.effect_marker_path) }
    effect = JSON.parse(File.read(CrashWindowAgent.effect_marker_path))
    worker = SolidQueue::Process.find_by!(pid: effect.fetch("pid"), kind: "Worker")
    tool_call = persisted_tool_call(chat, effect.fetch("tool_call_id"))
    artifact = run.artifacts.find_by!(source_tool_call_id: tool_call.tool_call_id)

    assert_equal artifact.id, effect.fetch("artifact_id")
    assert_nil tool_call.result
    assert run.reload.agent_execution_expires_at.future?

    ::Process.kill("KILL", worker.pid)
    wait_until("Solid Queue records the interrupted job and starts a replacement worker") do
      replacement_worker = SolidQueue::Process.where(kind: "Worker", supervisor_id: @supervisor_record.id)
        .where.not(pid: worker.pid).exists?
      failed_job = SolidQueue::FailedExecution.joins(:job).where(
        solid_queue_jobs: { class_name: AgentRunJob.name }
      ).exists?
      replacement_worker && failed_job
    end

    assert run.reload.running?
    assert_equal 1, run.artifacts.where(source_tool_call_id: tool_call.tool_call_id).count
    assert_nil tool_call.reload.result

    run.update_columns(agent_execution_expires_at: 1.second.ago)
    AgentRunDeliveryDispatcherJob.perform_now

    wait_until("the replayed delivery completes the Agent Run") { run.reload.succeeded? }
    replay = JSON.parse(File.read(CrashWindowAgent.replay_marker_path))
    tool_call.reload
    artifact.reload

    assert_equal effect.fetch("artifact_id"), replay.fetch("artifact_id")
    assert_equal effect.fetch("tool_call_id"), replay.fetch("tool_call_id")
    assert_equal tool_call.tool_call_id, artifact.source_tool_call_id
    assert_equal 1, run.artifacts.where(source_tool_call_id: tool_call.tool_call_id).count
    assert tool_call.result
    assert run.tool_invocations.find_by!(tool_call_id: tool_call.tool_call_id).succeeded?
    assert_operator run.agent_execution_generation, :>, initial_delivery.expected_generation
    assert_nil run.agent_execution_token
  end

  private

  def persisted_tool_call(chat, tool_call_id)
    RubyLLM::ActiveRecord::ToolCall.where(
      message_type: Message.polymorphic_name,
      message_id: chat.messages.select(:id)
    ).find_by!(tool_call_id:)
  end

  def dispatch_ready_deliveries
    AgentRunDeliveryDispatcherJob.perform_now
  end

  def install_fake_agent_factory
    @original_restore_agent = AgentRunJob.instance_method(:restore_agent)
    AgentRunJob.define_method(:restore_agent) do
      File.write(AgentRunWorkerReplayTest::CrashWindowAgent.factory_marker_path, "#{::Process.pid}", mode: "w", perm: 0o600)
      @agent = AgentRunWorkerReplayTest::CrashWindowAgent.new(@run.chat, @run)
      @tool_recorder = Ai::ToolInvocationRecorder.new(
        run: @run,
        chat: @run.chat,
        agent_execution_token: @lease_token,
        agent_execution_generation: @lease_generation
      )
    end
    AgentRunJob.send(:private, :restore_agent)
  end

  def restore_agent_factory
    return unless @original_restore_agent

    AgentRunJob.define_method(:restore_agent, @original_restore_agent)
    AgentRunJob.send(:private, :restore_agent)
    @original_restore_agent = nil
  end

  def start_worker_supervisor
    ActiveRecord::Base.connection_handler.clear_all_connections!
    @supervisor_pid = fork do
      SolidQueue::Supervisor.start(
        mode: :fork,
        skip_recurring: true,
        dispatchers: [ { batch_size: 50, polling_interval: 0.05 } ],
        workers: [ { queues: "default", threads: 1, processes: 1, polling_interval: 0.05 } ]
      )
      exit! 0
    end

    wait_until("Solid Queue registers its supervisor and worker") do
      @supervisor_record = SolidQueue::Process.find_by(pid: @supervisor_pid)
      @supervisor_record = nil unless @supervisor_record&.kind&.start_with?("Supervisor")
      worker = SolidQueue::Process.where(kind: "Worker", supervisor_id: @supervisor_record&.id).first
      @supervisor_record && worker
    end
  end

  def stop_worker_supervisor
    return unless @supervisor_pid

    if process_running?(@supervisor_pid)
      ::Process.kill("TERM", @supervisor_pid)
      wait_until("Solid Queue supervisor stops", timeout: 10) { process_reaped?(@supervisor_pid) }
    end
  rescue Minitest::Assertion
    worker_pids = SolidQueue::Process.where(supervisor_id: @supervisor_record&.id, kind: "Worker").pluck(:pid)
    worker_pids.each { |pid| ::Process.kill("KILL", pid) if process_running?(pid) }
    ::Process.kill("KILL", @supervisor_pid) if process_running?(@supervisor_pid)
    process_reaped?(@supervisor_pid)
  end

  def process_running?(pid)
    ::Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end

  def process_reaped?(pid)
    return true unless process_running?(pid)

    ::Process.waitpid(pid, ::Process::WNOHANG).present?
  rescue Errno::ECHILD
    true
  end

  def wait_until(description, timeout: 20)
    deadline = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + timeout
    loop do
      return true if yield
      flunk("Timed out waiting for #{description}") if ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.05
    end
  end
end

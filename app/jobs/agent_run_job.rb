class AgentRunJob < ApplicationJob
  include ActiveJob::Continuable

  queue_as :default
  self.enqueue_after_transaction_commit = false
  LEASE_HEARTBEAT_INTERVAL = 15.seconds
  LEASE_SAFETY_MARGIN = 5.seconds
  MAX_AGENT_STEPS = 40

  ExecutionLeaseLost = Ai::ExecutionContext::ExecutionLeaseLost
  class LeaseCheckUnavailable < StandardError; end
  class InterruptedStepError < StandardError; end
  class StepLimitError < StandardError; end

  def perform(run_id, execution_intent = "execute", approval_invocation_id = nil, expected_generation = nil)
    @job_arguments = [ run_id, execution_intent, approval_invocation_id, expected_generation ]
    @execution_intent = execution_intent.to_s
    @approval_invocation_id = approval_invocation_id
    @expected_generation = expected_generation
    @run = Run.includes(:chat, :attempts).find(run_id)
    return if @run.terminal?

    @lease_token = SecureRandom.uuid
    claim_run
    if @unclaimed
      reschedule_after_active_lease if @lease_busy
      return
    end
    return if @run.reload.terminal? || @run.waiting_for_approval?

    # Agent instances and callback closures are process-local, so rebuild
    # them on every continuation resume from the immutable Run snapshot.
    restore_agent
    step(:persist_initial_prompt) { persist_initial_prompt }
    step(:execute_agent_steps, isolated: true) do |continuation_step|
      execute_agent_steps(continuation_step)
    end
  rescue ExecutionLeaseLost => error
    @needs_recovery = true
    Rails.logger.info("Agent Run ##{@run&.id} stopped after losing its execution lease: #{error.message}")
  rescue RubyLLM::CancelledError => error
    @tool_recorder&.sync!(failure: error)
    active_attempt = @run&.attempts&.order(sequence: :desc, id: :desc)&.find { |attempt| attempt.queued? || attempt.running? }
    cancelled_attempt = @run&.attempts&.order(sequence: :desc, id: :desc)&.first if @run&.cancelled?
    cancelled_attempt = nil unless cancelled_attempt&.cancelled?
    attempt_to_cancel = active_attempt || cancelled_attempt
    if @attempt_recorder || attempt_to_cancel
      recorder = @attempt_recorder || Ai::AttemptRecorder.new(@run, attempt: attempt_to_cancel, chat: @run.chat, continuation: true)
      recorder.cancel!(error, usage_ids_before: @usage_ids_before || [])
    end
    @run&.cancel!
  rescue StandardError => error
    if transient_lease_error?(error)
      @needs_recovery = true
      @recovery_error = error
      Rails.logger.warn("Agent Run ##{@run&.id} will recover after a temporary lease database error: #{error.class}: #{error.message}")
      return
    end
    if @run&.terminal?
      Rails.logger.info("Agent Run ##{@run.id} stopped after a late error on a terminal Run: #{error.class}")
      return
    end
    begin
      ensure_agent_lease! if @lease_token
    rescue ExecutionLeaseLost => lease_error
      Rails.logger.info("Agent Run ##{@run&.id} stopped after losing its execution lease: #{lease_error.message}")
      @needs_recovery = true
      return
    rescue LeaseCheckUnavailable => lease_error
      @needs_recovery = true
      @recovery_error = lease_error
      Rails.logger.warn("Agent Run ##{@run&.id} will recover after a temporary lease check failure: #{lease_error.message}")
      return
    end
    if @run&.chat
      with_agent_execution_context do
        with_agent_execution_lease_lock do
          Ai::ToolErrorFinalizer.new(@run.chat, error).call
        end
      end
    end
    @tool_recorder&.sync!(failure: error)
    begin
      fail_run(error) if @run
    rescue ExecutionLeaseLost => lease_error
      Rails.logger.info("Agent Run ##{@run&.id} stopped after losing its execution lease: #{lease_error.message}")
    end
  ensure
    stop_lease_heartbeat
    release_execution_lease
    schedule_recovery if @needs_recovery
  end

  private

  def claim_run
    @run.reload
    if @run.terminal?
      @unclaimed = true
      return
    end

    unless @run.claim_agent_execution!(
      token: @lease_token,
      intent: @execution_intent,
      approval_invocation_id: @approval_invocation_id,
      expected_generation: @expected_generation
    )
      @run.reload
      runnable_status = @execution_intent == "approval" ? %w[waiting_for_approval running] : %w[queued running]
      @lease_busy = runnable_status.include?(@run.status) &&
        @run.agent_execution_token.present? && @run.agent_execution_expires_at&.future?
      @unclaimed = true
      return
    end

    @run.reload
    @claimed = true
    @lease_generation = @run.agent_execution_generation
    @lease_expires_at = @run.agent_execution_expires_at
    start_lease_heartbeat
  end

  def restore_agent
    snapshot = agent_snapshot
    tool_keys = Array(snapshot.fetch("tool_keys"))
    verify_frozen_tool_contract!(tool_keys)
    tool_definitions = Ai::ChatTooling.new(chat: @run.chat, project: @run.project, run: @run).tool_definitions
    missing_tools = tool_keys - tool_definitions.map(&:key)
    raise ArgumentError, "Agent tools are no longer registered: #{missing_tools.join(', ')}" if missing_tools.any?

    tool_instances = tool_keys.filter_map do |key|
      tool_definitions.find { |definition| definition.key == key }&.tool_instance(run: @run)
    end

    agent_class = Class.new(RubyLLM::Agent)
    agent_class.chat_model Chat
    agent_class.model(snapshot.fetch("model_id"), provider: snapshot.fetch("provider").to_sym)
    agent_class.instructions(snapshot.fetch("instructions"), persist: false)
    agent_class.inputs :tool_instances
    agent_class.tools { tool_instances }
    provider_tools = Array(snapshot.fetch("provider_tools")).map(&:to_sym)
    agent_class.provider_tools(*provider_tools) if provider_tools.any?
    agent_class.tool_options(**Ai::ToolExecutionPolicy.ruby_llm_options(@run.input_snapshot["tool_options"]))

    options = snapshot.fetch("options", {})
    agent_class.temperature(options.fetch("temperature")) if options.key?("temperature")
    agent_class.max_output_tokens(options.fetch("max_output_tokens")) if options.key?("max_output_tokens")

    @agent = agent_class.new(
      chat: @run.chat,
      inputs: { tool_instances: tool_instances },
      persist_instructions: false
    )
    fence_usage_persistence!
    @tool_recorder = Ai::ToolInvocationRecorder.new(
      run: @run,
      chat: @run.chat,
      agent_execution_token: @lease_token,
      agent_execution_generation: @lease_generation
    ).attach
  end

  def persist_initial_prompt
    with_agent_execution_context do
      user_messages = @run.chat.messages.where(role: "user")
      @agent.ask_later(@run.input_snapshot.fetch("prompt")) unless user_messages.exists?
    end
  end

  def execute_agent_steps(continuation_step)
    loop do
      ensure_agent_lease!
      @run.reload
      return if @run.terminal?

      if @agent.awaiting_approval?
        if reconcile_interrupted_attempt == :retry
          continuation_step.checkpoint!
          next
        end
        wait_for_approval
        return
      end
      if @agent.complete?
        if reconcile_interrupted_attempt == :retry
          continuation_step.checkpoint!
          next
        end
        break
      end

      if pending_tool_execution?
        reconcile_interrupted_attempt
        execute_pending_tools
      else
        execute_one_step
      end
      @run.reload
      return if @run.terminal?

      continuation_step.checkpoint!
    end

    completed = @run.succeed!(
      completed_summary,
      agent_execution_token: @lease_token,
      agent_execution_generation: @lease_generation
    )
    raise ExecutionLeaseLost, "the worker no longer owns this Run" unless completed
  end

  def execute_one_step
    ensure_agent_lease!
    fail_interrupted_attempt!

    attempt = current_or_next_attempt
    if attempt.sequence > MAX_AGENT_STEPS
      raise StepLimitError, "Agent Run reached its #{MAX_AGENT_STEPS}-step limit."
    end
    @tool_recorder.attempt = attempt
    @attempt_recorder = Ai::AttemptRecorder.new(@run, attempt:, chat: @run.chat, continuation: true)
    @usage_ids_before = @run.chat.ruby_llm_usages.pluck(:id)
    message_ids_before = @run.chat.messages.pluck(:id)
    step_number = attempt.sequence
    with_agent_execution_lease_lock do
      @attempt_recorder.start!
      attempt.update!(metadata_json: attempt.metadata_json.to_h.merge(
        "usage_ids_before" => @usage_ids_before,
        "message_ids_before" => message_ids_before
      ))
      emit_step_event(step_number, attempt, "started")
    end

    response = with_agent_execution_context(attempt_id: attempt.id) do
      @agent.step do |chunk|
        content = chunk.content.to_s
        next if content.blank?

        with_agent_execution_lease_lock do
          @attempt_recorder.observe!(content)
          latest_assistant_message&.broadcast_append_chunk(content)
        end
      end
    end
    @tool_recorder.sync!

    source_message_id = latest_assistant_message&.id
    @run.with_lock do
      @run.reload
      if @run.cancelled?
        @attempt_recorder.cancel!(nil, usage_ids_before: @usage_ids_before)
        next
      end
      next if @run.terminal?

      assert_agent_lease_within_lock!
      @run.update!(agent_execution_expires_at: Time.current + Run::AGENT_EXECUTION_LEASE_DURATION)
      citation_artifact = Ai::CitationSetRecorder.new(
        run: @run,
        attempt: attempt,
        response: response,
        source_message_id: source_message_id
      ).call
      @attempt_recorder.finish_step!(response, usage_ids_before: @usage_ids_before)
      save_step_summary(step_number, response, source_message_id, citation_artifact)
      status = @agent.awaiting_approval? ? "awaiting_approval" : "completed"
      emit_step_event(step_number, attempt, status)
    end
    @attempt_recorder = nil
    @usage_ids_before = []
  end

  def execute_pending_tools
    ensure_agent_lease!
    attempt = @run.attempts.order(sequence: :desc, id: :desc).first
    @tool_recorder.attempt = attempt
    @tool_recorder.sync!
    @attempt_recorder = nil
    @usage_ids_before = []
    with_agent_execution_context(attempt_id: attempt&.id) do
      @agent.step
    end
    @tool_recorder.sync!
  end

  def pending_tool_execution?
    message = @run.chat.messages.reorder(id: :desc).first
    message&.role.to_s == "assistant" && message.respond_to?(:tool_call?) && message.tool_call?
  end

  def current_or_next_attempt
    last_attempt = @run.attempts.order(sequence: :desc, id: :desc).first
    return last_attempt if last_attempt&.queued? || last_attempt&.running?

    @run.attempts.create!(
      sequence: @run.attempts.maximum(:sequence).to_i + 1,
      provider: agent_snapshot.fetch("provider"),
      model_id: agent_snapshot.fetch("model_id"),
      status: :queued
    )
  end

  def fail_interrupted_attempt!
    @run.with_lock do
      @run.reload
      return if @run.terminal?
      assert_agent_lease_within_lock!

      attempt = @run.attempts.order(sequence: :desc, id: :desc).first
      next unless attempt&.running?

      error = InterruptedStepError.new("Worker restarted before an assistant response was persisted.")
      recorder = Ai::AttemptRecorder.new(@run, attempt:, chat: @run.chat, continuation: true)
      usage_ids_before = Array(attempt.metadata_json.to_h["usage_ids_before"]).map(&:to_i)
      recorder.fail_step!(error, usage_ids_before:)
    end
  end

  def wait_for_approval
    attempt = @run.attempts.order(sequence: :desc, id: :desc).first
    @tool_recorder.attempt = attempt
    @tool_recorder.sync!
    pending_invocations = @run.tool_invocations.waiting_for_approval.order(:id).to_a
    pending = pending_invocations.map(&:tool_key)
    summary = @run.result_summary.merge(
      "pending_tool_calls" => pending,
      "pending_tool_call_ids" => pending_invocations.map(&:id)
    )
    waiting = @run.wait_for_approval!(
      summary,
      attempt_id: attempt&.id,
      agent_execution_token: @lease_token,
      agent_execution_generation: @lease_generation
    )
    raise ExecutionLeaseLost, "the worker no longer owns this Run" unless waiting
  end

  def reconcile_interrupted_attempt
    with_agent_execution_lease_lock do
      attempt = @run.attempts.order(sequence: :desc, id: :desc).first
      next unless attempt&.running?

      assistant_message = latest_assistant_message
      next unless assistant_message&.created_at && attempt.started_at && assistant_message.created_at >= attempt.started_at
      message_ids_before = Array(attempt.metadata_json.to_h["message_ids_before"]).map(&:to_i)
      next if message_ids_before.include?(assistant_message.id)

      unless complete_assistant_response?(assistant_message)
        interrupted_error = InterruptedStepError.new("Worker stopped before an assistant response was persisted.")
        recorder = Ai::AttemptRecorder.new(@run, attempt:, chat: @run.chat, continuation: true)
        usage_ids_before = Array(attempt.metadata_json.to_h["usage_ids_before"]).map(&:to_i)
        recorder.fail_step!(interrupted_error, usage_ids_before:)
        assistant_message.destroy!
        @run.chat.reload
        next :retry
      end

      @tool_recorder.attempt = attempt
      @tool_recorder.sync!
      @attempt_recorder = Ai::AttemptRecorder.new(@run, attempt:, chat: @run.chat, continuation: true)
      @usage_ids_before = Array(attempt.metadata_json.to_h["usage_ids_before"]).map(&:to_i)
      @attempt_recorder.finish_step!(assistant_message, usage_ids_before: @usage_ids_before)
      citation_artifact = Ai::CitationSetRecorder.new(
        run: @run,
        attempt: attempt,
        response: assistant_message,
        source_message_id: assistant_message.id
      ).call
      save_step_summary(attempt.sequence, assistant_message, assistant_message.id, citation_artifact)
      emit_step_event(attempt.sequence, attempt, "completed")
      @attempt_recorder = nil
      @usage_ids_before = []
      :completed
    end
  end

  def complete_assistant_response?(message)
    message.content.present? || message.tool_call? || message.server_tool_calls.any? ||
      message.citations.any? || message.attachments.attached?
  end

  def save_step_summary(step_number, response, source_message_id, citation_artifact)
    summary = @run.result_summary.deep_stringify_keys
    summary["agent_definition"] = agent_snapshot.slice("id", "name", "revision")
    summary["agent_step_count"] = step_number
    summary["last_agent_step"] = {
      "step_number" => step_number,
      "status" => @agent.awaiting_approval? ? "awaiting_approval" : "completed",
      "message_id" => (response.id if response.respond_to?(:id))
    }.compact
    summary["source_message_id"] = source_message_id if source_message_id
    if citation_artifact
      summary["citation_artifact_ids"] = (Array(summary["citation_artifact_ids"]) + [ citation_artifact.id ]).uniq
      summary["citation_artifact_id"] = citation_artifact.id
      summary["citation_count"] = citation_artifact.metadata_json["citation_count"]
    end

    provider_calls = provider_tool_call_records(response)
    if provider_calls.any?
      summary["provider_tool_calls"] = (Array(summary["provider_tool_calls"]) + provider_calls).last(100)
      summary["provider_tool_step_count"] = Array(summary["provider_tool_calls"]).size
    end
    summary["partial_output"] = @attempt_recorder.partial_output if @attempt_recorder.partial_output.present?
    @run.update!(result_summary_json: summary) unless @run.reload.terminal?
  end

  def completed_summary
    summary = @run.result_summary.deep_stringify_keys
    summary["agent_definition"] = agent_snapshot.slice("id", "name", "revision")
    summary["agent_step_count"] ||= 0
    summary.delete("pending_tool_calls")
    summary.delete("pending_tool_call_ids")
    summary
  end

  def emit_step_event(step_number, attempt, status)
    definition = agent_snapshot
    Ai::LifecycleEventRecorder.emit(
      "ai.agent.step",
      run_id: @run.id,
      project_id: @run.project_id,
      attempt_id: attempt.id,
      agent_definition_id: definition.fetch("id"),
      agent_revision: definition.fetch("revision"),
      step_number: step_number,
      step_status: status,
      status: @run.status,
      event_key: "agent-run:#{@run.id}:step:#{step_number}:#{status}"
    )
  end

  def latest_assistant_message
    @run.chat.messages.where(role: "assistant").reorder(id: :desc).first
  end

  def provider_tool_call_records(response)
    return [] unless response.respond_to?(:server_tool_calls)

    Array(response.server_tool_calls).filter_map do |call|
      data = call.respond_to?(:to_h) ? call.to_h : call
      next unless data.is_a?(Hash)

      record = {
        "type" => data[:type] || data["type"],
        "name" => data[:name] || data["name"],
        "id" => data[:id] || data["id"],
        "input" => Ai::ToolPayloadSanitizer.call(data[:input] || data["input"])
      }.compact
      record if record.any?
    end
  end

  def agent_snapshot
    @agent_snapshot ||= @run.input_snapshot.fetch("agent_definition")
  end

  def verify_frozen_tool_contract!(tool_keys)
    input_snapshot = @run.input_snapshot
    frozen_tools = Array(input_snapshot.fetch("tools", [])).map do |tool|
      tool.respond_to?(:deep_stringify_keys) ? tool.deep_stringify_keys : tool
    end
    frozen_keys = frozen_tools.filter_map { |tool| tool["key"].to_s.presence if tool.is_a?(Hash) }
    unless frozen_keys.sort == tool_keys.map(&:to_s).sort
      raise ArgumentError, "Agent Run tool snapshot does not match its definition snapshot."
    end

    current_tools = Ai::ChatTooling.snapshot(@run.project)
      .select { |tool| frozen_keys.include?(tool.fetch("key")) }
      .map(&:deep_stringify_keys)
    frozen_contract = frozen_tools.sort_by { |tool| tool.fetch("key") }
    current_contract = current_tools.sort_by { |tool| tool.fetch("key") }
    return if frozen_contract == current_contract

    raise ArgumentError, "A registered tool changed after this Agent Run was queued. Create a new Run to use the current tool contract."
  end

  def reschedule_after_active_lease
    @run.reload
    expires_at = @run.agent_execution_expires_at
    return unless expires_at

    AgentRunDelivery.record!(
      run: @run,
      intent: @execution_intent,
      approval_invocation_id: @approval_invocation_id,
      expected_generation: @run.agent_execution_generation,
      available_at: expires_at + 1.second,
      dedupe_key: "busy-lease:#{@run.id}:#{@run.agent_execution_generation}:#{@execution_intent}:#{@approval_invocation_id || '-'}"
    )
  end

  def start_lease_heartbeat
    @lease_heartbeat_mutex = Mutex.new
    @lease_heartbeat_condition = ConditionVariable.new
    @lease_heartbeat_stopped = false
    run_id = @run.id
    token = @lease_token
    generation = @lease_generation

    @lease_heartbeat_thread = Thread.new do
      loop do
        stopped = @lease_heartbeat_mutex.synchronize do
          @lease_heartbeat_condition.wait(@lease_heartbeat_mutex, LEASE_HEARTBEAT_INTERVAL)
          @lease_heartbeat_stopped
        end
        break if stopped

        begin
          renewed = ActiveRecord::Base.connection_pool.with_connection do
            Run.find(run_id).renew_agent_execution_lease!(token:, generation:)
          end
          unless renewed
            @lease_lost = true
            break
          end

          @lease_expires_at = Time.current + Run::AGENT_EXECUTION_LEASE_DURATION
        rescue StandardError => error
          if transient_lease_error?(error) && Time.current < @lease_expires_at - LEASE_SAFETY_MARGIN
            Rails.logger.warn("Agent Run ##{run_id} lease heartbeat will retry: #{error.class}: #{error.message}")
            next
          end

          @lease_lost = true
          Rails.logger.error("Agent Run ##{run_id} lease heartbeat failed: #{error.class}: #{error.message}")
          break
        end
      end
    end
  end

  def ensure_agent_lease!
    raise ExecutionLeaseLost, "the worker no longer owns this Run" if @lease_lost

    renewed = ActiveRecord::Base.connection_pool.with_connection do
      Run.find(@run.id).renew_agent_execution_lease!(token: @lease_token, generation: @lease_generation)
    end
    raise ExecutionLeaseLost, "the worker no longer owns this Run" unless renewed

    @lease_expires_at = Time.current + Run::AGENT_EXECUTION_LEASE_DURATION
  rescue StandardError => error
    raise unless transient_lease_error?(error)

    raise LeaseCheckUnavailable, "#{error.class}: #{error.message}", cause: error
  end

  def assert_agent_lease_within_lock!
    @run.assert_agent_execution_lease!(token: @lease_token, generation: @lease_generation)
  end

  def with_agent_execution_lease_lock
    @run.with_lock do
      @run.reload
      assert_agent_lease_within_lock!
      yield
    end
  end

  def with_agent_execution_context(attempt_id: nil, &block)
    Ai::ExecutionContext.with(
      run_id: @run.id,
      attempt_id:,
      agent_execution_token: @lease_token,
      agent_execution_generation: @lease_generation,
      &block
    )
  end

  def fence_usage_persistence!
    ruby_llm_chat = @run.chat.to_llm
    recorder = ruby_llm_chat.instance_variable_get(:@usage_recorder)
    return unless recorder

    token = @lease_token
    generation = @lease_generation
    ruby_llm_chat.usage_recorder = lambda do |entry|
      @run.with_lock do
        @run.reload
        @run.assert_agent_execution_lease!(token:, generation:)
        recorder.call(entry)
      end
    end
  end

  def stop_lease_heartbeat
    return unless @lease_heartbeat_thread

    @lease_heartbeat_mutex.synchronize do
      @lease_heartbeat_stopped = true
      @lease_heartbeat_condition.broadcast
    end
    @lease_heartbeat_thread.join
    @lease_heartbeat_thread = nil
  end

  def release_execution_lease
    return unless @run && @lease_token

    @lease_release_succeeded = ActiveRecord::Base.connection_pool.with_connection do
      Run.find_by(id: @run.id)&.release_agent_execution_lease!(token: @lease_token, generation: @lease_generation)
    end
  rescue StandardError => error
    @lease_release_succeeded = false
    Rails.logger.warn("Agent Run ##{@run.id} lease release failed: #{error.class}: #{error.message}")
  end

  def schedule_recovery
    return unless @run && @job_arguments

    current = Run.find_by(id: @run.id)
    return unless current
    return if current&.terminal?
    return if current&.agent_execution_token.present? && current.agent_execution_token != @lease_token

    run_at = if @lease_release_succeeded || current&.agent_execution_token.blank?
      Time.current + 1.second
    else
      [ current&.agent_execution_expires_at || @lease_expires_at || Time.current, Time.current ].max + 1.second
    end
    arguments = @claimed ? [ @run.id, "execute" ] : @job_arguments
    AgentRunDelivery.record!(
      run: current,
      intent: arguments[1],
      approval_invocation_id: arguments[2],
      expected_generation: @claimed ? @lease_generation : arguments[3],
      available_at: run_at,
      dedupe_key: "ensure-recovery:#{@run.id}:#{arguments[1]}:#{arguments[2] || '-'}:#{@lease_generation || current.agent_execution_generation}:#{run_at.to_i / 300}"
    )
  rescue StandardError => error
    Rails.logger.error("Agent Run ##{@run&.id} recovery enqueue failed: #{error.class}: #{error.message}")
  end

  def transient_lease_error?(error)
    transient_names = %w[
      ActiveRecord::ConnectionNotEstablished
      ActiveRecord::ConnectionTimeoutError
      ActiveRecord::ConnectionFailed
      ActiveRecord::Deadlocked
      ActiveRecord::LockWaitTimeout
      SQLite3::BusyException
      SQLite3::LockedException
      PG::ConnectionBad
      PG::UnableToSend
      Mysql2::Error::TimeoutError
    ]
    current = error
    while current
      return true if transient_names.include?(current.class.name)

      current = current.cause
    end
    false
  end

  def fail_run(error)
    @run.with_lock do
      @run.reload
      return if @run.terminal?
      unless @run.owns_active_agent_execution_lease?(@lease_token, generation: @lease_generation)
        raise ExecutionLeaseLost, "the worker no longer owns this Run"
      end

      attempt = @run.attempts.order(sequence: :desc, id: :desc).find { |record| record.queued? || record.running? }
      if attempt
        recorder = @attempt_recorder || Ai::AttemptRecorder.new(@run, attempt:, chat: @run.chat, continuation: true)
        recorder.fail!(error, usage_ids_before: @usage_ids_before || [])
      else
        @run.fail!(
          error,
          agent_execution_token: @lease_token,
          agent_execution_generation: @lease_generation
        )
      end
    end
  end
end

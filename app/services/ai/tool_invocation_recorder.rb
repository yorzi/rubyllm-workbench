module Ai
  class ToolInvocationRecorder
    def initialize(run:, chat:, attempt: nil, agent_execution_token: nil, agent_execution_generation: nil)
      @run = run
      @chat = chat
      @attempt = attempt
      @agent_execution_token = agent_execution_token
      @agent_execution_generation = agent_execution_generation
      @mutex = Mutex.new
    end

    def attempt=(attempt)
      @attempt = attempt
    end

    def attach
      return self unless @chat.respond_to?(:before_tool_call)

      if @agent_execution_token
        @chat.before_tool_call { |_tool_call| with_agent_execution_lease { true } }
      end
      @chat.before_tool_call { |tool_call| mark_running(tool_call) }
      @chat.after_message { |_message| sync! }
      self
    end

    def sync!(failure: nil)
      if @agent_execution_token
        with_agent_execution_lease { sync_persisted_records(failure:) }
      else
        @run.with_lock do
          @run.reload
          sync_persisted_records(failure:)
        end
      end
    end

    private

    # RubyLLM 2.0 can mark a tool call as remote; preserve that flag for inspection.
    def remote?(tool_call)
      return false unless tool_call.respond_to?(:remote?)

      tool_call.remote? == true
    rescue StandardError
      false
    end

    def persisted_tool_calls
      RubyLLM::ActiveRecord::ToolCall.where(
        message_type: Message.polymorphic_name,
        message_id: @chat.messages.select(:id)
      ).includes(:result).order(:id)
    end

    def mark_running(tool_call)
      with_agent_execution_lease do
        @mutex.synchronize do
          invocation = find_or_initialize(tool_call.id, tool_call.name)
          invocation.assign_attributes(
            attempt: @attempt,
            status: :running,
            arguments_json: Ai::ToolPayloadSanitizer.call(tool_call.arguments),
            started_at: invocation.started_at || Time.current,
            remote: remote?(tool_call)
          )
          invocation.save!
          notify("ai.tool.requested", invocation, tool_call_id: tool_call.id)
        end
      end
    end

    def sync_persisted_records(failure:)
      @mutex.synchronize do
        unless @run.terminal?
          persisted_tool_calls.each do |tool_call_record|
            sync_record(tool_call_record, failure:)
          end
        end
        @run.tool_invocations.reload
      end
    end

    def sync_record(tool_call_record, failure: nil)
      invocation = find_or_initialize(tool_call_record.tool_call_id, tool_call_record.name)
      definition = @run.project.tool_definitions.find_by(key: tool_call_record.name)
      result_record = tool_call_record.result
      approval_status = tool_call_record.approval.to_s.presence
      remote_approval_pending = remote?(tool_call_record) && approval_status.nil? && result_record.nil?

      invocation.assign_attributes(
        attempt: invocation.attempt || @attempt,
        tool_definition: definition,
        arguments_json: Ai::ToolPayloadSanitizer.call(tool_call_record.arguments || {}),
        started_at: invocation.started_at || tool_call_record.created_at || Time.current,
        remote: remote?(tool_call_record)
      )

      if failure && result_record.nil?
        invocation.assign_attributes(
          status: :failed,
          finished_at: Time.current,
          duration_ms: duration_for(invocation),
          error_class: failure.class.name,
          error_code: Ai::ErrorClassifier.code(failure),
          error_message: safe_error_message(failure)
        )
      elsif approval_status == "denied"
        invocation.assign_attributes(
          status: :denied,
          finished_at: invocation.finished_at || Time.current
        )
        invocation.result_json = result_payload(result_record) if result_record
      elsif result_record
        payload = result_payload(result_record)
        parsed = payload.fetch("parsed")
        content = payload.fetch("content")
        failed_result = parsed.is_a?(Hash) && parsed.key?("error")
        invocation.assign_attributes(
          status: failed_result ? :failed : :succeeded,
          result_json: payload,
          finished_at: invocation.finished_at || Time.current,
          duration_ms: invocation.duration_ms || duration_for(invocation)
        )
        invocation.assign_attributes(
          error_class: "RubyLLM::ToolError",
          error_message: parsed["error"].to_s.truncate(2_000)
        ) if failed_result
      elsif approval_status == "approved"
        invocation.status = :approved
      elsif remote_approval_pending || definition&.approval_required?
        invocation.status = :waiting_for_approval
      else
        invocation.status = :requested
      end

      invocation.save!
      sync_approval!(invocation, definition, approval_status, tool_call_record.created_at,
        remote_approval_pending:, failure:)
      notify("ai.tool.requested", invocation)
      if invocation.succeeded? || invocation.failed? || invocation.denied?
        notify("ai.tool.completed", invocation)
      end
      invocation
    end

    def sync_approval!(invocation, definition, approval_status, requested_at, remote_approval_pending:, failure:)
      return if failure
      return unless definition&.approval_required? || approval_status.present? || remote_approval_pending

      approval = invocation.approval || invocation.build_approval(
        actor: "local_user",
        requested_at: requested_at || Time.current
      )
      approval.status = approval_status.presence || "pending"
      approval.requested_at ||= requested_at || Time.current
      approval.decided_at = Time.current if approval.decided? && approval.decided_at.blank?
      approval.save!
      notify("ai.approval.requested", invocation) if approval.pending?
    end

    def find_or_initialize(tool_call_id, tool_key)
      @run.tool_invocations.find_or_initialize_by(tool_call_id: tool_call_id) do |invocation|
        invocation.tool_key = tool_key
      end.tap do |invocation|
        invocation.tool_key = tool_key
      end
    end

    def duration_for(invocation)
      return unless invocation.started_at

      ((Time.current - invocation.started_at) * 1_000).round
    end

    def result_payload(result_record)
      content = result_record.content.to_s
      {
        "content" => Ai::ToolPayloadSanitizer.call(content),
        "parsed" => Ai::ToolPayloadSanitizer.parse_and_call(content)
      }
    end

    def safe_error_message(error)
      Ai::ErrorText.safe(error.message)
    end

    def notify(event, invocation, tool_call_id: nil)
      Ai::LifecycleEventRecorder.emit(
        event,
        run_id: @run.id,
        project_id: @run.project_id,
        attempt_id: invocation.attempt_id,
        tool_invocation_id: invocation.id,
        approval_id: invocation.approval&.id,
        tool_call_id: tool_call_id || invocation.tool_call_id,
        tool_key: invocation.tool_key,
        status: invocation.status,
        event_key: event_key_for(event, invocation)
      )
    end

    def with_agent_execution_lease
      return yield unless @agent_execution_token

      @run.with_lock do
        @run.reload
        @run.assert_agent_execution_lease!(
          token: @agent_execution_token,
          generation: @agent_execution_generation
        )
        yield
      end
    end

    def event_key_for(event, invocation)
      case event
      when "ai.tool.requested"
        "tool:#{invocation.id}:requested"
      when "ai.tool.completed"
        "tool:#{invocation.id}:completed:#{invocation.status}"
      when "ai.approval.requested"
        "approval:#{invocation.approval&.id || invocation.id}:requested"
      else
        "tool:#{invocation.id}:#{event.delete_prefix('ai.tool.')}"
      end
    end
  end
end

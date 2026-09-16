module Ai
  class ToolInvocationRecorder
    def initialize(run:, chat:, attempt: nil)
      @run = run
      @chat = chat
      @attempt = attempt
    end

    def attach
      return self unless @chat.respond_to?(:before_tool_call)

      @chat.before_tool_call { |tool_call| mark_running(tool_call) }
      @chat.after_message { |_message| sync! }
      self
    end

    def sync!(failure: nil)
      persisted_tool_calls.each do |tool_call_record|
        sync_record(tool_call_record, failure:)
      end
      @run.tool_invocations.reload
    end

    private

    def persisted_tool_calls
      RubyLLM::ActiveRecord::ToolCall.where(
        message_type: Message.polymorphic_name,
        message_id: @chat.messages.select(:id)
      ).includes(:result).order(:id)
    end

    def mark_running(tool_call)
      invocation = find_or_initialize(tool_call.id, tool_call.name)
      invocation.assign_attributes(
        attempt: @attempt,
        status: :running,
        arguments_json: Ai::ToolPayloadSanitizer.call(tool_call.arguments),
        started_at: invocation.started_at || Time.current
      )
      invocation.save!
      notify("ai.tool.requested", invocation, tool_call_id: tool_call.id)
    end

    def sync_record(tool_call_record, failure: nil)
      invocation = find_or_initialize(tool_call_record.tool_call_id, tool_call_record.name)
      definition = @run.project.tool_definitions.find_by(key: tool_call_record.name)
      result_record = tool_call_record.result
      approval_status = tool_call_record.approval.to_s.presence

      invocation.assign_attributes(
        attempt: invocation.attempt || @attempt,
        tool_definition: definition,
        arguments_json: Ai::ToolPayloadSanitizer.call(tool_call_record.arguments || {}),
        started_at: invocation.started_at || tool_call_record.created_at || Time.current
      )

      if failure && result_record.nil?
        invocation.assign_attributes(
          status: :failed,
          finished_at: Time.current,
          duration_ms: duration_for(invocation),
          error_class: failure.class.name,
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
      elsif definition&.approval_required?
        invocation.status = :waiting_for_approval
      else
        invocation.status = :requested
      end

      invocation.save!
      sync_approval!(invocation, definition, approval_status, tool_call_record.created_at)
      if invocation.succeeded? || invocation.failed? || invocation.denied?
        notify("ai.tool.completed", invocation)
      elsif invocation.requested? || invocation.waiting_for_approval? || invocation.approved? || invocation.running?
        notify("ai.tool.requested", invocation)
      end
      invocation
    end

    def sync_approval!(invocation, definition, approval_status, requested_at)
      return unless definition&.approval_required? || approval_status.present?

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
      error.message.to_s.gsub(/\b(sk|rk|xai|AIza|gsk|pplx|r8)_[A-Za-z0-9_-]{12,}\b/i, "[REDACTED]").truncate(2_000)
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

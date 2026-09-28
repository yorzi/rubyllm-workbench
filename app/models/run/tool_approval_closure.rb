# Closes tool calls and approvals when a Run is cancelled or fails, so the
# Chat transcript stays valid for RubyLLM and no approval is left actionable.
# Unknown outcomes of approved remote (provider-hosted) calls are recorded
# rather than guessed.
module Run::ToolApprovalClosure
  extend ActiveSupport::Concern

  private

  def cancel_active_tool_invocations!(now)
    tool_invocations
      .where(status: %w[requested waiting_for_approval approved running])
      .includes(:approval)
      .order(:id)
      .each do |invocation|
        approval = invocation.approval
        if invocation.status.in?(%w[requested waiting_for_approval approved])
          chat.deny(invocation.tool_call_id)
        end

        if approval&.pending?
          approval.update!(
            status: :expired,
            decided_at: now,
            decision_note: "Run cancelled before approval was decided."
          )
          Ai::LifecycleEventRecorder.emit(
            "ai.approval.expired",
            run_id: id,
            project_id: project_id,
            attempt_id: invocation.attempt_id,
            tool_invocation_id: invocation.id,
            approval_id: approval.id,
            status: approval.status,
            actor: "system",
            event_key: "approval:#{approval.id}:expired"
          )
        end

        cancellation_message = if invocation.status == "running"
          "Run cancelled while the tool action was in progress; its outcome may be unknown."
        else
          "Run cancelled before the tool action started."
        end
        invocation.update!(
          status: :cancelled,
          finished_at: now,
          duration_ms: invocation.started_at ? ((now - invocation.started_at) * 1_000).round : nil,
          error_class: "RunCancellation",
          error_code: invocation.remote? && invocation.status == "running" ? "remote_tool_outcome_unknown" : "run_cancelled",
          error_message: cancellation_message
        )
        Ai::LifecycleEventRecorder.emit(
          "ai.tool.cancelled",
          run_id: id,
          project_id: project_id,
          attempt_id: invocation.attempt_id,
          tool_invocation_id: invocation.id,
          tool_call_id: invocation.tool_call_id,
          tool_key: invocation.tool_key,
          status: invocation.status,
          error_code: invocation.error_code,
          event_key: "tool:#{invocation.id}:cancelled"
        )
      end
  end

  def pending_tool_approval_invocations
    tool_invocations
      .where(status: %w[requested waiting_for_approval approved])
      .includes(:approval, :tool_definition)
      .select do |invocation|
        invocation.remote? || invocation.approval.present? || invocation.tool_definition&.approval_required?
      end
  end

  def finalize_failed_tool_approvals!(error)
    invocations = tool_invocations.includes(:approval, :tool_definition).order(:id).to_a
    return if invocations.empty?

    tool_calls = RubyLLM::ActiveRecord::ToolCall.where(
      message_type: Message.polymorphic_name,
      message_id: chat.messages.select(:id),
      tool_call_id: invocations.map(&:tool_call_id)
    ).includes(:result).index_by(&:tool_call_id)

    now = Time.current
    invocations.each do |invocation|
      approval = invocation.approval
      tool_call = tool_calls[invocation.tool_call_id]
      next unless failed_approval_call?(invocation, approval, tool_call)

      if approved_remote_tool_outcome_unknown?(invocation, approval, tool_call)
        mark_remote_tool_outcome_unknown!(invocation, error, now)
        next
      end

      finalize_failed_tool_call!(invocation, tool_call)
      expire_failed_approval!(invocation, approval, now) if approval&.pending?
      unless invocation.status.in?(%w[succeeded failed denied cancelled])
        mark_failed_tool_invocation!(invocation, error, now)
      end
    end
  end

  def failed_approval_call?(invocation, approval, tool_call)
    return true if approval&.pending?
    return false unless tool_call && tool_call.result.nil?
    return true if invocation.remote?

    approval_required = approval.present? || invocation.tool_definition&.approval_required?
    approval_required && (
      approval&.approved? || approval&.denied? ||
        invocation.status.in?(%w[requested waiting_for_approval approved])
    )
  end

  def approved_remote_tool_outcome_unknown?(invocation, approval, tool_call)
    invocation.remote? && tool_call && tool_call.result.nil? && (
      approval&.approved? || tool_call.approval == "approved" || invocation.approved?
    )
  end

  def mark_remote_tool_outcome_unknown!(invocation, error, now)
    message = "Remote tool call was approved, but its provider result was not persisted before the Run failed. The external outcome is unknown; this chat cannot safely resume it."
    invocation.update!(
      status: :failed,
      finished_at: now,
      duration_ms: invocation.started_at ? ((now - invocation.started_at) * 1_000).round : nil,
      error_class: error.class.name,
      error_code: "remote_tool_outcome_unknown",
      error_message: message
    )
    Ai::LifecycleEventRecorder.emit(
      "ai.tool.completed",
      run_id: id,
      project_id: project_id,
      attempt_id: invocation.attempt_id,
      tool_invocation_id: invocation.id,
      tool_call_id: invocation.tool_call_id,
      tool_key: invocation.tool_key,
      status: invocation.status,
      error_class: invocation.error_class,
      error_code: invocation.error_code,
      event_key: "tool:#{invocation.id}:completed:remote_outcome_unknown"
    )
  end

  def finalize_failed_tool_call!(invocation, tool_call)
    return unless tool_call

    chat.deny(invocation.tool_call_id) unless tool_call.approval == "denied"
    return if tool_call.result

    if invocation.remote?
      llm_chat = chat.to_llm
      response = llm_chat.provider.tool_approval_response(
        tool_call.to_llm,
        approved: false,
        model: llm_chat.model
      )
      chat.add_message(response)
    else
      chat.add_message(
        role: :tool,
        content: { error: "The Run failed before this tool call was executed." }.to_json,
        tool_call_id: invocation.tool_call_id
      )
    end
  rescue StandardError => error
    Rails.logger.warn("Run ##{id} failed approval cleanup for tool call #{invocation.tool_call_id}: #{error.class}")
  end

  def expire_failed_approval!(invocation, approval, now)
    approval.update!(
      status: :expired,
      decided_at: now,
      decision_note: "Run failed before approval was decided."
    )
    Ai::LifecycleEventRecorder.emit(
      "ai.approval.expired",
      run_id: id,
      project_id: project_id,
      attempt_id: invocation.attempt_id,
      tool_invocation_id: invocation.id,
      approval_id: approval.id,
      status: approval.status,
      actor: "system",
      event_key: "approval:#{approval.id}:expired"
    )
  end

  def mark_failed_tool_invocation!(invocation, error, now)
    invocation.update!(
      status: :failed,
      finished_at: now,
      duration_ms: invocation.started_at ? ((now - invocation.started_at) * 1_000).round : nil,
      error_class: error.class.name,
      error_code: Ai::ErrorClassifier.code(error),
      error_message: Ai::ErrorText.safe(error.message).to_s.truncate(2_000)
    )
    Ai::LifecycleEventRecorder.emit(
      "ai.tool.completed",
      run_id: id,
      project_id: project_id,
      attempt_id: invocation.attempt_id,
      tool_invocation_id: invocation.id,
      tool_call_id: invocation.tool_call_id,
      tool_key: invocation.tool_key,
      status: invocation.status,
      error_class: invocation.error_class,
      error_code: invocation.error_code,
      event_key: "tool:#{invocation.id}:completed:failed"
    )
  end

  def resolve_pending_tool_approvals!(pending_invocations)
    pending_invocations.each do |invocation|
      chat.deny(invocation.tool_call_id)
      next if invocation.remote?

      chat.add_message(
        role: :tool,
        content: { error: "The Run was cancelled before this tool call started." }.to_json,
        tool_call_id: invocation.tool_call_id
      )
    end

    return unless pending_invocations.any?(&:remote?)

    Ai::ChatTooling.new(chat:, project:, run: self).configure
    chat.run_tools
  end
end

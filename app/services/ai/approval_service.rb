module Ai
  class ApprovalService
    VALID_DECISIONS = %w[approved denied].freeze

    def self.decide!(invocation:, decision:, note: nil)
      new(invocation:, decision:, note:).decide!
    end

    def initialize(invocation:, decision:, note: nil)
      @invocation = invocation
      @decision = decision.to_s
      @note = note.to_s.strip.presence
    end

    def decide!
      raise ArgumentError, "Unknown approval decision." unless VALID_DECISIONS.include?(@decision)
      raise ArgumentError, "This tool call is no longer awaiting approval." unless @invocation.approval_pending?

      run = @invocation.run
      chat = run.chat

      if @decision == "approved"
        chat.approve(@invocation.tool_call_id)
      else
        chat.deny(@invocation.tool_call_id)
      end

      now = Time.current
      @invocation.approval.update!(
        status: @decision,
        decided_at: now,
        decision_note: @note
      )
      @invocation.update!(status: @decision)
      ActiveSupport::Notifications.instrument(
        "ai.approval.decided",
        run_id: run.id,
        tool_invocation_id: @invocation.id,
        tool_call_id: @invocation.tool_call_id,
        decision: @decision
      )
      ChatResponseJob.perform_later(run.id)
      @invocation
    end
  end
end

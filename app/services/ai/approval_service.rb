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

      run = @invocation.run
      run.with_lock do
        run.reload
        raise ArgumentError, "This Run can no longer be resumed." if run.terminal? || !run.waiting_for_approval?

        @invocation.with_lock do
          @invocation.reload
          raise ArgumentError, "This tool call is no longer awaiting approval." unless @invocation.approval_pending?

          chat = run.chat
          tool_call = Ai::RubyLlmInternals.record_tool_call_decision(chat, @invocation.tool_call_id, @decision)
          unless tool_call.reload.approval == @decision && tool_call.result_id.nil?
            raise ArgumentError, "This tool call is no longer awaiting approval."
          end

          approval = @invocation.approval
          approval.update!(status: @decision, decided_at: Time.current, decision_note: @note)
          @invocation.update!(status: @decision)
          if run.operation == "agent"
            AgentRunDelivery.record!(
              run:,
              intent: "approval",
              approval_invocation_id: @invocation.id,
              expected_generation: run.agent_execution_generation
            )
          end
          Ai::LifecycleEventRecorder.emit(
            "ai.approval.decided",
            run_id: run.id,
            project_id: run.project_id,
            approval_id: approval.id,
            tool_invocation_id: @invocation.id,
            tool_call_id: @invocation.tool_call_id,
            decision: @decision,
            actor: approval.actor,
            status: approval.status,
            event_key: "approval:#{approval.id}:decided:#{@decision}"
          )
        end
      end

      ChatResponseJob.perform_later(run.id) unless run.operation == "agent"
      @invocation
    end
  end
end

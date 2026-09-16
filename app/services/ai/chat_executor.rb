module Ai
  class ChatExecutor
    def initialize(run_id, run: nil, chat: nil)
      @run = run || Run.includes(:chat, :attempts).find(run_id)
      @chat = chat || @run.chat
    end

    def call
      return @run unless claim_run

      recorder = Ai::AttemptRecorder.new(@run, chat: @chat)
      attempt = recorder.start!
      Ai::ChatTooling.new(chat: @chat, project: @run.project, run: @run).configure
      tool_recorder = Ai::ToolInvocationRecorder.new(run: @run, chat: @chat, attempt:).attach
      usage_ids_before = @chat.ruby_llm_usages.pluck(:id)
      response = nil

      completion = @resuming_approval ? :complete : :ask
      response = @chat.public_send(completion, *([ prompt ] if completion == :ask)) do |chunk|
        content = chunk.content.to_s
        next if content.blank?

        recorder.observe!(content)
        latest_assistant_message&.broadcast_append_chunk(content)
      end
      tool_recorder.sync!

      if @chat.awaiting_approval?
        recorder.waiting_for_approval!(
          usage_ids_before: usage_ids_before,
          result_summary: { "pending_tool_calls" => @run.tool_invocations.waiting_for_approval.pluck(:tool_key) }
        )
      else
        recorder.succeed!(response, usage_ids_before: usage_ids_before)
      end
    rescue StandardError => error
      Ai::ToolErrorFinalizer.new(@chat, error).call
      tool_recorder&.sync!(failure: error)
      recorder&.fail!(error, usage_ids_before: usage_ids_before || [])
    end

    private

    def claim_run
      @run.with_lock do
        @run.reload
        return false if @run.terminal? || @run.running?

        @resuming_approval = @run.waiting_for_approval?
        @run.start!
      end
      true
    end

    def prompt
      @run.input_snapshot.fetch("prompt") { @run.input_snapshot.fetch(:prompt) }
    end

    def latest_assistant_message
      @chat.messages.reload.reverse.find { |message| message.role.to_s == "assistant" }
    end
  end
end

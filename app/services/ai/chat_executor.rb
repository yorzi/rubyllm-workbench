module Ai
  class ChatExecutor
    def initialize(run_id, run: nil, chat: nil)
      @run = run || Run.includes(:chat, :attempts).find(run_id)
      @chat = chat || @run.chat
    end

    def call
      return @run if @run.terminal?

      recorder = Ai::AttemptRecorder.new(@run, chat: @chat)
      recorder.start!
      usage_ids_before = @chat.ruby_llm_usages.pluck(:id)
      response = nil

      response = @chat.ask(prompt) do |chunk|
        content = chunk.content.to_s
        next if content.blank?

        recorder.observe!(content)
        latest_assistant_message&.broadcast_append_chunk(content)
      end

      if @chat.awaiting_approval?
        recorder.waiting_for_approval!(usage_ids_before: usage_ids_before)
      else
        recorder.succeed!(response, usage_ids_before: usage_ids_before)
      end
    rescue StandardError => error
      recorder&.fail!(error, usage_ids_before: usage_ids_before || [])
    end

    private

    def prompt
      @run.input_snapshot.fetch("prompt") { @run.input_snapshot.fetch(:prompt) }
    end

    def latest_assistant_message
      @chat.messages.reload.reverse.find { |message| message.role.to_s == "assistant" }
    end
  end
end

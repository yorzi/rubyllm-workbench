module Ai
  class ChatExecutor
    def initialize(run_id, run: nil, chat: nil)
      @run = run || Run.includes(:chat, :attempts).find(run_id)
      @chat = chat || @run.chat
    end

    def call
      return @run unless claim_run

      recorder = Ai::AttemptRecorder.new(@run, chat: @chat, continuation: @resuming_approval)
      attempt = recorder.start!
      Ai::ChatTooling.new(chat: @chat, project: @run.project, run: @run).configure
      assert_frozen_conversation_context! unless @resuming_approval
      tool_recorder = Ai::ToolInvocationRecorder.new(run: @run, chat: @chat, attempt:).attach
      usage_ids_before = @chat.ruby_llm_usages.pluck(:id)
      response = nil

      completion = @resuming_approval ? :complete : :ask
      response = Ai::ExecutionContext.with(run_id: @run.id, attempt_id: attempt.id) do
        @chat.public_send(completion, *([ prompt ] if completion == :ask)) do |chunk|
          content = chunk.content.to_s
          next if content.blank?

          recorder.observe!(content)
          latest_assistant_message&.broadcast_append_chunk(content)
        end
      end
      tool_recorder.sync!
      source_message_id = latest_assistant_message&.id
      citation_artifact = Ai::CitationSetRecorder.new(run: @run, attempt:, response:, source_message_id:).call
      result_summary = provider_result_summary(response, citation_artifact, source_message_id)

      if @chat.awaiting_approval?
        pending_result_summary = {
          "pending_tool_calls" => @run.tool_invocations.waiting_for_approval.pluck(:tool_key)
        }.merge(result_summary)
        recorder.waiting_for_approval!(
          usage_ids_before: usage_ids_before,
          result_summary: pending_result_summary
        )
      else
        recorder.succeed!(
          response,
          usage_ids_before: usage_ids_before,
          result_summary:
        )
      end
    rescue StandardError => error
      @run.with_lock do
        @run.reload
        return if @run.terminal?

        Ai::ToolErrorFinalizer.new(@chat, error, run: @run).call
        tool_recorder&.sync!(failure: error)
        result_summary = error.is_a?(Ai::ChatContextSnapshot::ContextChanged) ? { "provider_request_made" => false } : {}
        recorder&.fail!(error, usage_ids_before: usage_ids_before || [], result_summary:)
      end
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

    def assert_frozen_conversation_context!
      expected = @run.input_snapshot["conversation_context"]
      return unless expected

      # RubyLLM memoizes its hydrated Chat object. Tool configuration can
      # materialize that object before this check, so refresh it from the
      # persisted transcript before comparing the frozen request context.
      @chat.reload
      return if Ai::ChatContextSnapshot.call(@chat) == expected

      raise Ai::ChatContextSnapshot::ContextChanged,
        "Chat changed after this Run was queued. No provider request was made; queue a new Run."
    end

    def latest_assistant_message
      @chat.messages.reload.reverse.find { |message| message.role.to_s == "assistant" }
    end

    def provider_result_summary(response, citation_artifact, source_message_id)
      summary = {}
      summary["source_message_id"] = source_message_id if source_message_id
      summary["citation_artifact_id"] = citation_artifact.id if citation_artifact
      summary["citation_count"] = citation_artifact.metadata_json["citation_count"] if citation_artifact
      provider_tool_calls = provider_tool_call_records(response)
      if provider_tool_calls.any?
        summary["provider_tool_calls"] = provider_tool_calls
        summary["provider_tool_step_count"] = provider_tool_calls.size
      end
      summary
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
  end
end

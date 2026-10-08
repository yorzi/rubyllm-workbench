module Ai
  class EvaluationBatchResults
    # RubyLLM 2.1 validates result indices before delivery. Require the public
    # submitted-chat manifest so RubyLLM knows the frozen count even when the
    # provider omits it. Fail before collecting if the local manifest is lost;
    # never patch private Batch methods or guess a count from returned rows.
    def self.call(batch, expected_count:)
      chats = batch.chats
      unless chats.is_a?(Array) && chats.size == expected_count && chats.none?(&:nil?)
        raise RubyLLM::Error, "Provider batch chat manifest does not match the frozen evaluation case count."
      end

      batch.messages
    end
  end
end

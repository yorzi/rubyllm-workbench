module Ai
  # Workbench's dependencies on RubyLLM APIs that are not public live here,
  # or are listed here. Re-check each one on every RubyLLM upgrade;
  # test/services/ai/ruby_llm_internals_test.rb fails if any of them moves.
  #
  # RubyLLM's Active Record chat delegates usage writes to #persist_usage_entry.
  # Its private #record_tool_call_decision records a decision without loading
  # the provider, and respects the gem's persisted tool claims.
  module RubyLlmInternals
    module_function

    def wrap_usage_recorder(chat)
      original = chat.method(:persist_usage_entry)
      chat.define_singleton_method(:persist_usage_entry) do |entry|
        yield(entry, original)
      end
    end

    def record_tool_call_decision(chat, id, decision)
      chat.send(:record_tool_call_decision, id, decision)
    end
  end
end

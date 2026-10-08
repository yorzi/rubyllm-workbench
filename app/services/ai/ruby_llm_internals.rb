module Ai
  # Workbench's dependencies on RubyLLM APIs that are not public live here,
  # or are listed here. Re-check each one on every RubyLLM upgrade;
  # test/services/ai/ruby_llm_internals_test.rb fails if any of them moves.
  #
  # 1. RubyLLM::Chat#usage_recorder= (:nodoc:) and the @usage_recorder that
  #    RubyLLM's ActiveRecord layer installs. Agent Runs wrap it so every
  #    ruby_llm_usages write is fenced by the Run's execution lease.
  module RubyLlmInternals
    module_function

    # Replaces the chat's usage recorder with one that yields each usage entry
    # and the original recorder to the block. Returns false when RubyLLM has
    # installed no recorder (a plain, non-persisted chat).
    def wrap_usage_recorder(llm_chat)
      original = llm_chat.instance_variable_get(:@usage_recorder)
      return false unless original

      llm_chat.usage_recorder = ->(entry) { yield(entry, original) }
      true
    end
  end
end

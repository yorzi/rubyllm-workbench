require "test_helper"

class Ai::RubyLlmInternalsTest < ActiveSupport::TestCase
  test "persisted chat usage passes through the Agent fencing hook" do
    chat = create_chat(create_project(name: "Internals project"))
    seen = []
    Ai::RubyLlmInternals.wrap_usage_recorder(chat) do |entry, original|
      seen << [ entry, original.respond_to?(:call) ]
    end

    RubyLLM::ActiveRecord::ChatRun.new(chat).record_usage(:entry)

    assert_equal [ [ :entry, true ] ], seen
    assert_empty chat.ruby_llm_usages
  end
end

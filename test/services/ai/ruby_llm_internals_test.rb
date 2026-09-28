require "test_helper"

# Contract tests for the RubyLLM internals listed in Ai::RubyLlmInternals.
# A failure here after a RubyLLM upgrade means a private seam moved: re-read
# the upstream change before adjusting the Workbench code that relies on it.
class Ai::RubyLlmInternalsTest < ActiveSupport::TestCase
  test "persisted chats expose the usage recorder seam that Agent Runs fence" do
    chat = create_chat(create_project(name: "Internals project"))
    llm_chat = with_configured_provider(chat) { chat.to_llm }

    assert llm_chat.instance_variable_get(:@usage_recorder).respond_to?(:call),
      "RubyLLM's ActiveRecord chat no longer installs @usage_recorder"
    assert_includes RubyLLM::Chat.private_instance_methods + RubyLLM::Chat.public_instance_methods, :usage_recorder=
  end

  test "wrap_usage_recorder yields each entry with the original recorder" do
    chat = create_chat(create_project(name: "Internals wrap project"))
    llm_chat = with_configured_provider(chat) { chat.to_llm }
    seen = []

    assert Ai::RubyLlmInternals.wrap_usage_recorder(llm_chat) { |entry, original| seen << [ entry, original.respond_to?(:call) ] }
    llm_chat.instance_variable_get(:@usage_recorder).call(:entry)

    assert_equal [ [ :entry, true ] ], seen
  end

  test "wrap_usage_recorder is a no-op for chats without a recorder" do
    llm_chat = RubyLLM::Chat.allocate

    assert_not Ai::RubyLlmInternals.wrap_usage_recorder(llm_chat) { flunk "must not wrap" }
  end

  test "Batch still sizes results through the private hook EvaluationBatchResults overrides" do
    assert_includes RubyLLM::Batch.private_instance_methods, :result_slot_count
    file, line = RubyLLM::Batch.instance_method(:collect_results).source_location
    source = File.readlines(file)[(line - 1), 12].join

    assert_includes source, "result_slot_count(results)", "RubyLLM::Batch#collect_results no longer calls result_slot_count"
  end
end

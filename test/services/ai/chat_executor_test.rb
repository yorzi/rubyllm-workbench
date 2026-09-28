require "test_helper"

class Ai::ChatExecutorTest < ActiveSupport::TestCase
  Chunk = Data.define(:content)
  Response = Data.define(:tokens, :cost, :finish_reason, :id)

  class FakeChat
    def initialize(chat, response_or_error)
      @chat = chat
      @response_or_error = response_or_error
    end

    def provider
      @chat.provider
    end

    def model_id
      @chat.model_id
    end

    def messages
      @chat.messages
    end

    def with_tools(*)
      self
    end

    def ruby_llm_usages
      @chat.ruby_llm_usages
    end

    def awaiting_approval?
      false
    end

    def ask(prompt)
      @chat.messages.create!(role: "user", content: prompt)
      assistant = @chat.messages.create!(role: "assistant", content: "")
      chunks = @response_or_error.is_a?(Exception) ? [ "Hello" ] : [ "Hello", " world" ]

      chunks.each do |content|
        yield Chunk.new(content)
        assistant.update!(content: assistant.content.to_s + content)
      end

      raise @response_or_error if @response_or_error.is_a?(Exception)

      @response_or_error
    end
  end

  setup do
    @project = create_project(name: "Executor project")
    @chat = create_chat(@project)
    @run = @chat.runs.create!(
      project: @project,
      operation: "chat",
      status: :queued,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "hello" },
      app_version: "test",
      ruby_llm_version: Gem.loaded_specs.fetch("ruby_llm").version.to_s
    )
    @run.attempts.create!(sequence: 1, provider: @chat.provider, model_id: @chat.model_id, status: :queued)
    @run.chat = @chat
  end

  test "persists a streamed response and completes its Run" do
    model = RubyLLM.models.find(@chat.model_id, provider: @chat.provider)
    response = Response.new(
      RubyLLM::Tokens.new(input: 12, output: 5),
      model.cost_for(RubyLLM::Tokens.new(input: 12, output: 5)),
      :stop,
      "response-1"
    )

    fake_chat = FakeChat.new(@chat, response)
    result = Ai::ChatExecutor.new(@run.id, run: @run, chat: fake_chat).call
    assert_equal @run.id, result.id

    @run.reload
    attempt = @run.attempts.first
    messages = @chat.messages.reload

    assert @run.succeeded?
    assert attempt.succeeded?
    assert_equal 12, attempt.input_tokens
    assert_equal 5, attempt.output_tokens
    assert_equal "Hello world", messages.last.content
    assert_equal "Hello world", @run.result_summary["partial_output"]
    assert_equal "stop", attempt.reload.finish_reason
    assert_operator @run.time_to_first_output_ms, :>=, 0
    assert_operator attempt.duration_ms, :>=, 0
  end

  test "records usage-only provider tool counters in the Run summary" do
    model = RubyLLM.models.find(@chat.model_id, provider: @chat.provider)
    tokens = RubyLLM::Tokens.new(input: 12, output: 5, server_tool_use: { "web_search_requests" => 2 })
    response = Response.new(tokens, model.cost_for(tokens), :stop, "response-search")

    Ai::ChatExecutor.new(@run.id, run: @run, chat: FakeChat.new(@chat, response)).call

    @run.reload
    assert @run.succeeded?
    assert_equal({ "web_search_requests" => 2 }, @run.result_summary["provider_tool_usage"])
    assert_nil @run.result_summary["provider_tool_calls"]
  end

  test "preserves partial output and failed Attempt when streaming raises" do
    error = RuntimeError.new("provider stream interrupted")

    fake_chat = FakeChat.new(@chat, error)
    Ai::ChatExecutor.new(@run.id, run: @run, chat: fake_chat).call

    @run.reload
    attempt = @run.attempts.first
    messages = @chat.messages.reload

    assert @run.failed?
    assert attempt.failed?
    assert_equal "RuntimeError", attempt.error_class
    assert_includes attempt.error_message, "provider stream interrupted"
    assert_equal "Hello", messages.last.content
    assert_equal "Hello", @run.result_summary["partial_output"]
    assert_includes @run.error_summary, "provider stream interrupted"
  end

  test "resumes a waiting Run with complete without adding the prompt again" do
    @run.update!(status: :waiting_for_approval)
    @run.attempts.first.update!(status: :succeeded, finished_at: Time.current)
    response = Response.new(
      RubyLLM::Tokens.new(input: 3, output: 2),
      RubyLLM::Cost.new(tokens: RubyLLM::Tokens.new(input: 3, output: 2), model: RubyLLM.models.find(@chat.model_id, provider: @chat.provider)),
      :stop,
      "response-resumed"
    )
    fake_chat = ResumingFakeChat.new(@chat, response)

    Ai::ChatExecutor.new(@run.id, run: @run, chat: fake_chat).call

    @run.reload
    messages = @chat.messages.reload
    assert @run.succeeded?
    assert_equal 1, messages.count
    assert_equal "Resumed answer", messages.first.content
    assert_equal 2, @run.attempts.count
    assert @run.attempts.first.succeeded?
    assert @run.attempts.second.succeeded?
  end

  test "does not start a second executor for an already running Run" do
    @run.update!(status: :running, started_at: Time.current)
    fake_chat = FakeChat.new(@chat, RuntimeError.new("must not call the provider"))

    result = Ai::ChatExecutor.new(@run.id, run: @run, chat: fake_chat).call

    assert_equal @run.id, result.id
    assert_empty @chat.messages.reload
    assert @run.reload.running?
  end

  test "fails before asking the provider when the persisted chat changed after enqueue" do
    @chat.messages.create!(role: "user", content: "Context before enqueue")
    frozen_context = Ai::ChatContextSnapshot.call(@chat)
    watermark = @chat.messages.maximum(:id)
    @run.update!(input_snapshot_json: {
      "prompt" => "hello",
      "conversation_context" => frozen_context,
      "conversation_message_high_watermark" => watermark
    })

    # Reproduce the stale RubyLLM message cache that can be materialized by
    # tool configuration before the worker's drift check.
    provider_called = false
    with_provider_configuration(@chat.provider) do
      @chat.to_llm
      Message.create!(chat: @chat, role: "assistant", content: "Changed after enqueue")
      with_singleton_method_stub(@chat, :ask, ->(*) { provider_called = true; raise "provider must not be called" }) do
        Ai::ChatExecutor.new(@run.id, run: @run, chat: @chat).call
      end
    end

    @run.reload
    assert @run.failed?
    assert_equal false, @run.result_summary.fetch("provider_request_made")
    assert_equal false, provider_called
    assert_equal "Context before enqueue", @chat.messages.first.content
    assert_equal "Changed after enqueue", @chat.messages.last.content
  end

  class ResumingFakeChat < FakeChat
    def complete
      @chat.messages.create!(role: "assistant", content: "Resumed answer")
      @response_or_error
    end

    def ask(*)
      raise "ask should not be used while resuming an approval"
    end
  end

  private

  def with_singleton_method_stub(object, name, implementation)
    original = object.method(name)
    object.define_singleton_method(name, &implementation)
    yield
  ensure
    object.define_singleton_method(name, original)
  end
end

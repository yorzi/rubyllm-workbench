require "test_helper"

class SemanticGroundedAnswerFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  EMBEDDING = "openai/text-embedding-3-small"
  RERANK = "voyageai/rerank-2.5-lite"

  setup do
    @project = create_project(name: "Owned semantic source answers")
    @collection = @project.knowledge_collections.create!(name: "Notes")
    2.times do |index|
      item = @collection.knowledge_items.create!(title: "Note #{index}", content_text: "SQLite retrieval evidence #{index}.")
      Ai::Knowledge::Ingestor.call(item)
    end
    @model = RubyLLM.models.chat_models.all.find { |model| model.provider == "openrouter" && model.supports?(:structured_output) }
    @answer = { status: "insufficient_evidence", reason: "These fragments omit implementation details.", claims: [] }
  end

  test "a batch charge belongs once to the collection, never to each chunk" do
    request = stub_embeddings(batch: true, usage: { prompt_tokens: 12, total_tokens: 12, cost: 0.003 })
    with_provider_configuration("openrouter") { Ai::Knowledge::Embedder.call(collection: @collection, model_id: EMBEDDING) }
    usage = @collection.ruby_llm_usages.sole
    assert_equal "embedding", usage.operation
    assert_equal 12, usage.input_tokens
    assert_equal BigDecimal("0.003"), usage.total_cost
    assert_nil usage.chat_id
    assert_equal 2, @collection.knowledge_embeddings.count
    assert @collection.knowledge_embeddings.all? { |row| row.input_tokens.nil? && row.reported_cost.nil? }
    assert_requested request, times: 1
    get project_knowledge_collection_path(@project, @collection)
    assert_includes response.body, "Collection retrieval usage"
    assert_includes response.body, "0.003 USD (recorded)"
  end

  test "query embedding, rerank and generation are independently owned and exported" do
    prepare_vectors
    embedding = stub_embeddings(usage: { prompt_tokens: 11, total_tokens: 11, cost: 0.002 })
    rerank = WebMock.stub_request(:post, "https://openrouter.ai/api/v1/rerank").to_return(
      status: 200, headers: { "content-type" => "application/json" }, body: JSON.generate(
        model: RERANK, results: [ { index: 1, relevance_score: 0.9 }, { index: 0, relevance_score: 0.2 } ],
        usage: { total_tokens: 20, cost: 0.004 }
      )
    )
    chat = stub_answer
    with_provider_configuration("openrouter") do
      assert_no_difference "RubyLLM::ActiveRecord::Usage.count" do
        post_answer(mode: "hybrid", rerank: "1", rerank_model_id: RERANK)
      end
      run = @project.runs.sole
      assert run.input_snapshot.dig("grounded_answer", "retrieval_pending")
      assert_empty run.attempts
      GroundedAnswerJob.perform_now(run.id)
      assert run.reload.succeeded?, run.error_summary
      snapshot = run.input_snapshot.fetch("grounded_answer")
      assert_equal "hybrid", snapshot.dig("retrieval", "mode")
      assert_equal true, snapshot.dig("retrieval", "rerank")
      assert_equal false, snapshot["retrieval_pending"]
      assert snapshot["evidence"].all? { |e| e["similarity"] && e["rerank_score"] && e["pre_rank"] }
      assert_equal %w[query_embedding rerank answer], run.attempts.map { |a| a.metadata_json["phase"] }
      assert_equal [ 11, 20, 30 ], run.attempts.map(&:input_tokens)
      assert_equal 3, run.attempts.flat_map(&:ruby_llm_usage_ids_json).uniq.size
      assert_equal "recorded", run.attempts.first.cost_status
      assert_equal BigDecimal("0.002"), run.attempts.first.cost
      assert_empty @collection.ruby_llm_usages
      assert_equal run.attempts.last, run.artifacts.sole.attempt
      get run_path(run)
      assert_response :success
      assert_includes response.body, "hybrid · frozen evidence"
      assert_includes response.body, "Rerank: applied"
      get reproduction_run_path(run)
      export = JSON.parse(response.body)
      assert_equal snapshot["embedding_revision"], export.dig("run", "input_snapshot", "grounded_answer", "embedding_revision")
      assert_equal snapshot["retrieval"], export.dig("run", "input_snapshot", "grounded_answer", "retrieval")
    end
    assert_requested embedding, times: 1
    assert_requested rerank, times: 1
    assert_requested chat, times: 1
  end

  test "interactive semantic search attributes its query to the collection" do
    prepare_vectors
    request = stub_embeddings(usage: {})
    with_provider_configuration("openrouter") do
      Ai::Knowledge::Search.call(collection: @collection, query: "SQLite retrieval", mode: "semantic")
    end
    usage = @collection.ruby_llm_usages.sole
    assert_nil usage.input_tokens
    assert_nil usage.total_cost
    assert_requested request, times: 1
  end

  test "stored vector drift rejects a queued answer before any transport" do
    prepare_vectors
    with_provider_configuration("openrouter") do
      post_answer(mode: "semantic")
      run = @project.runs.sole
      @collection.knowledge_embeddings.first.update!(vector: [ 0.0, 1.0, 0.0, 0.0, 0.0, 0.0 ].pack("f*"))
      GroundedAnswerJob.perform_now(run.id)
      assert run.reload.failed?
      assert_equal "stale_evidence", run.result_summary["failure_kind"]
      assert_empty run.attempts
      assert_empty run.artifacts
    end
    assert_not_requested :post, "https://openrouter.ai/api/v1/embeddings"
    assert_not_requested :post, "https://openrouter.ai/api/v1/chat/completions"
  end

  test "source drift during query embedding fails before answer generation but retains billed usage" do
    prepare_vectors
    request = WebMock.stub_request(:post, "https://openrouter.ai/api/v1/embeddings").to_return do
      @collection.knowledge_items.first.update!(content_text: "Changed source")
      embedding_response(usage: { prompt_tokens: 11, cost: 0.002 })
    end
    with_provider_configuration("openrouter") do
      post_answer(mode: "semantic")
      run = @project.runs.sole
      GroundedAnswerJob.perform_now(run.id)
      assert run.reload.failed?
      assert_equal "stale_evidence", run.result_summary["failure_kind"]
      assert run.attempts.sole.succeeded?
      assert_equal BigDecimal("0.002"), run.total_cost
      assert_empty run.artifacts
      assert_equal true, run.input_snapshot.dig("grounded_answer", "retrieval_pending")
    end
    assert_requested request, times: 1
    assert_not_requested :post, "https://openrouter.ai/api/v1/chat/completions"
  end

  test "cancellation during retrieval keeps late native usage without reviving the Attempt" do
    prepare_vectors
    request = WebMock.stub_request(:post, "https://openrouter.ai/api/v1/embeddings").to_return do
      @project.runs.sole.cancel!
      embedding_response(usage: { prompt_tokens: 11, cost: 0.002 })
    end
    with_provider_configuration("openrouter") do
      post_answer(mode: "semantic", rerank: "1", rerank_model_id: RERANK)
      run = @project.runs.sole
      GroundedAnswerJob.perform_now(run.id)
      assert run.reload.cancelled?
      assert run.attempts.sole.cancelled?
      assert_equal BigDecimal("0.002"), run.attempts.sole.ruby_llm_usages.sole.total_cost
      assert_empty run.artifacts
    end
    assert_requested request, times: 1
    assert_not_requested :post, "https://openrouter.ai/api/v1/rerank"
    assert_not_requested :post, "https://openrouter.ai/api/v1/chat/completions"
  end

  test "cancellation between Attempt creation and the provider block makes no transport call" do
    prepare_vectors
    klass = Ai::Knowledge::ProviderCall
    original = klass.instance_method(:start_attempt)
    with_provider_configuration("openrouter") do
      post_answer(mode: "semantic")
      run = @project.runs.sole
      klass.define_method(:start_attempt) do
        attempt = original.bind_call(self)
        Run.find(run.id).cancel!
        attempt
      end
      GroundedAnswerJob.perform_now(run.id)
      assert run.reload.cancelled?
      assert run.attempts.sole.cancelled?
      assert_empty run.artifacts
    end
    assert_not_requested :post, "https://openrouter.ai/api/v1/embeddings"
    assert_not_requested :post, "https://openrouter.ai/api/v1/chat/completions"
  ensure
    klass&.define_method(:start_attempt, original) if original
  end

  test "the native request boundary prevents cancellation during payload serialization" do
    prepare_vectors
    klass = RubyLLM::Providers::OpenRouter::ChatCompletions
    original = klass.instance_method(:render_embedding_payload)
    with_provider_configuration("openrouter") do
      post_answer(mode: "semantic")
      run = @project.runs.sole
      klass.define_method(:render_embedding_payload) do |*args, **kwargs|
        payload = original.bind_call(self, *args, **kwargs)
        Run.find(run.id).cancel!
        payload
      end
      GroundedAnswerJob.perform_now(run.id)
      assert run.reload.cancelled?
      assert run.attempts.sole.cancelled?
      assert_empty run.artifacts
    end
    assert_not_requested :post, "https://openrouter.ai/api/v1/embeddings"
    assert_not_requested :post, "https://openrouter.ai/api/v1/chat/completions"
  ensure
    klass&.define_method(:render_embedding_payload, original) if original
  end

  test "a changed query dimension is a visible lexical degradation, not semantic evidence absence" do
    prepare_vectors
    request = WebMock.stub_request(:post, "https://openrouter.ai/api/v1/embeddings").to_return(
      status: 200, headers: { "content-type" => "application/json" }, body: JSON.generate(
        model: EMBEDDING, data: [ { index: 0, embedding: [ 1.0, 0.0 ] } ], usage: { prompt_tokens: 11 }
      )
    )
    chat = stub_answer
    with_provider_configuration("openrouter") do
      post_answer(mode: "semantic")
      run = @project.runs.sole
      GroundedAnswerJob.perform_now(run.id)
      assert run.reload.succeeded?, run.error_summary
      assert_equal "lexical", run.input_snapshot.dig("grounded_answer", "retrieval", "mode")
      assert_includes run.input_snapshot.dig("grounded_answer", "retrieval", "degraded_reason"), "dimensions"
      assert run.attempts.first.succeeded?, "the query HTTP transport still succeeded"
    end
    assert_requested request, times: 1
    assert_requested chat, times: 1
  end

  test "a missing semantic index explicitly degrades without an invented retrieval Attempt" do
    chat = stub_answer
    with_provider_configuration("openrouter") do
      post_answer(mode: "semantic")
      run = @project.runs.sole
      GroundedAnswerJob.perform_now(run.id)
      assert run.reload.succeeded?, run.error_summary
      assert_equal "lexical", run.input_snapshot.dig("grounded_answer", "retrieval", "mode")
      assert_includes run.input_snapshot.dig("grounded_answer", "retrieval", "degraded_reason"), "No embedding model"
      assert_equal "answer", run.attempts.sole.metadata_json["phase"]
    end
    assert_requested chat, times: 1
    assert_not_requested :post, "https://openrouter.ai/api/v1/embeddings"
  end

  test "a failed query keeps unknown usage and exposes lexical degradation" do
    prepare_vectors
    request = WebMock.stub_request(:post, "https://openrouter.ai/api/v1/embeddings").to_return(status: 503, body: '{"error":{"message":"Provider unavailable"}}')
    chat = stub_answer
    with_provider_configuration("openrouter") do
      post_answer(mode: "semantic")
      run = @project.runs.sole
      GroundedAnswerJob.perform_now(run.id)
      assert run.reload.succeeded?, run.error_summary
      assert run.attempts.first.failed?
      assert_nil run.attempts.first.cost
      assert_equal "unknown", run.cost_status
      assert_equal "lexical", run.input_snapshot.dig("grounded_answer", "retrieval", "mode")
      assert run.input_snapshot.dig("grounded_answer", "retrieval", "degraded_reason").present?
    end
    assert_requested request, times: 1
    assert_requested chat, times: 1
  end

  private

  def post_answer(**options)
    post project_knowledge_collection_answers_path(@project, @collection), params: {
      knowledge_answer: { question: "SQLite retrieval", model_reference: "openrouter|#{@model.id}" }.merge(options)
    }
    assert_response :see_other
  end

  def prepare_vectors
    with_provider_configuration("openrouter") do
      Ai::Knowledge::Embedder.call(collection: @collection, model_id: EMBEDDING, client: FakeEmbeddingClient.new)
    end
  end

  def stub_embeddings(batch: false, usage:)
    WebMock.stub_request(:post, "https://openrouter.ai/api/v1/embeddings").to_return(embedding_response(batch:, usage:))
  end

  def embedding_response(batch: false, usage:)
    { status: 200, headers: { "content-type" => "application/json" }, body: JSON.generate(
      model: EMBEDDING, data: Array.new(batch ? 2 : 1) { |i| { index: i, embedding: [ 1.0, 1.0, 0.0, 0.0, 0.0, 0.0 ] } }, usage:
    ) }
  end

  def stub_answer
    WebMock.stub_request(:post, "https://openrouter.ai/api/v1/chat/completions").to_return(
      status: 200, headers: { "content-type" => "application/json" }, body: JSON.generate(
        id: "owned-semantic", model: @model.id,
        choices: [ { index: 0, message: { role: "assistant", content: JSON.generate(@answer) }, finish_reason: "stop" } ],
        usage: { prompt_tokens: 30, completion_tokens: 20, cost: 0.001 }
      )
    )
  end
end

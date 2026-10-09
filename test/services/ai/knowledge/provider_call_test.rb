require "test_helper"

class Ai::Knowledge::ProviderCallTest < ActiveSupport::TestCase
  test "native retries keep one physical usage and cost mirror per request" do
    project = create_project(name: "One-shot retry accounting")
    collection = project.knowledge_collections.create!(name: "Retrieval owner")
    chat = create_chat(project)
    run = chat.runs.create!(project:, operation: "grounded_answer", status: :queued, requested_by: "test")
    run.claim_queued_execution!(operation: "grounded_answer")
    before = RubyLLM.config.max_retries
    RubyLLM.config.max_retries = 1
    model_id = "openai/text-embedding-3-small"
    request = WebMock.stub_request(:post, "https://openrouter.ai/api/v1/embeddings").to_return(
      { status: 503, headers: { "content-type" => "application/json" }, body: JSON.generate(error: { message: "Temporary failure" }) },
      { status: 200, headers: { "content-type" => "application/json" }, body: JSON.generate(
        model: model_id, data: [ { index: 0, embedding: [ 1.0, 0.0 ] } ], usage: { prompt_tokens: 3, cost: 0.002 }
      ) }
    )
    with_provider_configuration("openrouter") do
      Ai::Knowledge::Embedder.embed_text("note", model_id:, provider: "openrouter", owner: collection, run:)
    end
    assert_equal %w[failed succeeded], run.attempts.reload.map(&:status)
    assert_equal 2, run.attempts.first.ruby_llm_usages.count
    assert_equal 2, run.attempts.flat_map(&:ruby_llm_usage_ids_json).uniq.size
    assert_equal BigDecimal("0.002"), run.total_cost
    assert_equal "unknown", run.cost_status
    assert_empty collection.ruby_llm_usages
    assert_requested request, times: 2
  ensure
    RubyLLM.config.max_retries = before
  end
end

require "test_helper"

class Ai::Knowledge::RerankerTest < ActiveSupport::TestCase
  MODEL_ID = "voyageai/rerank-2.5-lite"

  setup do
    @project = create_project(name: "Rerank project")
    @collection = @project.knowledge_collections.create!(name: "Engineering notes")
  end

  def add_item(title:, text:)
    item = @collection.knowledge_items.create!(title: title, content_text: text)
    Ai::Knowledge::Ingestor.call(item)
    item
  end

  test "catalog lists rerank-capable models that are configured" do
    with_provider_configuration("openrouter") do
      entries = Ai::Knowledge::RerankCatalog.configured_entries

      assert_operator entries.size, :>, 0
      assert entries.all? { |entry| Array(entry.modalities.to_h[:output]).include?("rerank") }
      assert entries.all?(&:configured)
    end
  end

  test "catalog refuses unknown and unconfigured rerank models" do
    with_provider_configuration("openrouter") do
      unknown = Ai::Knowledge::RerankCatalog.availability("not-a-rerank-model")
      assert_not unknown.available
      assert_includes unknown.reason, "not in the RubyLLM catalog"

      unconfigured = Ai::Knowledge::RerankCatalog.entries.reject(&:configured).first
      return skip "every rerank provider is configured in this environment" if unconfigured.nil?

      availability = Ai::Knowledge::RerankCatalog.availability(unconfigured.id)
      assert_not availability.available
      assert_includes availability.reason, "not configured"
    end
  end

  test "reranker returns ranked indexes for a configured model" do
    with_provider_configuration("openrouter") do
      ranked = Ai::Knowledge::Reranker.call(
        query: "sqlite retrieval",
        documents: [ "sqlite retrieval evidence", "tool approval notes", "sqlite retrieval and retrieval again" ],
        model_id: MODEL_ID,
        client: FakeEmbeddingClient.new
      )

      assert_equal [ 2, 0, 1 ], ranked.map(&:index)
      assert_operator ranked.first.score, :>, ranked.last.score
    end
  end

  test "reranker refuses an unavailable model without calling the provider" do
    with_provider_configuration("openrouter") do
      client = FakeEmbeddingClient.new

      error = assert_raises(Ai::Knowledge::Reranker::ConfigurationError) do
        Ai::Knowledge::Reranker.call(query: "sqlite", documents: [ "a" ], model_id: "not-a-rerank-model", client: client)
      end

      assert_includes error.message, "not in the RubyLLM catalog"
      assert_empty client.calls
    end
  end

  test "reranker redacts provider secrets from failures" do
    with_provider_configuration("openrouter") do
      client = FakeEmbeddingClient.new(error: StandardError.new("401 unauthorized for sk-abcdef1234567890abcd"))

      error = assert_raises(Ai::Knowledge::Reranker::Error) do
        Ai::Knowledge::Reranker.call(query: "sqlite", documents: [ "a" ], model_id: MODEL_ID, client: client)
      end

      assert_includes error.message, "[REDACTED]"
      refute_includes error.message, "sk-abcdef1234567890abcd"
    end
  end

  test "search reorders evidence and keeps the pre-rerank position" do
    with_provider_configuration("openrouter") do
      add_item(title: "Notes A", text: "sqlite only chunk without the other signal word")
      add_item(title: "Notes B", text: "sqlite retrieval evidence with both signal terms")
      add_item(title: "Notes C", text: "sqlite retrieval partial evidence")

      without = Ai::Knowledge::Search.call(collection: @collection, query: "sqlite retrieval", mode: "lexical")
      with = Ai::Knowledge::Search.call(
        collection: @collection,
        query: "sqlite retrieval",
        mode: "lexical",
        rerank: true,
        rerank_model_id: MODEL_ID,
        client: FakeEmbeddingClient.new
      )

      assert_not without.rerank_applied
      assert_nil without.rerank_note
      assert with.rerank_applied
      assert_nil with.rerank_note
      assert_equal MODEL_ID, with.rerank_model_id

      assert_equal without.results.length, with.results.length
      assert_equal "sqlite only chunk without the other signal word", with.results.last.chunk.content_text
      assert_equal with.results.map(&:rerank_score).sort.reverse, with.results.map(&:rerank_score)
      # pre_rank points back at the original retrieval position
      lexical_positions = without.results.map { |result| result.chunk.content_text }.each_with_index.to_h
      assert_equal lexical_positions.values_at(*with.results.map { |result| result.chunk.content_text }), with.results.map(&:pre_rank)
      # retrieval evidence survives reranking
      assert with.results.all? { |result| result.score.present? && result.matched_terms.present? }
    end
  end

  test "search keeps evidence and explains itself when rerank is unavailable" do
    with_provider_configuration("openrouter") do
      add_item(title: "Notes A", text: "sqlite retrieval evidence")

      outcome = Ai::Knowledge::Search.call(
        collection: @collection,
        query: "sqlite retrieval",
        mode: "lexical",
        rerank: true,
        rerank_model_id: nil,
        client: FakeEmbeddingClient.new
      )

      assert_not outcome.rerank_applied
      assert_includes outcome.rerank_note, "No rerank model is selected"
      assert_equal 1, outcome.results.length
    end
  end

  test "search keeps evidence when the rerank provider fails" do
    with_provider_configuration("openrouter") do
      add_item(title: "Notes A", text: "sqlite retrieval evidence")

      outcome = Ai::Knowledge::Search.call(
        collection: @collection,
        query: "sqlite retrieval",
        mode: "lexical",
        rerank: true,
        rerank_model_id: MODEL_ID,
        client: FakeEmbeddingClient.new(error: StandardError.new("provider unavailable"))
      )

      assert_not outcome.rerank_applied
      assert_includes outcome.rerank_note, "Reranking failed"
      assert_equal 1, outcome.results.length
      assert_equal "sqlite retrieval evidence", outcome.results.first.chunk.content_text
    end
  end

  test "rerank is not applied when it was not requested" do
    with_provider_configuration("openrouter") do
      add_item(title: "Notes A", text: "sqlite retrieval evidence")

      outcome = Ai::Knowledge::Search.call(
        collection: @collection,
        query: "sqlite retrieval",
        mode: "lexical",
        rerank_model_id: MODEL_ID,
        client: FakeEmbeddingClient.new
      )

      assert_not outcome.rerank_applied
      assert_nil outcome.rerank_note
    end
  end
end

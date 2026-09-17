require "test_helper"

class Ai::Knowledge::VectorStoreTest < ActiveSupport::TestCase
  setup do
    @adapter = Ai::Knowledge::VectorStore.default
  end

  test "encodes and decodes vectors with documented float32 precision" do
    vector = [ 0.1, -0.25, 0.5, 1.0 ]

    decoded = @adapter.decode(@adapter.encode(vector))

    assert_equal 4, decoded.length
    decoded.each_with_index do |value, index|
      assert_in_delta vector[index], value, 1e-6
    end
    assert_equal "float32", Ai::Knowledge::VectorStore::SqliteApplicationCosine::PRECISION
  end

  test "rejects empty vectors and unknown adapters" do
    assert_raises(Ai::Knowledge::VectorStore::Error) { @adapter.encode([]) }
    assert_raises(Ai::Knowledge::VectorStore::Error) { Ai::Knowledge::VectorStore.adapter_for("pgvector") }
  end

  test "cosine similarity reports identical, orthogonal and opposite vectors" do
    assert_in_delta 1.0, @adapter.cosine([ 0.3, 0.4 ], [ 0.3, 0.4 ]), 1e-6
    assert_in_delta 0.0, @adapter.cosine([ 1.0, 0.0 ], [ 0.0, 1.0 ]), 1e-6
    assert_in_delta(-1.0, @adapter.cosine([ 1.0, 0.0 ], [ -1.0, 0.0 ]), 1e-6)
    assert_in_delta 0.0, @adapter.cosine([ 0.0, 0.0 ], [ 1.0, 2.0 ]), 1e-6
    assert_raises(Ai::Knowledge::VectorStore::Error) { @adapter.cosine([ 1.0 ], [ 1.0, 2.0 ]) }
  end

  test "ranks candidates by similarity and honours the limit" do
    candidates = [
      { id: 1, vector: @adapter.encode([ 1.0, 0.0, 0.0 ]) },
      { id: 2, vector: @adapter.encode([ 1.0, 1.0, 0.0 ]) },
      { id: 3, vector: @adapter.encode([ 0.0, 0.0, 1.0 ]) }
    ]

    ranked = @adapter.rank(query_vector: [ 1.0, 1.0, 0.0 ], candidates: candidates, limit: 2)

    assert_equal [ 2, 1 ], ranked.map { |candidate, _| candidate[:id] }
    assert_in_delta 1.0, ranked.first[1], 1e-6
  end

  test "skips candidates whose stored dimension does not match the query" do
    candidates = [
      { id: 1, vector: @adapter.encode([ 1.0, 0.0 ]) },
      { id: 2, vector: @adapter.encode([ 1.0, 1.0, 0.0 ]) }
    ]

    ranked = @adapter.rank(query_vector: [ 1.0, 1.0, 0.0 ], candidates: candidates, limit: 5)

    assert_equal [ 2 ], ranked.map { |candidate, _| candidate[:id] }
  end
end

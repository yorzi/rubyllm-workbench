require "test_helper"

class Ai::Knowledge::VectorStoreSqliteExtensionTest < ActiveSupport::TestCase
  setup do
    @adapter = Ai::Knowledge::VectorStore.adapter_for("sqlite_vector_extension")
  end

  teardown do
    ENV.delete("SQLITE_VECTOR_PATH")
    ENV.delete("KNOWLEDGE_VECTOR_ADAPTER")
  end

  test "reports itself unavailable when no sqlite-vector binary is configured" do
    ENV["SQLITE_VECTOR_PATH"] = "/definitely/not/here/vector.dylib"

    assert_equal "sqlite_vector_extension", @adapter.key
    assert_not @adapter.available?
    assert_includes @adapter.unavailability_reason, "not found"
  end

  test "shares the float32 encoding with the default adapter so vectors stay portable" do
    other = Ai::Knowledge::VectorStore.default

    assert_equal other.encode([ 0.25, -0.5, 1.0 ]), @adapter.encode([ 0.25, -0.5, 1.0 ])
    assert_equal [ 0.25, -0.5, 1.0 ].map(&:to_f), @adapter.decode(@adapter.encode([ 0.25, -0.5, 1.0 ])).map { |value| value.round(4) }
  end

  test "index table names are dimension scoped and integer only" do
    assert_equal "knowledge_vector_index_1024", @adapter.index_table(1024)
    assert_equal "knowledge_vector_index_1536", @adapter.index_table("1536")
    assert_equal "knowledge_vector_index_1024", @adapter.index_table("1024; DROP TABLE knowledge_embeddings")
    assert_raises(Ai::Knowledge::VectorStore::Error) { @adapter.index_table(0) }
  end

  test "ranking refuses to run while the extension is unavailable" do
    ENV["SQLITE_VECTOR_PATH"] = "/definitely/not/here/vector.dylib"

    error = assert_raises(Ai::Knowledge::VectorStore::Error) do
      @adapter.rank(query_vector: [ 1.0, 0.0 ], candidates: [], limit: 5)
    end

    assert_includes error.message, "unavailable"
  end

  test "registry falls back to the default adapter and explains why" do
    ENV["SQLITE_VECTOR_PATH"] = "/definitely/not/here/vector.dylib"
    ENV["KNOWLEDGE_VECTOR_ADAPTER"] = "sqlite_vector_extension"

    selection = Ai::Knowledge::VectorStore.selection

    assert_equal "sqlite_vector_extension", selection.requested_key
    assert_equal "sqlite_application_cosine", selection.key
    assert_equal "sqlite_application_cosine", selection.adapter.key
    assert_includes selection.note, "sqlite_vector_extension unavailable"
  end

  test "registry honours an available adapter and reports no fallback note" do
    selection = Ai::Knowledge::VectorStore.selection

    assert_equal "sqlite_application_cosine", selection.key
    assert_nil selection.note
    assert selection.adapter.available?
  end

  test "search exposes the effective adapter and the fallback note" do
    ENV["SQLITE_VECTOR_PATH"] = "/definitely/not/here/vector.dylib"
    ENV["KNOWLEDGE_VECTOR_ADAPTER"] = "sqlite_vector_extension"
    project = create_project(name: "Adapter selection project")
    collection = project.knowledge_collections.create!(name: "Notes")
    item = collection.knowledge_items.create!(title: "Notes", content_text: "SQLite retrieval evidence lives here.")
    Ai::Knowledge::Ingestor.call(item)

    outcome = Ai::Knowledge::Search.call(collection: collection, query: "sqlite retrieval", mode: "lexical")

    assert_equal "sqlite_application_cosine", outcome.adapter_key
    assert_includes outcome.adapter_note, "sqlite_vector_extension unavailable"
    assert_equal 1, outcome.results.length
  end
end

require "test_helper"

class Ai::Knowledge::VectorStoreSqliteExtensionTest < ActiveSupport::TestCase
  # Exercise real SQLite index maintenance without claiming coverage of the
  # optional native binary. The scan probe reads the derived table and applies
  # the same cosine ordering/limit in Ruby.
  class SqliteIndexProbe < Ai::Knowledge::VectorStore::SqliteExtension
    def available?
      true
    end

    def index_rows(collection:, model_id:, dimension: 2)
      table = connection.quote_table_name(index_table(dimension))
      execute_sql("SELECT knowledge_embedding_id, vector FROM #{table} WHERE knowledge_collection_id = ? AND model_id = ?",
        [ collection.id, model_id ]).map do |row|
        row.is_a?(Hash) ? row : { "knowledge_embedding_id" => row[0], "vector" => row[1] }
      end
    end

    private

    def initialize_column!(_table, _dimension)
      # vector_init requires the optional extension.
    end

    def scan(table:, query_vector:, collection_id:, model_id:, limit:)
      quoted_table = connection.quote_table_name(table)
      rows = execute_sql("SELECT knowledge_embedding_id, vector FROM #{quoted_table} WHERE knowledge_collection_id = ? AND model_id = ?",
        [ collection_id, model_id ]).map do |row|
        row.is_a?(Hash) ? row : { "knowledge_embedding_id" => row[0], "vector" => row[1] }
      end
      rows.map do |row|
        { "knowledge_embedding_id" => row.fetch("knowledge_embedding_id"), "distance" => 1.0 - cosine(query_vector, decode(row.fetch("vector"))) }
      end.sort_by { |row| [ row.fetch("distance"), row.fetch("knowledge_embedding_id") ] }.first(limit)
    end
  end

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

  test "native derived partition contains only supplied fresh provider candidates before applying the limit" do
    adapter = SqliteIndexProbe.new
    collection = create_project(name: "Native provider partition project").knowledge_collections.create!(name: "Notes")
    excluded = create_embedding(collection, title: "Old provider", provider: "openai", vector: [ 1.0, 0.0 ])
    selected = create_embedding(collection, title: "Selected provider", provider: "openrouter", vector: [ 0.0, 1.0 ])
    stale = create_embedding(collection, title: "Stale source", provider: "openrouter", vector: [ 1.0, 0.0 ])
    stale.update!(content_checksum: "old-checksum")

    # Populate the previous partition first, then ask for the filtered candidate.
    adapter.rank(query_vector: [ 1.0, 0.0 ], candidates: [ excluded, selected, stale ], limit: 1,
      collection: collection, model_id: "shared-embed")
    ranked = adapter.rank(query_vector: [ 1.0, 0.0 ], candidates: [ selected ], limit: 1,
      collection: collection, model_id: "shared-embed")

    assert_equal [ selected.id ], adapter.index_rows(collection: collection, model_id: "shared-embed").map { |row| row.fetch("knowledge_embedding_id") }
    assert_equal [ selected.id ], ranked.map { |embedding, _| embedding.id }
    assert_in_delta 0.0, ranked.first.last, 1e-6
  end

  test "native derived partition refreshes replaced vectors even when source count and ids are unchanged" do
    adapter = SqliteIndexProbe.new
    collection = create_project(name: "Native vector replacement project").knowledge_collections.create!(name: "Notes")
    first = create_embedding(collection, title: "First", provider: "openrouter", vector: [ 1.0, 0.0 ])
    second = create_embedding(collection, title: "Second", provider: "openrouter", vector: [ 0.0, 1.0 ])

    before = adapter.rank(query_vector: [ 1.0, 0.0 ], candidates: [ first, second ], limit: 1,
      collection: collection, model_id: "shared-embed")
    first.update!(vector: adapter.encode([ 0.0, 1.0 ]))
    second.update!(vector: adapter.encode([ 1.0, 0.0 ]))
    after = adapter.rank(query_vector: [ 1.0, 0.0 ], candidates: [ first.reload, second.reload ], limit: 1,
      collection: collection, model_id: "shared-embed")

    assert_equal [ first.id ], before.map { |embedding, _| embedding.id }
    assert_equal [ second.id ], after.map { |embedding, _| embedding.id }
    assert_equal [ first.id, second.id ].sort, adapter.index_rows(collection: collection, model_id: "shared-embed").map { |row| row.fetch("knowledge_embedding_id") }.sort
    assert_in_delta 1.0, after.first.last, 1e-6
  end

  private

  def create_embedding(collection, title:, provider:, vector:)
    item = collection.knowledge_items.create!(title: title, content_text: "#{title} vector evidence.")
    Ai::Knowledge::Ingestor.call(item)
    chunk = item.knowledge_chunks.first
    chunk.knowledge_embeddings.create!(provider: provider, model_id: "shared-embed", dimensions: vector.length,
      vector: @adapter.encode(vector), content_checksum: chunk.content_checksum)
  end
end

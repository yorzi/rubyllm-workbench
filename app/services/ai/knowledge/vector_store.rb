module Ai
  module Knowledge
    # Bounded vector storage and similarity adapter interface.
    #
    # The Specs require a vector adapter interface without preemptively
    # introducing PostgreSQL/pgvector. Two adapters are registered:
    #
    # - `sqlite_application_cosine` (default): vectors stay in SQLite as packed
    #   Float32 blobs and cosine similarity is computed in Ruby. Valid for
    #   bounded local corpora.
    # - `sqlite_vector_extension` (opt-in spike): scans with the external
    #   sqlite-vector loadable extension when its binary is present, keeping
    #   exact brute-force cosine so evidence semantics are unchanged.
    #
    # Selection is explicit and never silent: when the requested adapter is
    # unavailable the registry falls back to the default and reports why.
    module VectorStore
      class Error < StandardError; end

      class Base
        PRECISION = "float32".freeze

        def key
          raise NotImplementedError
        end

        def available?
          true
        end

        def unavailability_reason
          nil
        end

        def encode(vector)
          values = Array(vector).map { |value| Float(value) }
          raise Error, "Vector must contain at least one dimension." if values.empty?

          values.pack("e*")
        end

        def decode(blob)
          return [] if blob.blank?

          blob.to_s.unpack("e*").map(&:to_f)
        end

        def cosine(left, right)
          raise Error, "Vector dimensions differ: #{left.length} vs #{right.length}." if left.length != right.length

          magnitude = Math.sqrt(dot(left, left)) * Math.sqrt(dot(right, right))
          return 0.0 if magnitude.zero?

          (dot(left, right) / magnitude).clamp(-1.0, 1.0)
        end

        def rank(query_vector:, candidates:, limit:, collection: nil, model_id: nil)
          raise NotImplementedError
        end

        private

        def dot(left, right)
          left.each_with_index.sum { |value, index| value * right[index].to_f }
        end
      end

      class SqliteApplicationCosine < Base
        def key
          "sqlite_application_cosine"
        end

        def rank(query_vector:, candidates:, limit:, collection: nil, model_id: nil)
          scored = candidates.filter_map do |candidate|
            vector = decode(candidate.is_a?(KnowledgeEmbedding) ? candidate.vector : candidate.fetch(:vector))
            next if vector.empty?
            next if vector.all?(&:zero?)
            next if vector.length != query_vector.length

            [ candidate, cosine(query_vector, vector) ]
          rescue Error
            nil
          end

          scored.sort_by { |candidate, score| [ -score, candidate_id(candidate) ] }
            .first([ limit.to_i, 1 ].max)
        end

        private

        def candidate_id(candidate)
          candidate.is_a?(KnowledgeEmbedding) ? candidate.id : candidate[:id].to_i
        end
      end

      class SqliteExtension < Base
        def key
          "sqlite_vector_extension"
        end

        def available?
          load_extension!
          true
        rescue Error => error
          @unavailability_reason = error.message
          false
        end

        def unavailability_reason
          @unavailability_reason
        end

        # The extension scans an integer-keyed table it has been initialized
        # on. `knowledge_embeddings.vector` mixes dimensions across embedding
        # models, and sqlite-vector declares one dimension per column and does
        # not check per-row blob length, so the adapter reads through a
        # dimension-scoped derived index instead of the source column.
        def rank(query_vector:, candidates:, limit:, collection: nil, model_id: nil)
          raise Error, "sqlite_vector_extension is unavailable: #{unavailability_reason}" unless available?
          return [] if candidates.empty? || collection.nil? || model_id.blank?

          dimension = query_vector.length
          table = index_table(dimension)
          ensure_index!(table: table, dimension: dimension, collection_id: collection.id, model_id: model_id)

          rows = scan(table: table, query_vector: query_vector, collection_id: collection.id, model_id: model_id, limit: limit)
          by_id = candidates.index_by(&:id)

          rows.filter_map do |row|
            embedding = by_id.fetch(row["knowledge_embedding_id"].to_i, nil)
            next if embedding.nil?

            [ embedding, similarity_from_distance(row["distance"]) ]
          end.first([ limit.to_i, 1 ].max)
        end

        def index_table(dimension)
          dimension = dimension.to_i
          raise Error, "Vector dimension must be a positive integer." unless dimension.positive?

          "knowledge_vector_index_#{dimension}"
        end

        private

        def ensure_index!(table:, dimension:, collection_id:, model_id:)
          connection.execute(<<~SQL)
            CREATE TABLE IF NOT EXISTS #{table} (
              knowledge_embedding_id INTEGER PRIMARY KEY,
              knowledge_collection_id INTEGER NOT NULL,
              model_id TEXT NOT NULL,
              vector BLOB NOT NULL
            )
          SQL

          if indexed_count(table, collection_id, model_id) != source_count(collection_id, model_id, dimension)
            rebuild_index!(table: table, dimension: dimension, collection_id: collection_id, model_id: model_id)
          end

          initialize_column!(table, dimension)
        end

        def rebuild_index!(table:, dimension:, collection_id:, model_id:)
          connection.transaction do
            execute_sql(
              "DELETE FROM #{table} WHERE knowledge_collection_id = ? AND model_id = ?",
              [ collection_id, model_id.to_s ]
            )
            execute_sql(<<~SQL, [ collection_id, model_id.to_s, dimension ])
              INSERT INTO #{table} (knowledge_embedding_id, knowledge_collection_id, model_id, vector)
              SELECT knowledge_embeddings.id, knowledge_items.knowledge_collection_id, knowledge_embeddings.model_id, knowledge_embeddings.vector
              FROM knowledge_embeddings
              JOIN knowledge_chunks ON knowledge_chunks.id = knowledge_embeddings.knowledge_chunk_id
              JOIN knowledge_items ON knowledge_items.id = knowledge_chunks.knowledge_item_id
              WHERE knowledge_items.knowledge_collection_id = ?
                AND knowledge_embeddings.model_id = ?
                AND knowledge_embeddings.status = 'ready'
                AND knowledge_embeddings.dimensions = ?
                AND knowledge_items.ingestion_status = 'ready'
            SQL
          end
        end

        def initialize_column!(table, dimension)
          raw.execute("SELECT vector_init('#{table}', 'vector', 'type=FLOAT32,dimension=#{dimension.to_i},distance=cosine')")
        end

        def scan(table:, query_vector:, collection_id:, model_id:, limit:)
          sql = <<~SQL
            SELECT #{table}.knowledge_embedding_id AS knowledge_embedding_id, v.distance AS distance
            FROM vector_full_scan('#{table}', 'vector', ?) AS v
            JOIN #{table} ON #{table}.knowledge_embedding_id = v.rowid
            WHERE #{table}.knowledge_collection_id = ? AND #{table}.model_id = ?
            ORDER BY v.distance
            LIMIT ?
          SQL

          statement = raw.prepare(sql)
          result = statement.execute([ SQLite3::Blob.new(encode(query_vector)), collection_id, model_id.to_s, limit.to_i ])
          rows = result.to_a
          columns = statement.columns
          rows.map { |row| row.is_a?(Hash) ? row : columns.each_with_index.to_h { |name, index| [ name, row[index] ] } }
        ensure
          statement&.close
        end

        # `distance=cosine` reports cosine distance; similarity is 1 - distance.
        def similarity_from_distance(distance)
          (1.0 - distance.to_f).clamp(-1.0, 1.0).round(6)
        end

        def indexed_count(table, collection_id, model_id)
          scalar(
            "SELECT COUNT(*) FROM #{table} WHERE knowledge_collection_id = ? AND model_id = ?",
            [ collection_id, model_id.to_s ]
          ).to_i
        end

        def source_count(collection_id, model_id, dimension)
          scalar(<<~SQL, [ collection_id, model_id.to_s, dimension ]).to_i
            SELECT COUNT(*)
            FROM knowledge_embeddings
            JOIN knowledge_chunks ON knowledge_chunks.id = knowledge_embeddings.knowledge_chunk_id
            JOIN knowledge_items ON knowledge_items.id = knowledge_chunks.knowledge_item_id
            WHERE knowledge_items.knowledge_collection_id = ?
              AND knowledge_embeddings.model_id = ?
              AND knowledge_embeddings.dimensions = ?
              AND knowledge_embeddings.status = 'ready'
              AND knowledge_items.ingestion_status = 'ready'
          SQL
        end

        # ActiveRecord's execute ignores bare array binds, and the extension
        # needs Blobs bound as Blobs, so index maintenance and scans go through
        # prepared statements on the underlying SQLite3 connection.
        def execute_sql(sql, binds = [])
          statement = raw.prepare(sql)
          statement.execute(binds).to_a
        ensure
          statement&.close
        end

        def scalar(sql, binds = [])
          row = execute_sql(sql, binds).first
          row.is_a?(Hash) ? row.values.first : row&.first
        end

        def load_extension!
          return true if loaded?

          path = extension_path
          raise Error, "no sqlite-vector binary found (set SQLITE_VECTOR_PATH or add vendor/sqlite-vector/vector.dylib)" if path.blank?
          raise Error, "sqlite-vector binary not found at #{path}" unless File.exist?(path)

          raw.enable_load_extension(true)
          raw.load_extension(path)
          version = raw.execute("SELECT vector_version()").flatten.first.to_s
          raise Error, "sqlite-vector loaded but vector_version() returned nothing" if version.blank?

          mark_loaded!
        rescue SQLite3::Exception, LoadError => error
          raise Error, "sqlite-vector could not be loaded: #{Ai::ErrorText.safe(error.message, limit: 200)}"
        end

        def extension_path
          configured = ENV["SQLITE_VECTOR_PATH"].to_s
          return configured if configured.present?

          Rails.root.glob("vendor/sqlite-vector/vector.{dylib,so}").first&.to_s
        end

        def loaded?
          raw.instance_variable_get(:@knowledge_sqlite_vector_loaded) == true
        end

        def mark_loaded!
          raw.instance_variable_set(:@knowledge_sqlite_vector_loaded, true)
        end

        def connection
          KnowledgeEmbedding.connection
        end

        def raw
          connection.raw_connection
        end
      end

      ADAPTERS = {
        "sqlite_application_cosine" => SqliteApplicationCosine,
        "sqlite_vector_extension" => SqliteExtension
      }.freeze

      DEFAULT_KEY = "sqlite_application_cosine".freeze
      SELECTION_ENV = "KNOWLEDGE_VECTOR_ADAPTER".freeze

      Selection = Data.define(:adapter, :key, :requested_key, :note)

      class << self
        def default
          selection.adapter
        end

        def selection
          requested_key = ENV.fetch(SELECTION_ENV, DEFAULT_KEY).to_s
          adapter = adapter_for(requested_key)
          return Selection.new(adapter: adapter, key: requested_key, requested_key: requested_key, note: nil) if adapter.available?

          fallback = adapter_for(DEFAULT_KEY)
          Selection.new(
            adapter: fallback,
            key: DEFAULT_KEY,
            requested_key: requested_key,
            note: "#{requested_key} unavailable (#{adapter.unavailability_reason}); using #{DEFAULT_KEY}"
          )
        end

        def adapter_for(key)
          ADAPTERS.fetch(key.to_s) { raise Error, "Unknown vector adapter: #{key}" }.new
        end

        def keys
          ADAPTERS.keys
        end
      end
    end
  end
end

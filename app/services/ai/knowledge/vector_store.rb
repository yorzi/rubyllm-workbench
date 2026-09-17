module Ai
  module Knowledge
    # Bounded vector storage and similarity adapter interface.
    #
    # The Specs require a vector adapter interface without preemptively
    # introducing PostgreSQL/pgvector. The default adapter keeps vectors in
    # SQLite as packed Float32 blobs and computes cosine similarity in the
    # application. That is only valid for bounded local corpora; the adapter
    # boundary exists so a SQLite vector extension (or a real vector store)
    # can replace it without touching callers.
    module VectorStore
      class Error < StandardError; end

      class Base
        def encode(vector)
          raise NotImplementedError
        end

        def decode(blob)
          raise NotImplementedError
        end

        def cosine(left, right)
          raise NotImplementedError
        end

        def rank(query_vector:, candidates:, limit:)
          raise NotImplementedError
        end

        def key
          raise NotImplementedError
        end
      end

      class SqliteApplicationCosine < Base
        PRECISION = "float32".freeze

        def key
          "sqlite_application_cosine"
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

        def rank(query_vector:, candidates:, limit:)
          scored = candidates.filter_map do |candidate|
            vector = decode(vector_for(candidate))
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

        def vector_for(candidate)
          candidate.is_a?(KnowledgeEmbedding) ? candidate.vector : candidate.fetch(:vector)
        end

        def candidate_id(candidate)
          candidate.is_a?(KnowledgeEmbedding) ? candidate.id : candidate[:id].to_i
        end

        def dot(left, right)
          left.each_with_index.sum { |value, index| value * right[index].to_f }
        end
      end

      ADAPTERS = {
        "sqlite_application_cosine" => SqliteApplicationCosine
      }.freeze

      DEFAULT_KEY = "sqlite_application_cosine".freeze

      class << self
        def default
          adapter_for(DEFAULT_KEY)
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

require "digest"

module Ai
  module Knowledge
    class EvidenceSnapshot
      LIMIT = 8
      MAX_CHUNK_CHARACTERS = 800

      class StaleEvidence < StandardError
        def code
          "stale_evidence"
        end
      end

      def self.capture(collection:, question:)
        outcome = Search.call(collection:, query: question, mode: "lexical", limit: LIMIT)
        evidence = outcome.results.each_with_index.map do |result, index|
          chunk = result.chunk
          source = chunk.knowledge_item
          if chunk.content_text.length > MAX_CHUNK_CHARACTERS
            raise ArgumentError, "A retrieved chunk exceeds 800 characters. Re-ingest with the default chunker before asking."
          end
          unless source.checksum == Digest::SHA256.hexdigest(source.content_text) &&
              source.content_text[chunk.char_start...chunk.char_end] == chunk.content_text
            raise StaleEvidence, "Source text and chunk offsets disagree. Re-ingest the source before asking."
          end

          {
            "evidence_id" => "e#{index + 1}", "chunk_id" => chunk.id,
            "source_id" => source.id, "title" => source.title,
            "source_reference" => source.source_reference,
            "source_checksum" => source.checksum, "chunk_checksum" => chunk.content_checksum,
            "position" => chunk.position, "char_start" => chunk.char_start, "char_end" => chunk.char_end,
            "line_start" => source.content_text[0...chunk.char_start].count("\n") + 1,
            "line_end" => source.content_text[0...[ chunk.char_end - 1, 0 ].max].count("\n") + 1,
            "chunker" => chunk.metadata_json.to_h["chunker"], "text" => chunk.content_text,
            "corpus_release" => release_metadata(source),
            "score" => result.score, "matched_terms" => result.matched_terms,
            "trust" => "untrusted"
          }
        end
        {
          "version" => 1, "collection_id" => collection.id, "collection_name" => collection.name,
          "question" => question, "corpus_checksum" => corpus_checksum(collection),
          "retrieval" => {
            "requested_mode" => "lexical", "mode" => outcome.mode, "algorithm" => "lexical-v1",
            "limit" => LIMIT, "embedding_model_id" => nil, "embedding_provider" => nil, "rerank" => false
          },
          "evidence" => evidence
        }
      end

      # This is a revision of the searchable corpus, including chunk boundaries,
      # rather than just a hash of the matching text. Adding/removing a source or
      # re-ingesting it also invalidates a queued answer.
      def self.corpus_checksum(collection)
        revisions = collection.knowledge_items.where(ingestion_status: "ready").order(:id)
          .includes(:knowledge_chunks).map do |source|
            [ source.id, source.title, source.source_reference, source.checksum,
              Digest::SHA256.hexdigest(source.content_text), release_metadata(source),
              source.knowledge_chunks.sort_by { |chunk| [ chunk.position, chunk.id ] }.map do |chunk|
                [ chunk.id, chunk.position, chunk.char_start, chunk.char_end, chunk.content_checksum,
                  chunk.metadata_json.to_h["chunker"] ]
              end ]
          end
        Digest::SHA256.hexdigest(JSON.generate(revisions))
      end

      def self.verify_current!(snapshot, project:)
        collection = project.knowledge_collections.find_by(id: snapshot.fetch("collection_id"))
        unless collection && corpus_checksum(collection) == snapshot.fetch("corpus_checksum")
          raise StaleEvidence, "The searchable corpus changed after this Run was queued. Create a new answer to retrieve current evidence."
        end
      end

      def self.release_metadata(source)
        source.metadata_json.to_h.fetch("knowledge_case_study", {}).slice(
          "id", "revision", "source_key", "source_path", "source_sha256", "content_sha256", "corpus_sha256", "license"
        )
      end
      private_class_method :release_metadata
    end
  end
end

require "test_helper"

class Ai::Knowledge::DocumentIngestorTest < ActiveSupport::TestCase
  OCR_MODEL_ID = "parse-v5.0"

  setup do
    @project = create_project(name: "Document project")
    @collection = @project.knowledge_collections.create!(name: "Documents")
  end

  test "extracts a text-like attachment locally and records provenance" do
    item = attach_file(filename: "notes.md", content_type: "text/markdown", body: "# Heading\n\nSQLite retrieval evidence lives here.\n")

    Ai::Knowledge::DocumentIngestor.call(item)

    item.reload
    assert_equal "ready", item.extraction_status
    assert_equal "local_text", item.extractor
    assert_equal "ready", item.ingestion_status
    assert_operator item.knowledge_chunks.count, :>, 0
    assert_includes item.content_text, "SQLite retrieval evidence"

    artifact = item.extraction_artifact
    assert_equal "ocr_document", artifact.kind
    assert_nil artifact.run_id
    assert_equal item.id, artifact.knowledge_item_id
    assert_equal "local_text", artifact.metadata_json["extractor"]
    assert_equal "notes.md", artifact.metadata_json["filename"]
    assert_equal "text/markdown", artifact.metadata_json["content_type"]
    assert_equal item.document.blob.checksum, artifact.metadata_json["blob_checksum"]
    assert_equal item.checksum, artifact.metadata_json["content_checksum"]
    assert_includes artifact.content_text, "SQLite retrieval evidence"
  end

  test "chunks extracted text with the shared chunker so documents are searchable" do
    item = attach_file(filename: "long.txt", content_type: "text/plain", body: ("sqlite retrieval evidence. " * 60))

    Ai::Knowledge::DocumentIngestor.call(item)

    item.reload
    assert_operator item.knowledge_chunks.count, :>, 1
    results = Ai::Knowledge::Retriever.search(collection: @collection, query: "sqlite retrieval")
    assert_equal item.id, results.first.chunk.knowledge_item_id
  end

  test "refuses a binary attachment when no OCR model is configured" do
    item = attach_file(filename: "scan.pdf", content_type: "application/pdf", body: "%PDF-1.4 not really a pdf")

    error = assert_raises(Ai::Knowledge::Extractor::Unsupported) do
      Ai::Knowledge::DocumentIngestor.call(item)
    end

    assert_includes error.message, "No OCR model is selected"
    item.reload
    assert_equal "failed", item.extraction_status
    assert_includes item.extraction_error, "No OCR model is selected"
  end

  test "refuses an attachment that is neither locally readable nor OCR readable" do
    item = attach_file(filename: "archive.zip", content_type: "application/zip", body: "PKbinary")

    assert_raises(Ai::Knowledge::Extractor::Unsupported) { Ai::Knowledge::DocumentIngestor.call(item) }

    assert_includes item.reload.extraction_error, "Unsupported attachment type"
  end

  test "extracts a PDF through a configured OCR model and records provider provenance" do
    with_provider_configuration("cohere") do
      item = attach_file(filename: "contract.pdf", content_type: "application/pdf", body: "%PDF-1.4 fake")

      with_knowledge_client(FakeEmbeddingClient.new) do
        Ai::Knowledge::DocumentIngestor.call(item, ocr_model_id: OCR_MODEL_ID)
      end

      item.reload
      assert_equal "ready", item.extraction_status
      assert_equal "ruby_llm_ocr", item.extractor
      assert_includes item.content_text, "extracted page"

      artifact = item.extraction_artifact
      assert_equal "ruby_llm_ocr", artifact.metadata_json["extractor"]
      assert_equal OCR_MODEL_ID, artifact.metadata_json["model_id"]
      assert_equal "cohere", artifact.metadata_json["provider"]
      assert_equal 1, artifact.metadata_json["page_count"]
    end
  end

  test "marks the source failed when the OCR provider fails" do
    with_provider_configuration("cohere") do
      item = attach_file(filename: "scan.png", content_type: "image/png", body: "fake png bytes")

      with_knowledge_client(FakeEmbeddingClient.new(error: StandardError.new("429 rate limited for sk-abcdef1234567890abcd"))) do
        assert_raises(Ai::Knowledge::DocumentIngestor::Error) do
          Ai::Knowledge::DocumentIngestor.call(item, ocr_model_id: OCR_MODEL_ID)
        end
      end

      item.reload
      assert_equal "failed", item.extraction_status
      assert_includes item.extraction_error, "[REDACTED]"
      refute_includes item.extraction_error, "sk-abcdef1234567890abcd"
    end
  end

  private

  def attach_file(filename:, content_type:, body:)
    item = @collection.knowledge_items.new(
      source_kind: "file",
      title: filename,
      source_reference: filename,
      content_text: " "
    )
    item.document.attach(io: StringIO.new(body), filename: filename, content_type: content_type)
    item.save!
    item
  end
end

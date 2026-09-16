require "test_helper"

class Ai::Knowledge::IngestorTest < ActiveSupport::TestCase
  test "ingests text into replaceable, inspectable chunks" do
    collection = create_project(name: "Ingestion project").knowledge_collections.create!(name: "Notes")
    item = collection.knowledge_items.create!(
      title: "Architecture notes",
      source_reference: "notes-001",
      content_text: "SQLite keeps the local evidence bounded.\nThe chunk offset is inspectable."
    )

    Ai::Knowledge::Ingestor.call(item)

    item.reload
    assert item.ready?
    assert_equal Digest::SHA256.hexdigest(item.content_text), item.checksum
    assert_equal 1, item.knowledge_chunks.count
    assert_equal "char_window_v1", item.knowledge_chunks.first.metadata_json.fetch("chunker")
    assert_equal item.content_text, item.knowledge_chunks.first.content_text
    assert_equal 0, item.knowledge_chunks.first.char_start
    assert_equal item.content_text.length, item.knowledge_chunks.first.char_end

    first_content = item.knowledge_chunks.first.content_text
    Ai::Knowledge::Ingestor.call(item)

    assert_equal 1, item.reload.knowledge_chunks.count
    assert_equal first_content, item.knowledge_chunks.first.content_text
  end
end

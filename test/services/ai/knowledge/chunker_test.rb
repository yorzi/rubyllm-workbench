require "test_helper"

class Ai::Knowledge::ChunkerTest < ActiveSupport::TestCase
  test "normalizes text and records deterministic character offsets" do
    text = "Alpha source\r\n\r\ncontains SQLite retrieval evidence for a local project."
    normalized = text.gsub(/\r\n?/, "\n").strip

    chunks = Ai::Knowledge::Chunker.call(normalized, max_chars: 28, overlap_chars: 6)

    assert_operator chunks.size, :>, 1
    assert_equal (0...chunks.size).to_a, chunks.map(&:position)
    chunks.each do |chunk|
      assert_equal chunk.content_text, normalized[chunk.char_start...chunk.char_end]
      assert_operator chunk.char_end, :>, chunk.char_start
      assert_operator chunk.char_end - chunk.char_start, :<=, 28
    end
    assert chunks.each_cons(2).all? { |left, right| right.char_start < left.char_end }
  end

  test "returns no chunks for blank text" do
    assert_empty Ai::Knowledge::Chunker.call(" \n\t ")
  end

  test "rejects invalid window options" do
    assert_raises(ArgumentError) { Ai::Knowledge::Chunker.call("text", max_chars: 0) }
    assert_raises(ArgumentError) { Ai::Knowledge::Chunker.call("text", max_chars: 10, overlap_chars: 10) }
    assert_raises(ArgumentError) { Ai::Knowledge::Chunker.call("text", max_chars: 10, overlap_chars: -1) }
  end
end

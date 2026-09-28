require "test_helper"
require "stringio"

module Ai
  class EvaluationCaseAttachmentContentValidatorTest < ActiveSupport::TestCase
    test "validates CSV and JSON contents rather than accepting the declared MIME type" do
      assert valid?("name,value\nanswer,42\n", "text/csv", "case.csv")
      refute valid?("name,value\n\"unterminated", "text/csv", "case.csv")
      assert valid?('{"answer":42}', "application/json", "case.json")
      refute valid?("{broken}", "application/json", "case.json")
      refute valid?("plain text", "image/png", "case.png")
      refute valid?("\xFF\x00".b, "text/plain", "case.txt")
    end

    test "restores stream position after rejected contents" do
      io = StringIO.new("{broken}")
      io.pos = 3

      refute EvaluationCaseAttachmentContentValidator.valid?(io:, content_type: "application/json", filename: "case.json")
      assert_equal 3, io.pos
    end

    private

    def valid?(contents, content_type, filename)
      EvaluationCaseAttachmentContentValidator.valid?(io: StringIO.new(contents), content_type:, filename:)
    end
  end
end

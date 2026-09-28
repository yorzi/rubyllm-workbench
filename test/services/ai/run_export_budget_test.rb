require "test_helper"

module Ai
  class RunExportBudgetTest < ActiveSupport::TestCase
    setup do
      @project = create_project(name: "Bounded export project")
      @chat = create_chat(@project)
      @run = @chat.runs.create!(project: @project, operation: "chat", status: :succeeded, requested_by: "test")
    end

    test "bounds nested collections and depth while preserving redaction" do
      deep = "hidden"
      12.times { deep = { "next" => deep } }
      @run.update!(input_snapshot_json: {
        "api_key" => "SECRET-SENTINEL", "list" => (1..80).to_a, "deep" => deep,
        "fields" => 75.times.to_h { |i| [ "field#{i}", i ] }
      })

      document = RunReproductionExporter.call(@run)
      assert_equal "[REDACTED]", document.dig("run", "input_snapshot", "api_key")
      assert_equal 50, document.dig("run", "input_snapshot", "list").size
      assert_equal 50, document.dig("run", "input_snapshot", "fields").size
      assert_equal 30, document.dig("truncation", "omitted", "nested_array_items")
      assert_equal 25, document.dig("truncation", "omitted", "nested_hash_entries")
      assert_operator document.dig("truncation", "omitted", "maximum_depth_values"), :>, 0
      refute_includes JSON.generate(document), "SECRET-SENTINEL"
    end

    test "bounds aggregate text and reports truncation for large Unicode strings" do
      @run.update!(input_snapshot_json: { "values" => Array.new(15) { "文" * 19_900 } })

      document = RunReproductionExporter.call(@run)
      assert_operator JSON.pretty_generate(document).bytesize, :<=, RunReproductionExporter::MAX_EXPORT_BYTES
      assert_operator document.dig("truncation", "omitted", "text_characters"), :>, 0
      assert_operator document.dig("truncation", "omitted", "text_values"), :>, 0
    end

    test "formatted byte overflow produces a compact Run summary" do
      @run.update!(input_snapshot_json: { "values" => Array.new(8) { "\u0001" * 19_900 } })

      document = RunReproductionExporter.call(@run)
      assert_equal @run.id, document.dig("run", "id")
      assert_equal 1, document.dig("truncation", "omitted", "full_export_exceeded_maximum_bytes")
      refute document.fetch("run").key?("input_snapshot")
      assert_operator JSON.pretty_generate(document).bytesize, :<=, RunReproductionExporter::MAX_EXPORT_BYTES
    end

    test "retains latest bounded Run messages in chronological order" do
      @run.update!(input_snapshot_json: { "conversation_message_high_watermark" => 0,
        "conversation_context" => Ai::ChatContextSnapshot.call(@chat) })
      105.times { |index| @chat.messages.create!(role: "user", content: "message #{index}") }
      @run.update!(result_summary_json: { "conversation_message_end_id" => @chat.messages.maximum(:id) })
      @chat.messages.create!(role: "user", content: "later Run")

      document = RunReproductionExporter.call(@run)
      assert_equal (5..104).map { |i| "message #{i}" },
        document.dig("chat_context", "run_messages").map { |message| message.fetch("content") }
      assert_equal 5, document.dig("truncation", "omitted", "chat_context.run_messages")
    end

    test "bounds value traversal for wide nested inputs" do
      @run.update!(input_snapshot_json: { "grid" => Array.new(50) { Array.new(50) { (1..50).to_a } } })

      document = RunReproductionExporter.call(@run)
      assert_operator document.dig("run", "input_snapshot", "grid").flatten.size, :<, 5_000
      assert_operator document.dig("truncation", "omitted", "nested_array_items"), :>, 0
      assert_operator JSON.pretty_generate(document).bytesize, :<=, RunReproductionExporter::MAX_EXPORT_BYTES
    end

    test "caps Artifact scanning even when recent records are excluded candidate reports" do
      @run.artifacts.create!(kind: "report", name: "Old report", content_text: "old report beyond scan window")
      @run.artifacts.insert_all!(Array.new(1_001) { |index|
        { kind: "report", name: "Candidate #{index}", created_at: 1.minute.from_now,
          metadata_json: { "report_type" => "upstream_candidate" } }
      })

      document = RunReproductionExporter.call(@run)
      assert_empty document.fetch("artifacts")
      assert_equal 1_000, document.dig("truncation", "omitted", "upstream_candidate_reports_excluded")
      assert_equal 2, document.dig("truncation", "omitted", "artifact_records_not_scanned_or_not_exported")
    end

    test "oversized saved issue draft omits its reproduction and long notes" do
      candidate = {
        "report_type" => "upstream_candidate", "title" => "Bounded draft", "category" => "unconfirmed",
        "evidence" => { "run_id" => @run.id }, "expected_behavior" => "expected",
        "observed_behavior" => "observed", "reproduction_steps" => "steps",
        "reproduction" => { "text" => "x" * 800_000 }
      }
      markdown = UpstreamIssueDraft.call(Struct.new(:content_json).new(candidate))

      assert_operator markdown.bytesize, :<=, UpstreamIssueDraft::MAX_MARKDOWN_BYTES
      assert_includes markdown, "Reproduction JSON and long-form notes were omitted"
      assert_includes markdown, "Run: ##{@run.id}"
      refute_includes markdown, "x" * 100
    end
  end
end

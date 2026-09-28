require "test_helper"

class RunEventExportTest < ActionDispatch::IntegrationTest
  setup do
    @project = create_project(name: "Event export project")
    @chat = create_chat(@project)
    @run = @chat.runs.create!(project: @project, operation: "chat", status: :succeeded, requested_by: "test",
      input_snapshot_json: { "prompt" => "PRIVATE-PROMPT" })
    @run.lifecycle_events.delete_all
  end

  test "downloads chronological redacted events scoped to one Run" do
    attempt = @run.attempts.create!(sequence: 1, provider: @chat.provider, model_id: @chat.model_id, status: :succeeded)
    later = event(Time.current, { "api_key" => "SECRET-SENTINEL", "result" => "safe" }, attempt:)
    earlier = event(1.minute.ago, { "url" => "https://example.test/file?sig=SIGNATURE-SENTINEL" })
    other = @chat.runs.create!(project: @project, operation: "chat", status: :succeeded, requested_by: "test")
    other.lifecycle_events.create!(name: "ai.run.succeeded", source: "test", occurred_at: Time.current,
      event_key: SecureRandom.uuid, payload_json: { "private" => "OTHER-RUN-SENTINEL" })
    @chat.messages.create!(role: "user", content: "PRIVATE-MESSAGE")

    get events_run_path(@run)

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_equal "private, no-store", response.headers.fetch("Cache-Control")
    assert_includes response.headers.fetch("Content-Disposition"), "run-#{@run.id}-events.json"
    document = JSON.parse(response.body)
    assert_equal "lifecycle_events", document.fetch("export_type")
    assert_equal [ earlier.id, later.id ], document.fetch("events").map { |row| row.fetch("id") }
    assert_equal attempt.id, document.fetch("events").last.fetch("attempt_id")
    assert_equal later.id, document.fetch("events").last.fetch("id")
    assert_equal earlier.id, document.fetch("event_high_watermark")
    assert_equal "[REDACTED]", document.fetch("events").last.dig("payload", "api_key")
    refute_match(/SENTINEL|PRIVATE-PROMPT|PRIVATE-MESSAGE/, response.body)
    refute document.key?("chat_context")
    refute document.fetch("run").key?("input_snapshot")

    get run_path(@run)
    assert_response :success
    assert_select "a[href=?]", events_run_path(@run), text: "Download events JSON"
  end

  test "empty and missing Runs have explicit results" do
    get events_run_path(@run)
    assert_response :success
    assert_empty JSON.parse(response.body).fetch("events")

    get events_run_path(id: Run.maximum(:id) + 1)
    assert_response :not_found
  end

  test "keeps latest 100 events in timestamp and id order with omission count" do
    time = Time.current
    103.times { |index| event(time, { "position" => index }) }
    expected_ids = @run.lifecycle_events.order(:id).pluck(:id).last(100)

    get events_run_path(@run)

    assert_response :success
    document = JSON.parse(response.body)
    assert_equal expected_ids, document.fetch("events").map { |row| row.fetch("id") }
    assert_equal 3, document.dig("truncation", "omitted", "events")
    assert_operator response.body.bytesize, :<=, Ai::RunReproductionExporter::MAX_EXPORT_BYTES
  end

  test "escaped event payloads fall back to a bounded identifiable event export" do
    8.times { event(Time.current, { "text" => "\u0001" * 19_900 }) }

    get events_run_path(@run)

    document = JSON.parse(response.body)
    assert_equal @run.id, document.dig("run", "id")
    assert_equal "lifecycle_events", document.fetch("export_type")
    assert_empty document.fetch("events")
    assert_equal 1, document.dig("truncation", "omitted", "full_export_exceeded_maximum_bytes")
    assert_operator response.body.bytesize, :<=, Ai::RunReproductionExporter::MAX_EXPORT_BYTES
  end

  private

  def event(time, payload, attempt: nil)
    @run.lifecycle_events.create!(name: "ai.run.succeeded", source: "test", occurred_at: time,
      event_key: SecureRandom.uuid, payload_json: payload, attempt:)
  end
end

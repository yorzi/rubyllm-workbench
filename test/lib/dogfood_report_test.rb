require "test_helper"
require_relative "../support/dogfood_report"

class DogfoodReportTest < ActiveSupport::TestCase
  test "unreported tokens remain unknown rather than becoming free zero usage" do
    assert_nil DogfoodReport.token_total([])
    assert_nil DogfoodReport.token_total([ nil ])
    assert_nil DogfoodReport.token_total([ 12, nil ])
    assert_equal 0, DogfoodReport.token_total([ 0, 0 ])
    assert_equal 30, DogfoodReport.token_total([ 12, 18 ])
  end

  test "HTTP evidence keeps failures and timing without request secrets or invented IDs" do
    payload = {
      provider: "openrouter", method: :post, status: nil,
      exception_object: IOError.new("Bearer fake-secret provider echo"),
      url: "https://example.com/?token=fake-secret", body: "private prompt",
      headers: { "Authorization" => "Bearer fake-secret" }
    }
    evidence = DogfoodReport.http_evidence(payload, duration_ms: 2.1234)
    assert_equal "IOError", evidence[:error_class]
    assert_equal 2.12, evidence[:duration_ms]
    assert_nil evidence[:http_status]
    assert_nil evidence[:request_id]
    assert_no_match(/fake-secret|private|Bearer/, evidence.to_json)

    success = DogfoodReport.http_evidence({ provider: "openrouter", method: :post, status: 200 }, duration_ms: 3)
    assert_equal 200, success[:http_status]
    assert_nil success[:error_class]
  end
end

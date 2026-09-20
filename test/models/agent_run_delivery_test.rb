require "test_helper"

class AgentRunDeliveryTest < ActiveSupport::TestCase
  setup do
    project = create_project(name: "Agent delivery project")
    chat = create_chat(project)
    @run = chat.runs.create!(
      project: project,
      operation: "agent",
      status: :queued,
      requested_by: "test",
      input_snapshot_json: { "prompt" => "run the agent" }
    )
  end

  test "deduplicates durable deliveries and fences expired dispatch claims" do
    first = AgentRunDelivery.record!(run: @run, intent: "execute", expected_generation: 0)
    duplicate = AgentRunDelivery.record!(run: @run, intent: "execute", expected_generation: 0)

    assert_equal first.id, duplicate.id
    first_token = first.claim_for_dispatch!
    assert first_token
    assert_nil first.claim_for_dispatch!

    re_claim_time = Time.current + 6.minutes
    assert_not first.mark_delivered!(token: first_token, now: re_claim_time)
    second_token = first.claim_for_dispatch!(now: re_claim_time)
    assert second_token
    assert_not_equal first_token, second_token
    assert_not first.mark_delivered!(token: first_token)
    assert first.mark_delivered!(token: second_token)
    assert first.reload.delivered_at
    assert_nil first.claim_token
  end

  test "retries a failed dispatch with a bounded delay and error class" do
    delivery = AgentRunDelivery.record!(run: @run, intent: "execute", expected_generation: 0)
    claim_token = delivery.claim_for_dispatch!

    assert delivery.retry_dispatch!(token: claim_token, error: IOError.new("queue unavailable"))

    delivery.reload
    assert_equal 1, delivery.dispatch_attempts
    assert_equal "IOError", delivery.last_error_class
    assert_operator delivery.available_at, :>, Time.current
    assert_nil delivery.claim_token
  end
end

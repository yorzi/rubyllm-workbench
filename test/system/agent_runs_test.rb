require "application_system_test_case"

class AgentRunsTest < ApplicationSystemTestCase
  test "Run cancellation requires confirmation and then stays terminal" do
    project = create_project(name: "Browser cancellation project")
    chat = create_chat(project)
    run = chat.runs.create!(
      project: project,
      operation: "agent",
      status: :running,
      started_at: Time.current,
      requested_by: "system test",
      input_snapshot_json: { "prompt" => "Synthetic pending task" }
    )
    attempt = run.attempts.create!(
      sequence: 1,
      provider: chat.provider,
      model_id: chat.model_id,
      status: :running,
      started_at: Time.current
    )
    confirmation = "Cancel this Run? The provider may already have accepted the request."

    visit run_path(run)

    dismiss_confirm(confirmation) do
      click_button "Cancel Run"
    end

    assert run.reload.running?
    assert attempt.reload.running?
    assert_selector "#run_#{run.id}_status", text: "Running"

    accept_confirm(confirmation) do
      click_button "Cancel Run"
    end

    assert_selector "#run_#{run.id}_status", text: "Cancelled"
    assert run.reload.cancelled?
    assert attempt.reload.cancelled?
  end
end

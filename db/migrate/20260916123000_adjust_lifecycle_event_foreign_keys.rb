class AdjustLifecycleEventForeignKeys < ActiveRecord::Migration[8.1]
  def up
    remove_lifecycle_event_foreign_keys

    add_foreign_key :lifecycle_events, :runs, on_delete: :cascade
    add_foreign_key :lifecycle_events, :attempts, on_delete: :nullify
    add_foreign_key :lifecycle_events, :artifacts, on_delete: :nullify
    add_foreign_key :lifecycle_events, :tool_invocations, on_delete: :nullify
    add_foreign_key :lifecycle_events, :approvals, on_delete: :nullify
  end

  def down
    remove_lifecycle_event_foreign_keys

    add_foreign_key :lifecycle_events, :runs
    add_foreign_key :lifecycle_events, :attempts
    add_foreign_key :lifecycle_events, :artifacts
    add_foreign_key :lifecycle_events, :tool_invocations
    add_foreign_key :lifecycle_events, :approvals
  end

  private

  def remove_lifecycle_event_foreign_keys
    remove_foreign_key :lifecycle_events, column: :run_id
    remove_foreign_key :lifecycle_events, column: :attempt_id
    remove_foreign_key :lifecycle_events, column: :artifact_id
    remove_foreign_key :lifecycle_events, column: :tool_invocation_id
    remove_foreign_key :lifecycle_events, column: :approval_id
  end
end

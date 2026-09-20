class AddAgentRunRecoveryFields < ActiveRecord::Migration[8.1]
  def change
    add_column :runs, :agent_execution_token, :string
    add_column :runs, :agent_execution_expires_at, :datetime
    add_column :runs, :agent_execution_generation, :integer, default: 0, null: false

    add_column :artifacts, :source_tool_call_id, :string
    add_index :artifacts, [ :run_id, :source_tool_call_id ],
      unique: true,
      name: "index_artifacts_on_run_and_source_tool_call"
  end
end

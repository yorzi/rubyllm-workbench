class CreateAgentRunDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_run_deliveries do |t|
      t.references :run, null: false, foreign_key: true
      t.references :approval_invocation, foreign_key: { to_table: :tool_invocations }
      t.string :intent, null: false
      t.integer :expected_generation
      t.string :dedupe_key, null: false
      t.datetime :available_at, null: false
      t.string :claim_token
      t.datetime :claimed_until
      t.integer :dispatch_attempts, null: false, default: 0
      t.datetime :delivered_at
      t.string :last_error_class

      t.timestamps
    end

    add_index :agent_run_deliveries, :dedupe_key, unique: true
    add_index :agent_run_deliveries, [ :delivered_at, :available_at, :claimed_until ],
      name: "index_agent_run_deliveries_for_dispatch"
  end
end

class CreateToolingRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :tool_definitions do |t|
      t.references :project, null: false, foreign_key: true
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.string :class_identifier, null: false
      t.json :schema_json, null: false, default: {}
      t.string :approval_policy, null: false, default: "never"
      t.boolean :enabled, null: false, default: true

      t.timestamps

      t.index [ :project_id, :key ], unique: true
      t.index [ :project_id, :enabled ]
    end

    create_table :tool_invocations do |t|
      t.references :run, null: false, foreign_key: true
      t.references :attempt, foreign_key: true
      t.references :tool_definition, foreign_key: true
      t.string :tool_call_id, null: false
      t.string :tool_key, null: false
      t.string :status, null: false, default: "requested"
      t.json :arguments_json, null: false, default: {}
      t.json :result_json
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :duration_ms
      t.string :error_class
      t.text :error_message

      t.timestamps

      t.index [ :run_id, :tool_call_id ], unique: true
      t.index [ :run_id, :status ]
      t.index :tool_key
    end

    create_table :approvals do |t|
      t.references :tool_invocation, null: false, foreign_key: true, index: false
      t.string :status, null: false, default: "pending"
      t.string :actor, null: false, default: "local_user"
      t.datetime :requested_at, null: false
      t.datetime :decided_at
      t.text :decision_note

      t.timestamps

      t.index [ :status, :requested_at ]
      t.index :tool_invocation_id, unique: true, name: "index_approvals_on_invocation_unique"
    end
  end
end

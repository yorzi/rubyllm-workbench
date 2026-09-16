class CreateLifecycleEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :lifecycle_events do |t|
      t.references :run, null: false, foreign_key: true
      t.references :attempt, foreign_key: true
      t.references :artifact, foreign_key: true
      t.references :tool_invocation, foreign_key: true
      t.references :approval, foreign_key: true
      t.string :name, null: false
      t.string :event_key, null: false
      t.string :source, null: false, default: "application"
      t.datetime :occurred_at, null: false
      t.integer :duration_ms
      t.json :payload_json, null: false, default: {}

      t.timestamps

      t.index :event_key, unique: true
      t.index [ :run_id, :occurred_at, :id ], name: "index_lifecycle_events_on_run_and_occurred_at"
      t.index [ :name, :occurred_at ], name: "index_lifecycle_events_on_name_and_occurred_at"
    end
  end
end

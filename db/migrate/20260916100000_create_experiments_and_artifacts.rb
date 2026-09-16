class CreateExperimentsAndArtifacts < ActiveRecord::Migration[8.1]
  def change
    create_table :experiments do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.text :system_prompt
      t.text :input_prompt, null: false
      t.json :schema_json, null: false
      t.json :generation_options_json, null: false, default: {}
      t.string :status, null: false, default: "runnable"
      t.integer :revision, null: false, default: 1
      t.datetime :archived_at

      t.timestamps

      t.index [ :project_id, :status, :updated_at ]
    end

    create_table :experiment_executions do |t|
      t.references :project, null: false, foreign_key: true
      t.references :experiment, null: false, foreign_key: true
      t.string :status, null: false, default: "queued"
      t.integer :target_count, null: false
      t.string :requested_by, null: false
      t.json :input_snapshot_json, null: false
      t.datetime :started_at
      t.datetime :finished_at
      t.text :error_summary

      t.timestamps

      t.index [ :experiment_id, :created_at ]
      t.index [ :project_id, :created_at ]
    end

    create_table :artifacts do |t|
      t.references :run, null: false, foreign_key: true
      t.references :attempt, foreign_key: true
      t.string :kind, null: false
      t.string :name
      t.text :content_text
      t.json :content_json
      t.json :metadata_json, null: false, default: {}

      t.timestamps

      t.index [ :run_id, :kind ]
    end

    add_reference :runs, :experiment, foreign_key: true
    add_reference :runs, :experiment_execution, foreign_key: true
  end
end

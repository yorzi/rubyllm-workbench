class CreateEvaluationWorkflows < ActiveRecord::Migration[8.1]
  def change
    create_table :evaluation_datasets do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.integer :current_revision, null: false, default: 0

      t.timestamps

      t.index [ :project_id, :updated_at ]
      t.index [ :project_id, :name ], unique: true
    end

    create_table :evaluation_dataset_revisions do |t|
      t.references :evaluation_dataset, null: false, foreign_key: true
      t.integer :revision, null: false
      t.json :cases_json, null: false

      t.timestamps

      t.index [ :evaluation_dataset_id, :revision ], unique: true, name: "index_evaluation_dataset_revisions_unique_version"
    end

    create_table :evaluation_executions do |t|
      t.references :project, null: false, foreign_key: true
      t.references :evaluation_dataset_revision, null: false, foreign_key: true
      t.references :experiment, foreign_key: { on_delete: :nullify }
      t.string :provider, null: false
      t.string :model_id, null: false
      t.string :status, null: false, default: "queued"
      t.integer :case_count, null: false
      t.string :requested_by, null: false
      t.json :input_snapshot_json, null: false
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps

      t.index [ :project_id, :created_at ]
      t.index [ :evaluation_dataset_revision_id, :created_at ], name: "index_evaluation_executions_on_dataset_revision_and_created"
    end

    create_table :evaluation_case_results do |t|
      t.references :evaluation_execution, null: false, foreign_key: true
      t.references :evaluation_dataset_revision, null: false, foreign_key: true
      t.references :run, index: false, foreign_key: { on_delete: :nullify }
      t.string :case_key, null: false
      t.integer :case_position, null: false
      t.json :input_json, null: false
      t.json :expected_output_json, null: false
      t.json :actual_output_json
      t.string :status, null: false, default: "queued"
      t.boolean :passed
      t.text :error_summary
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps

      t.index [ :evaluation_execution_id, :case_key ], unique: true, name: "index_evaluation_case_results_unique_case"
      t.index [ :run_id ], unique: true
    end
  end
end

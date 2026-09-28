class CreateEvaluationComparisons < ActiveRecord::Migration[8.1]
  def change
    create_table :evaluation_comparisons do |t|
      t.references :project, null: false, foreign_key: true
      t.references :evaluation_dataset_revision, null: false, foreign_key: true
      t.references :experiment, foreign_key: { on_delete: :nullify }
      t.json :dataset_snapshot_json, null: false
      t.json :experiment_snapshot_json, null: false
      t.json :model_targets_json, null: false
      t.string :requested_by, null: false

      t.timestamps

      t.index [ :project_id, :created_at ], name: "index_evaluation_comparisons_on_project_and_created"
    end

    add_reference :evaluation_executions, :evaluation_comparison, foreign_key: true
    add_index :evaluation_executions, [ :evaluation_comparison_id, :provider, :model_id ],
      unique: true,
      where: "evaluation_comparison_id IS NOT NULL",
      name: "index_evaluation_executions_on_comparison_and_model"
  end
end

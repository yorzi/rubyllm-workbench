class CreateEvaluationCaseJudgments < ActiveRecord::Migration[8.1]
  def change
    create_table :evaluation_case_judgments do |t|
      t.references :evaluation_case_result, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true, name: "index_evaluation_case_judgments_on_case_result" }
      t.references :run, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.json :input_snapshot_json, null: false
      t.json :result_json
      t.string :status, null: false, default: "queued"
      t.datetime :started_at
      t.datetime :finished_at
      t.text :error_summary
      t.timestamps
    end
    add_index :evaluation_case_judgments, [ :status, :started_at ], name: "index_evaluation_case_judgments_for_recovery"
  end
end

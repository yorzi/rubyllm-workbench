class CreateRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :runs do |t|
      t.references :project, null: false, foreign_key: true
      t.references :chat, null: false, foreign_key: true
      t.string :operation
      t.string :status
      t.datetime :started_at
      t.datetime :finished_at
      t.string :requested_by
      t.json :input_snapshot_json
      t.json :result_summary_json
      t.text :error_summary
      t.string :app_version
      t.string :ruby_llm_version
      t.integer :time_to_first_output_ms

      t.timestamps
    end
  end
end

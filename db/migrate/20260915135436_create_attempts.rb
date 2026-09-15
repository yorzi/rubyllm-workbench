class CreateAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :attempts do |t|
      t.references :run, null: false, foreign_key: true
      t.integer :sequence
      t.string :provider
      t.string :model_id
      t.string :status
      t.datetime :started_at
      t.datetime :finished_at
      t.integer :duration_ms
      t.integer :time_to_first_output_ms
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :cache_read_tokens
      t.integer :cache_write_tokens
      t.integer :thinking_tokens
      t.decimal :reported_cost
      t.decimal :estimated_cost
      t.string :currency
      t.string :cost_status
      t.string :request_id
      t.string :finish_reason
      t.string :error_class
      t.string :error_code
      t.text :error_message
      t.json :metadata_json
      t.json :ruby_llm_usage_ids_json

      t.timestamps
    end
  end
end

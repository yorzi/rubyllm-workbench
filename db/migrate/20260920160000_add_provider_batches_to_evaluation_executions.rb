class AddProviderBatchesToEvaluationExecutions < ActiveRecord::Migration[8.1]
  def change
    add_column :evaluation_executions, :execution_mode, :string, null: false, default: "individual"
    add_column :evaluation_executions, :provider_batch_id, :string
    add_column :evaluation_executions, :provider_batch_status, :string
    add_column :evaluation_executions, :provider_batch_raw_status, :string
    add_column :evaluation_executions, :provider_batch_submitted_at, :datetime
    add_column :evaluation_executions, :provider_batch_refreshed_at, :datetime
    add_column :evaluation_executions, :provider_batch_refresh_started_at, :datetime
    add_column :evaluation_executions, :provider_batch_error, :text

    add_column :evaluation_case_results, :submission_unknown_at, :datetime

    add_index :evaluation_executions, [ :provider, :provider_batch_id ],
      unique: true,
      where: "provider_batch_id IS NOT NULL",
      name: "index_evaluation_executions_on_provider_batch"
  end
end

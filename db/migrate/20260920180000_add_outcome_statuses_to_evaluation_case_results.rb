class AddOutcomeStatusesToEvaluationCaseResults < ActiveRecord::Migration[8.1]
  def change
    add_column :evaluation_case_results, :transport_status, :string
    add_column :evaluation_case_results, :schema_status, :string
  end
end

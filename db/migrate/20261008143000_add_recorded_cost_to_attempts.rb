class AddRecordedCostToAttempts < ActiveRecord::Migration[8.1]
  def change
    add_column :attempts, :recorded_cost, :decimal, precision: 18, scale: 10
  end
end

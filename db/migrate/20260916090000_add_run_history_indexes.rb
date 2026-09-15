class AddRunHistoryIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :runs, [ :status, :created_at ], name: "index_runs_on_status_and_created_at"
  end
end

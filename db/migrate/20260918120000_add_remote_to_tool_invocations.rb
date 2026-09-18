class AddRemoteToToolInvocations < ActiveRecord::Migration[8.1]
  def change
    add_column :tool_invocations, :remote, :boolean, null: false, default: false
    add_index :tool_invocations, :remote
  end
end

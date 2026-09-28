class AddErrorCodeToToolInvocations < ActiveRecord::Migration[8.1]
  def change
    add_column :tool_invocations, :error_code, :string
  end
end

class AddProjectContextToChats < ActiveRecord::Migration[8.1]
  def change
    add_reference :chats, :project, null: false, foreign_key: true
    add_column :chats, :title, :string

    add_index :chats, [ :project_id, :created_at ]
  end
end

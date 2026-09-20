class CreateAgentDefinitions < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_definitions do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.string :provider, null: false
      t.string :model_id, null: false
      t.text :instructions, null: false
      t.json :tool_keys_json, null: false, default: []
      t.json :provider_tools_json, null: false, default: []
      t.json :options_json, null: false, default: {}
      t.integer :revision, null: false, default: 1

      t.timestamps

      t.index [ :project_id, :name ], unique: true
      t.index [ :project_id, :updated_at ]
    end
  end
end

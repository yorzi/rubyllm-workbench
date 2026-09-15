class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.string :name
      t.string :slug
      t.text :description
      t.json :settings_json

      t.timestamps
    end
  end
end

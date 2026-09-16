class CreateKnowledgeRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :knowledge_collections do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description

      t.timestamps

      t.index [ :project_id, :name ]
    end

    create_table :knowledge_items do |t|
      t.references :knowledge_collection, null: false, foreign_key: true
      t.string :title, null: false
      t.string :source_kind, null: false, default: "text"
      t.string :source_reference
      t.text :content_text, null: false
      t.string :checksum, null: false
      t.string :ingestion_status, null: false, default: "pending"
      t.text :error_summary
      t.json :metadata_json, null: false, default: {}

      t.timestamps

      t.index [ :knowledge_collection_id, :ingestion_status ]
      t.index [ :knowledge_collection_id, :checksum ]
    end

    create_table :knowledge_chunks do |t|
      t.references :knowledge_item, null: false, foreign_key: true
      t.integer :position, null: false
      t.text :content_text, null: false
      t.integer :char_start, null: false
      t.integer :char_end, null: false
      t.json :metadata_json, null: false, default: {}

      t.timestamps

      t.index [ :knowledge_item_id, :position ], unique: true
    end
  end
end

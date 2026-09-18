class AddDocumentsToKnowledgeItems < ActiveRecord::Migration[8.1]
  def change
    add_column :knowledge_items, :extraction_status, :string, null: false, default: "not_required"
    add_column :knowledge_items, :extractor, :string
    add_column :knowledge_items, :extracted_at, :datetime
    add_column :knowledge_items, :extraction_error, :text
    add_column :knowledge_items, :extraction_metadata_json, :json, null: false, default: {}
    add_index :knowledge_items, :extraction_status

    change_column_null :artifacts, :run_id, true
    add_reference :artifacts, :knowledge_item, foreign_key: true, index: true
  end
end

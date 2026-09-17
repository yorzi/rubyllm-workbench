class CreateKnowledgeEmbeddings < ActiveRecord::Migration[8.1]
  def change
    create_table :knowledge_embeddings do |t|
      t.references :knowledge_chunk, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :model_id, null: false
      t.integer :dimensions, null: false
      t.binary :vector, null: false
      t.string :content_checksum, null: false
      t.string :status, null: false, default: "ready"
      t.integer :input_tokens
      t.decimal :reported_cost, precision: 16, scale: 10
      t.json :metadata_json, null: false, default: {}
      t.timestamps
    end

    add_index :knowledge_embeddings, [ :knowledge_chunk_id, :model_id ],
      unique: true, name: "index_knowledge_embeddings_on_chunk_and_model"
    add_index :knowledge_embeddings, [ :model_id, :status ],
      name: "index_knowledge_embeddings_on_model_and_status"

    add_column :knowledge_collections, :embedding_model_id, :string
    add_column :knowledge_collections, :embedding_provider, :string
    add_column :knowledge_collections, :embedding_dimensions, :integer
    add_column :knowledge_collections, :embedding_status, :string, null: false, default: "none"
    add_column :knowledge_collections, :embedded_at, :datetime
    add_column :knowledge_collections, :embedding_error, :text
  end
end

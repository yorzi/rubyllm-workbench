class CreateEvaluationDatasetCaseAttachments < ActiveRecord::Migration[8.1]
  def change
    create_table :evaluation_dataset_case_attachments do |t|
      t.references :evaluation_dataset_revision, null: false, foreign_key: { on_delete: :cascade }
      t.string :case_key, null: false
      t.integer :position, null: false

      t.timestamps
    end

    add_index :evaluation_dataset_case_attachments,
      [ :evaluation_dataset_revision_id, :case_key, :position ],
      unique: true,
      name: "index_evaluation_case_attachments_on_revision_case_position"
  end
end

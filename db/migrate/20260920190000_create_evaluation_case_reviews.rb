class CreateEvaluationCaseReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :evaluation_case_reviews do |t|
      t.references :evaluation_case_result,
        null: false,
        foreign_key: { on_delete: :cascade },
        index: { name: "index_evaluation_case_reviews_on_case_result" }
      t.string :verdict, null: false
      t.string :reviewer_label, null: false
      t.text :rationale

      t.timestamps
    end
  end
end

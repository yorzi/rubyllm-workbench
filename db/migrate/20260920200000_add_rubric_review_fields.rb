class AddRubricReviewFields < ActiveRecord::Migration[8.1]
  def change
    add_column :evaluation_case_results, :rubric_json, :json, null: false, default: []
    add_column :evaluation_case_reviews, :rubric_ratings_json, :json, null: false, default: {}
  end
end

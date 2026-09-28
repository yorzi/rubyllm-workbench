class EvaluationCaseReview < ApplicationRecord
  VERDICTS = %w[acceptable needs_work inconclusive].freeze
  RATINGS = %w[meets partially_meets does_not_meet not_applicable].freeze

  belongs_to :evaluation_case_result

  enum :verdict, VERDICTS.index_with(&:itself), validate: true

  validates :reviewer_label, presence: true, length: { maximum: 80 }
  validates :rationale, length: { maximum: 2_000 }, allow_blank: true
  validate :case_result_is_complete
  validate :rubric_ratings_match_frozen_rubric

  before_validation :normalize_reviewer_label
  before_update :prevent_mutation
  before_destroy :prevent_mutation

  def rubric_ratings
    return {} unless rubric_ratings_json.is_a?(Hash)

    rubric_ratings_json.deep_stringify_keys
  end

  private

  def normalize_reviewer_label
    self.reviewer_label = reviewer_label.to_s.strip
  end

  def case_result_is_complete
    return if evaluation_case_result&.completed?

    errors.add(:evaluation_case_result, "must have a completed structured response")
  end

  def rubric_ratings_match_frozen_rubric
    unless rubric_ratings_json.is_a?(Hash)
      errors.add(:rubric_ratings_json, "must be an object")
      return
    end

    expected_keys = evaluation_case_result&.rubric&.map { |criterion| criterion["key"] } || []
    ratings = rubric_ratings
    unless ratings.keys.sort == expected_keys.sort
      errors.add(:rubric_ratings_json, "must include exactly one rating for each frozen rubric criterion")
      return
    end

    return if ratings.values.all? { |rating| RATINGS.include?(rating) }

    errors.add(:rubric_ratings_json, "contains an unsupported criterion rating")
  end

  def prevent_mutation
    errors.add(:base, "Evaluation case reviews are append-only.")
    throw :abort
  end
end

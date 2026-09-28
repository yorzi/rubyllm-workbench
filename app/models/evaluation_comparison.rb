class EvaluationComparison < ApplicationRecord
  MIN_MODELS = 2
  MAX_MODELS = 5

  belongs_to :project
  belongs_to :evaluation_dataset_revision
  belongs_to :experiment, optional: true
  has_many :evaluation_executions, -> { order(:id) }, dependent: :destroy

  validates :requested_by, presence: true
  validate :project_scope_matches
  validate :snapshots_are_objects
  validate :model_targets_are_unique_and_bounded

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  before_update :keep_comparison_immutable

  def dataset_snapshot
    dataset_snapshot_json || {}
  end

  def experiment_snapshot
    experiment_snapshot_json || {}
  end

  def model_targets
    Array(model_targets_json)
  end

  private

  def snapshots_are_objects
    errors.add(:dataset_snapshot_json, "must be an object") unless dataset_snapshot_json.is_a?(Hash)
    errors.add(:experiment_snapshot_json, "must be an object") unless experiment_snapshot_json.is_a?(Hash)
  end

  def project_scope_matches
    dataset_project_id = evaluation_dataset_revision&.evaluation_dataset&.project_id
    errors.add(:evaluation_dataset_revision, "must belong to this Project") unless dataset_project_id == project_id
    if experiment && experiment.project_id != project_id
      errors.add(:experiment, "must belong to this Project")
    end
  end

  def model_targets_are_unique_and_bounded
    targets = model_targets
    unless targets.size.between?(MIN_MODELS, MAX_MODELS)
      errors.add(:model_targets_json, "must contain between #{MIN_MODELS} and #{MAX_MODELS} models")
      return
    end
    unless targets.all? { |target| target.is_a?(Hash) && target["provider"].present? && target["model_id"].present? }
      errors.add(:model_targets_json, "must include a provider and model ID for each target")
      return
    end

    references = targets.map { |target| [ target["provider"], target["model_id"] ] }
    errors.add(:model_targets_json, "must not repeat a provider/model pair") unless references.uniq.size == references.size
  end

  def keep_comparison_immutable
    errors.add(:base, "Evaluation comparisons are immutable.")
    throw :abort
  end
end

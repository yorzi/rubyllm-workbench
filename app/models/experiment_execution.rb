class ExperimentExecution < ApplicationRecord
  STATUSES = %w[queued running succeeded failed cancelled].freeze

  belongs_to :project
  belongs_to :experiment
  has_many :runs, dependent: :nullify

  enum :status, STATUSES.index_with(&:itself), validate: true

  validates :target_count, numericality: { only_integer: true, greater_than: 0 }
  validates :requested_by, presence: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def input_snapshot
    input_snapshot_json || {}
  end

  def terminal?
    succeeded? || failed? || cancelled?
  end

  def completed_count
    runs.count(&:terminal?)
  end

  def refresh_status!
    with_lock do
      child_runs = Run.where(experiment_execution_id: id).to_a
      next if child_runs.empty?

      next_status = if child_runs.all?(&:terminal?)
        child_runs.all?(&:succeeded?) ? :succeeded : :failed
      elsif child_runs.any?(&:running?)
        :running
      else
        :queued
      end

      attributes = { status: next_status }
      attributes[:started_at] = Time.current if next_status == :running && started_at.nil?
      if %i[succeeded failed].include?(next_status)
        attributes[:finished_at] = Time.current
        attributes[:error_summary] = if next_status == :failed
          child_runs.filter_map(&:error_summary).join("; ").presence || "One or more child runs did not succeed."
        end
      end
      update!(attributes)
    end

    self
  end
end

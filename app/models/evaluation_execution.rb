class EvaluationExecution < ApplicationRecord
  class ManuallyClosedSubmissionError < StandardError
    def code
      "provider_batch_submission_unknown_closed_manually"
    end
  end

  STATUSES = %w[queued preparing submitting running completed failed submission_unknown].freeze
  EXECUTION_MODES = %w[individual provider_batch].freeze
  PROVIDER_BATCH_REFRESH_THROTTLE = 30.seconds
  UNKNOWN_SUBMISSION_CLOSE_WAIT = 30.minutes
  ResumeResult = Data.define(:queued_count, :rejected_count)

  belongs_to :project
  belongs_to :evaluation_dataset_revision
  belongs_to :evaluation_comparison, optional: true
  belongs_to :experiment, optional: true
  has_many :evaluation_case_results, -> { order(:case_position, :id) }, dependent: :destroy
  has_many :evaluation_case_judgments, through: :evaluation_case_results
  has_many :runs, through: :evaluation_case_results

  enum :status, STATUSES.index_with(&:itself), validate: true
  enum :execution_mode, EXECUTION_MODES.index_with(&:itself), validate: true

  validates :provider, :model_id, :requested_by, presence: true
  validates :case_count, numericality: { only_integer: true, greater_than: 0 }
  validate :comparison_context_matches, if: -> { evaluation_comparison.present? }

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def input_snapshot
    input_snapshot_json || {}
  end

  def completed_count
    evaluation_case_results.where(status: %w[completed failed]).count
  end

  def submission_unknown_count
    evaluation_case_results.where(status: "submission_unknown").count
  end

  def passed_count
    evaluation_case_results.where(status: "completed", passed: true).count
  end

  def failed_count
    evaluation_case_results.where(status: "failed").or(
      evaluation_case_results.where(status: "completed", passed: false)
    ).count
  end

  def resume_unstarted!
    return ResumeResult.new(0, 0) unless individual? && !completed?

    eligible = evaluation_case_results.queued.includes(:run, :evaluation_dataset_revision).select do |result|
      run = result.run
      run&.queued? && run.started_at.nil? && run.attempts.all?(&:queued?)
    end
    queued_count = 0
    rejected_count = 0
    eligible.each do |result|
      Ai::EvaluationJobEnqueuer.call(EvaluationCaseJob, result.id)
      result.clear_enqueue_rejection!
      queued_count += 1
    rescue StandardError => error
      result.record_enqueue_rejection!(error)
      rejected_count += 1
    end
    ResumeResult.new(queued_count, rejected_count)
  end

  def resume_unstarted_judgments!
    eligible = evaluation_case_judgments.queued.where(
      "evaluation_case_judgments.error_summary LIKE ?",
      "#{EvaluationCaseJudgment::ENQUEUE_REJECTION_PREFIX}%"
    )
      .includes(:run).to_a.select do |judgment|
      child_run = judgment.run
      child_run&.queued? && child_run.started_at.nil? && child_run.attempts.all?(&:queued?)
    end
    queued_count = 0
    rejected_count = 0
    eligible.each do |judgment|
      Ai::EvaluationCaseJudgeEnqueuer.enqueue_existing(judgment)
      judgment.reload.error_summary.present? ? rejected_count += 1 : queued_count += 1
    end
    ResumeResult.new(queued_count, rejected_count)
  end

  def begin_provider_batch_preparation!
    claimed = false
    with_lock do
      reload
      next unless provider_batch? && queued?

      update!(status: :preparing, started_at: started_at || Time.current)
      claimed = true
    end
    claimed
  end

  def fail_queued_provider_batch_enqueue!(error:)
    failed = false
    with_lock do
      reload
      next unless provider_batch? && queued?

      summary = Ai::ErrorText.safe(error.message).to_s.truncate(2_000)
      update!(status: :failed, provider_batch_error: "Provider Batch job was not queued: #{summary}", finished_at: Time.current)
      evaluation_case_results.queued.includes(:run).each { |result| result.fail!(error) }
      failed = true
    end
    failed
  end

  def begin_provider_batch_submission!
    submitted = false
    with_lock do
      reload
      next unless provider_batch? && preparing?

      case_results = evaluation_case_results.includes(run: :attempts).order(:case_position, :id).to_a
      ready = case_results.size == case_count && case_results.all? do |result|
        run = result.run
        result.running? && run&.running? && run.attempts.last&.running?
      end
      next unless ready

      update!(status: :submitting)
      submitted = true
    end
    submitted
  end

  def record_provider_batch!(batch)
    with_lock do
      reload
      next unless provider_batch? && submitting? && provider_batch_id.blank?

      update!(
        provider_batch_id: batch.id,
        provider_batch_status: batch.status.to_s,
        provider_batch_raw_status: batch.raw_status.to_s,
        provider_batch_submitted_at: Time.current,
        provider_batch_refreshed_at: Time.current,
        provider_batch_error: nil,
        status: :running
      )
    end
    self
  end

  def claim_provider_batch_refresh!
    claimed = false
    with_lock do
      reload
      next unless provider_batch? && running? && provider_batch_id.present?
      next if provider_batch_refresh_started_at && provider_batch_refresh_started_at > PROVIDER_BATCH_REFRESH_THROTTLE.ago

      update!(provider_batch_refresh_started_at: Time.current)
      claimed = true
    end
    claimed
  end

  def record_provider_batch_refresh!(batch)
    with_lock do
      reload
      next unless provider_batch? && running? && provider_batch_id == batch.id

      update!(
        provider_batch_status: batch.status.to_s,
        provider_batch_raw_status: batch.raw_status.to_s,
        provider_batch_refreshed_at: Time.current,
        provider_batch_error: nil
      )
    end
    self
  end

  def record_provider_batch_refresh_error!(error)
    with_lock do
      reload
      next unless provider_batch? && running?

      update!(provider_batch_refreshed_at: Time.current, provider_batch_error: Ai::ErrorText.safe(error.message).to_s.truncate(2_000))
    end
    self
  end

  def recover_provider_batch_preparation!(error:)
    recovered = false
    with_lock do
      reload
      next false unless preparing?

      update!(status: :failed, provider_batch_error: Ai::ErrorText.safe(error.message), finished_at: Time.current)
      recovered = true
    end
    return false unless recovered

    evaluation_case_results.where(status: %w[queued running]).each do |result|
      result.fail!(error, before_provider_submission: true)
    end
    recovered
  end

  def recover_provider_batch_submission!(error:)
    return false unless submitting? || submission_unknown?
    return true if reconcile_provider_batch_from_store!
    return false unless submitting?

    mark_submission_unknown!(error)
  end

  def close_unresolved_provider_batch!
    return false unless manually_closable_unknown_submission?
    return false if reconcile_provider_batch_from_store!

    closed = false
    with_lock do
      reload
      next unless manually_closable_unknown_submission?

      case_results = evaluation_case_results.includes(run: :attempts).order(:case_position, :id).to_a
      closable = case_results.size == case_count && case_results.all? do |result|
        run = result.run
        result.submission_unknown? && run&.running? && run.attempts.last&.running?
      end
      next unless closable

      error = ManuallyClosedSubmissionError.new(
        "Provider batch status could not be reconciled. The local evaluation was closed manually; the provider may still process the request."
      )
      unless case_results.all? { |result| result.close_unknown_submission!(error:) }
        raise ActiveRecord::Rollback
      end

      update!(status: :failed, provider_batch_error: Ai::ErrorText.safe(error.message), finished_at: Time.current)
      closed = true
    end
    closed
  end

  def manually_closable_unknown_submission?
    provider_batch? && submission_unknown? && provider_batch_id.blank? &&
      updated_at <= UNKNOWN_SUBMISSION_CLOSE_WAIT.ago
  end

  def reconcile_provider_batch_from_store!
    return false unless provider_batch? && (submitting? || submission_unknown?)

    chat_ids = evaluation_case_results.includes(run: :chat).order(:case_position, :id).map { |result| result.run&.chat_id }
    return false if chat_ids.empty? || chat_ids.any?(&:nil?)

    # Active Record treats an Array predicate as SQL IN, including for this
    # JSON column. Compare the serialized array value so order and membership
    # both match RubyLLM's persisted submission record.
    stored_batch = RubyLLM::ActiveRecord::Batch.where(provider:)
      .where("chat_ids = ?", JSON.generate(chat_ids))
      .order(:id).last
    return false unless stored_batch

    with_lock do
      reload
      next false unless (submitting? || submission_unknown?) && provider_batch_id.blank?

      if submission_unknown?
        case_results = evaluation_case_results.includes(run: :attempts).order(:case_position, :id).to_a
        recoverable = case_results.size == case_count && case_results.all? do |result|
          run = result.run
          %w[running submission_unknown].include?(result.status) && run&.running? && run.attempts.last&.running?
        end
        next false unless recoverable

        evaluation_case_results.where(status: "submission_unknown").update_all(
          status: "running",
          passed: nil,
          submission_unknown_at: nil,
          finished_at: nil,
          error_summary: nil,
          updated_at: Time.current
        )
      end

      update!(
        provider_batch_id: stored_batch.provider_batch_id,
        provider_batch_status: stored_batch.status,
        provider_batch_raw_status: stored_batch.raw_status,
        provider_batch_submitted_at: stored_batch.created_at,
        provider_batch_refreshed_at: stored_batch.updated_at,
        provider_batch_error: nil,
        status: :running,
        finished_at: nil
      )
      true
    end
  end

  def mark_submission_unknown!(error)
    marked = false
    with_lock do
      reload
      next unless provider_batch? && submitting? && provider_batch_id.blank?

      summary = Ai::ErrorText.safe(error.message).to_s.truncate(2_000)
      update!(status: :submission_unknown, provider_batch_error: summary, finished_at: Time.current)
      evaluation_case_results.where(status: %w[queued running]).each do |result|
        result.mark_submission_unknown!(error)
      end
      marked = true
    end
    marked
  end

  def refresh_status!
    with_lock do
      reload
      results = evaluation_case_results.to_a
      next if results.empty?

      next if preparing? || submitting? || submission_unknown? || completed? || failed?

      all_finished = results.all? { |result| result.completed? || result.failed? }
      next_status = if all_finished
        :completed
      elsif results.any?(&:submission_unknown?)
        :submission_unknown
      elsif results.any?(&:running?)
        :running
      else
        :queued
      end
      attributes = { status: next_status }
      attributes[:started_at] = Time.current if next_status == :running && started_at.nil?
      attributes[:finished_at] = Time.current if next_status.in?(%i[completed submission_unknown])
      update!(attributes)
    end
    self
  end

  private

  def comparison_context_matches
    unless evaluation_comparison.project_id == project_id &&
        evaluation_comparison.evaluation_dataset_revision_id == evaluation_dataset_revision_id
      errors.add(:evaluation_comparison, "must share this Project and dataset revision")
    end
    unless evaluation_comparison.model_targets.any? { |target| target["provider"] == provider && target["model_id"] == model_id }
      errors.add(:evaluation_comparison, "must include this provider/model target")
    end
    return if input_snapshot.dig("dataset") == evaluation_comparison.dataset_snapshot &&
      input_snapshot.dig("experiment") == evaluation_comparison.experiment_snapshot

    errors.add(:input_snapshot_json, "must match the frozen comparison inputs")
  end
end

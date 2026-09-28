class EvaluationCaseJudgment < ApplicationRecord
  STATUSES = %w[queued running completed failed submission_unknown].freeze
  ENQUEUE_REJECTION_PREFIX = "Queue adapter did not accept this judge:".freeze

  belongs_to :evaluation_case_result
  belongs_to :run

  enum :status, STATUSES.index_with(&:itself), validate: true

  validates :input_snapshot_json, presence: true
  validates :evaluation_case_result_id, uniqueness: true
  validates :run_id, uniqueness: true
  before_update :keep_input_immutable

  def input_snapshot
    input_snapshot_json || {}
  end

  def result
    result_json || {}
  end

  def claim!
    claimed = false
    with_lock do
      reload
      next unless queued?
      next unless run&.claim_queued_execution!(operation: "structured")

      update!(status: :running, started_at: Time.current, error_summary: nil)
      claimed = true
    end
    claimed
  end

  def record_enqueue_rejection!(error)
    with_lock do
      reload
      next unless queued? && run&.queued? && run.started_at.nil?

      message = Ai::ErrorText.safe(error.message).to_s.truncate(1_500)
      update!(error_summary: "#{ENQUEUE_REJECTION_PREFIX} #{message}")
    end
    self
  end

  def clear_enqueue_rejection!
    with_lock do
      reload
      next unless queued? && error_summary&.start_with?(ENQUEUE_REJECTION_PREFIX)

      update!(error_summary: nil)
    end
    self
  end

  def complete_from_run!
    with_lock do
      reload
      next unless running?

      child_run = run
      child_run.reload
      next unless child_run.terminal?

      if child_run.succeeded?
        output = child_run.result_summary["structured_output"]
        rubric = Array(input_snapshot["rubric"]).map(&:deep_stringify_keys)
        if Ai::EvaluationRubricJudge.valid_result?(output, rubric)
          update!(status: :completed, result_json: output.deep_stringify_keys, error_summary: nil, finished_at: Time.current)
        else
          update!(status: :failed, error_summary: "Judge response did not contain exactly one supported rating for every frozen criterion.", finished_at: Time.current)
        end
      else
        update!(status: :failed, error_summary: child_run.error_summary.presence || "Judge Run #{child_run.status}.", finished_at: Time.current)
      end
    end
    self
  end

  def fail!(error)
    with_lock do
      reload
      next unless queued? || running?

      child_run = run
      child_run&.fail!(error) unless child_run&.terminal?
      update!(status: :failed, error_summary: Ai::ErrorText.safe(error.message).to_s.truncate(2_000), finished_at: Time.current)
    end
    self
  end

  def recover_stale!(cutoff:, error:)
    recovered = false
    with_lock do
      reload
      next unless running? && started_at && started_at <= cutoff

      child_run = run
      next unless child_run

      attempt = child_run.attempts.order(:sequence, :id).last
      if child_run.terminal?
        if child_run.succeeded?
          output = child_run.result_summary["structured_output"]
          rubric = Array(input_snapshot["rubric"]).map(&:deep_stringify_keys)
          if Ai::EvaluationRubricJudge.valid_result?(output, rubric)
            update!(status: :completed, result_json: output.deep_stringify_keys, error_summary: nil, finished_at: Time.current)
          else
            update!(status: :failed, error_summary: "Judge response did not contain exactly one supported rating for every frozen criterion.", finished_at: Time.current)
          end
        else
          update!(status: :failed, error_summary: child_run.error_summary.presence || "Judge Run #{child_run.status}.", finished_at: Time.current)
        end
        recovered = true
        next
      end

      if child_run.running?
        finished = child_run.finish_running_execution!(
          operation: "structured",
          status: :failed,
          error:,
          summary: { "evaluation_judge" => { "submission_unknown" => true, "automatic_replay" => false } },
          started_before: cutoff
        ) do
          attempt&.finish!(
            status: :failed,
            finished_at: Time.current,
            error_class: error.class.name,
            error_code: "evaluation_judge_submission_unknown",
            error_message: Ai::ErrorText.safe(error.message)
          )
        end
        next unless finished
      else
        next unless child_run.queued?

        queued_error = JudgeWorkerInterruptedBeforeStartError.new("Automated judge worker stopped before the Run started; this request was not submitted.")
        next unless child_run.fail_queued_execution!(operation: "structured", error: queued_error) do
          attempt&.finish!(
            status: :failed,
            finished_at: Time.current,
            error_class: queued_error.class.name,
            error_code: queued_error.code,
            error_message: queued_error.message
          )
        end
        update!(status: :failed, error_summary: queued_error.message, finished_at: Time.current)
        recovered = true
        next
      end

      update!(status: :submission_unknown, error_summary: Ai::ErrorText.safe(error.message).to_s.truncate(2_000), finished_at: Time.current)
      recovered = true
    end
    recovered
  end

  private

  class JudgeWorkerInterruptedBeforeStartError < StandardError
    def code
      "evaluation_judge_worker_interrupted_before_start"
    end
  end

  def keep_input_immutable
    return unless will_save_change_to_input_snapshot_json?

    errors.add(:input_snapshot_json, "is the frozen automated judge input.")
    throw :abort
  end
end

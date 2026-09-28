class EvaluationCaseResult < ApplicationRecord
  STATUSES = %w[queued running completed failed submission_unknown].freeze
  TRANSPORT_STATUSES = %w[not_attempted received failed cancelled unknown].freeze
  SCHEMA_STATUSES = %w[not_attempted valid invalid unknown].freeze

  belongs_to :evaluation_execution
  belongs_to :evaluation_dataset_revision
  belongs_to :run, optional: true
  has_one :evaluation_case_judgment, dependent: :destroy
  has_many :evaluation_case_reviews, -> { order(:created_at, :id) }, dependent: :delete_all

  enum :status, STATUSES.index_with(&:itself), validate: true
  enum :transport_status, TRANSPORT_STATUSES.index_with(&:itself), prefix: true, validate: { allow_nil: true }
  enum :schema_status, SCHEMA_STATUSES.index_with(&:itself), prefix: true, validate: { allow_nil: true }

  validates :case_key, presence: true, length: { maximum: 120 }, uniqueness: { scope: :evaluation_execution_id }
  validates :case_position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  before_validation :freeze_rubric_from_revision, on: :create
  before_update :keep_rubric_immutable

  def rubric
    Array(rubric_json).map(&:deep_stringify_keys)
  end

  def rubric_rating_summary
    ratings = EvaluationCaseReview::RATINGS
    counts = rubric.to_h { |criterion| [ criterion.fetch("key"), ratings.index_with(0) ] }
    reviews = evaluation_case_reviews.to_a

    reviews.each do |review|
      review.rubric_ratings.each do |key, rating|
        counts[key][rating] += 1 if counts.dig(key, rating)
      end
    end

    rubric.map do |criterion|
      { criterion:, counts: counts.fetch(criterion.fetch("key")), denominator: reviews.size }
    end
  end

  def claim!
    claimed = false
    with_lock do
      reload
      next unless queued?

      update!(status: :running, started_at: Time.current, error_summary: nil)
      claimed = true
    end
    claimed
  end

  def record_enqueue_rejection!(error)
    with_lock do
      reload
      next unless queued?

      child_run = run
      next unless child_run&.queued? && child_run.started_at.nil?

      message = Ai::ErrorText.safe(error.message).to_s.truncate(1_500)
      update!(error_summary: "Queue adapter did not accept this case: #{message}")
    end
    self
  end

  def clear_enqueue_rejection!
    with_lock do
      reload
      next unless queued? && error_summary&.start_with?("Queue adapter did not accept this case:")

      update!(error_summary: nil)
    end
    self
  end

  def evaluate_run!
    completed_successfully = false
    with_lock do
      reload
      next unless running? && run

      run.reload
      next unless run.terminal?

      outcome = Ai::EvaluationCaseOutcome.call(run)

      if run.succeeded?
        actual = run.result_summary["structured_output"]
        passed = canonical_json(actual) == canonical_json(expected_output_json)
        update!(
          transport_status: outcome.transport_status,
          schema_status: outcome.schema_status,
          status: :completed,
          passed:,
          actual_output_json: actual,
          error_summary: passed ? nil : "Structured output did not exactly match the expected JSON value.",
          finished_at: Time.current
        )
        completed_successfully = true
      else
        update!(
          transport_status: outcome.transport_status,
          schema_status: outcome.schema_status,
          status: :failed,
          passed: false,
          error_summary: run.error_summary.presence || "Child Run #{run.status}.",
          finished_at: Time.current
        )
      end
    end
    Ai::EvaluationCaseJudgeEnqueuer.call(self) if completed_successfully
    evaluation_execution.refresh_status!
    self
  end

  def fail!(error, before_provider_submission: false)
    with_lock do
      reload
      next unless queued? || running?

      child_run = run
      if child_run && !child_run.terminal?
        attempt = child_run.attempts.where(status: %w[queued running]).reorder(sequence: :desc, id: :desc).first
        attempt&.finish!(
          status: :failed,
          finished_at: Time.current,
          error_class: error.class.name,
          error_code: Ai::ErrorClassifier.code(error),
          error_message: Ai::ErrorText.safe(error.message)
        )
        child_run.fail!(error)
      end

      outcome = if before_provider_submission
        Ai::EvaluationCaseOutcome::Outcome.new("not_attempted", "not_attempted")
      else
        Ai::EvaluationCaseOutcome.call(child_run)
      end

      update!(
        transport_status: outcome.transport_status,
        schema_status: outcome.schema_status,
        status: :failed,
        passed: false,
        error_summary: Ai::ErrorText.safe(error.message),
        finished_at: Time.current
      )
    end
    evaluation_execution.refresh_status!
    self
  end

  def recover_stale!(cutoff:, error:)
    recovered = false
    evaluate_child_run = false
    with_lock do
      reload
      next unless running? && started_at && started_at <= cutoff

      child_run = run
      if child_run&.terminal?
        evaluate_child_run = true
        next
      end

      if child_run && !child_run.terminal?
        attempt = child_run.attempts.where(status: %w[queued running]).reorder(sequence: :desc, id: :desc).first
        if child_run.running?
          finished = child_run.finish_running_execution!(
            operation: "structured",
            status: :failed,
            error:,
            summary: { "recovery" => { "automatic_replay" => false, "reason" => error.respond_to?(:code) ? error.code : "worker_interrupted" } },
            started_before: cutoff
          ) do
            attempt&.finish!(status: :failed, finished_at: Time.current, error_class: error.class.name, error_code: error.code, error_message: error.message)
          end
          unless finished
            child_run.reload
            if child_run.terminal?
              evaluate_child_run = true
              next
            end
          end
        else
          attempt&.finish!(status: :failed, finished_at: Time.current, error_class: error.class.name, error_code: error.code, error_message: error.message)
          child_run.fail!(error)
        end
      end

      if child_run&.running?
        next
      elsif child_run&.terminal?
        evaluate_child_run = true
        next
      end

      outcome = Ai::EvaluationCaseOutcome.call(child_run)
      update!(
        transport_status: outcome.transport_status,
        schema_status: outcome.schema_status,
        status: :failed,
        passed: false,
        error_summary: Ai::ErrorText.safe(error.message),
        finished_at: Time.current
      )
      recovered = true
    end

    evaluate_run! if evaluate_child_run && run&.terminal? && running?
    evaluation_execution.refresh_status! if recovered
    recovered
  end

  def mark_submission_unknown!(error)
    with_lock do
      reload
      next unless queued? || running?

      now = Time.current
      update!(
        status: :submission_unknown,
        transport_status: :unknown,
        schema_status: :unknown,
        passed: nil,
        submission_unknown_at: now,
        finished_at: now,
        error_summary: Ai::ErrorText.safe(error.message).to_s.truncate(2_000)
      )
    end
    evaluation_execution.reload
    self
  end

  def close_unknown_submission!(error:)
    closed = false
    begin
      with_lock do
        reload
        next unless submission_unknown?

        child_run = run
        child_run&.reload
        next unless child_run&.running?

        attempt = child_run.attempts.where(status: "running").reorder(sequence: :desc, id: :desc).first
        next unless attempt

        now = Time.current
        finished = child_run.finish_running_execution!(
          operation: "structured",
          status: :failed,
          error:,
          summary: { "automatic_replay" => false, "submission_unknown_closed_manually" => true }
        ) do
          attempt.with_lock do
            raise ConcurrentUnknownSubmissionClose unless attempt.running?

            attempt.finish!(
              status: :failed,
              finished_at: now,
              error_class: error.class.name,
              error_code: Ai::ErrorClassifier.code(error),
              error_message: Ai::ErrorText.safe(error.message).to_s.truncate(2_000)
            )
          end
        end
        next unless finished

        update!(
          transport_status: :unknown,
          schema_status: :unknown,
          status: :failed,
          passed: false,
          error_summary: Ai::ErrorText.safe(error.message).to_s.truncate(2_000),
          finished_at: now
        )
        closed = true
      end
    rescue ConcurrentUnknownSubmissionClose
      false
    end
    closed
  end

  private

  class ConcurrentUnknownSubmissionClose < StandardError; end

  def canonical_json(value)
    case value
    when Hash
      value.deep_stringify_keys.sort.to_h { |key, child| [ key, canonical_json(child) ] }
    when Array
      value.map { |child| canonical_json(child) }
    else
      value
    end
  end

  def freeze_rubric_from_revision
    return unless evaluation_dataset_revision && case_key.present?

    source_case = evaluation_dataset_revision.cases.find { |item| item["key"] == case_key }
    self.rubric_json = source_case&.fetch("rubric", []) || []
  end

  def keep_rubric_immutable
    return unless will_save_change_to_rubric_json?

    errors.add(:rubric_json, "is a frozen copy of the evaluation case rubric.")
    throw :abort
  end
end

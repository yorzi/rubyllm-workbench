class AgentRunDelivery < ApplicationRecord
  CLAIM_DURATION = 5.minutes
  MAX_RETRY_DELAY = 5.minutes

  belongs_to :run
  belongs_to :approval_invocation, class_name: "ToolInvocation", optional: true

  validates :intent, inclusion: { in: %w[execute approval] }
  # The database unique index arbitrates concurrent insert races for
  # create_or_find_by!; a model uniqueness query would reject the lookup path.
  validates :dedupe_key, presence: true
  validates :available_at, presence: true

  scope :ready_to_dispatch, ->(now = Time.current) {
    where(delivered_at: nil)
      .where(available_at: ..now)
      .where("claimed_until IS NULL OR claimed_until <= ?", now)
      .order(:id)
  }

  def self.record!(run:, intent:, approval_invocation_id: nil, expected_generation: nil,
                   available_at: Time.current, dedupe_key: nil)
    key = dedupe_key || default_dedupe_key(run:, intent:, approval_invocation_id:, expected_generation:)
    create_or_find_by!(dedupe_key: key) do |delivery|
      delivery.assign_attributes(
        run:,
        intent:,
        approval_invocation_id:,
        expected_generation:,
        available_at:
      )
    end
  end

  def self.default_dedupe_key(run:, intent:, approval_invocation_id:, expected_generation:)
    [ "agent-run", run.id, intent, approval_invocation_id || "-", expected_generation || "-" ].join(":")
  end
  private_class_method :default_dedupe_key

  def job_arguments
    [ run_id, intent, approval_invocation_id, expected_generation ]
  end

  def claim_for_dispatch!(now: Time.current)
    with_lock do
      reload
      return if delivered_at? || available_at > now || (claimed_until && claimed_until > now)

      token = SecureRandom.uuid
      update!(claim_token: token, claimed_until: now + CLAIM_DURATION)
      token
    end
  end

  def mark_delivered!(token:, now: Time.current)
    with_lock do
      reload
      return false unless claim_token == token && claimed_until && claimed_until > now

      update!(delivered_at: Time.current, claim_token: nil, claimed_until: nil, last_error_class: nil)
    end
    true
  end

  def retry_dispatch!(token:, error:, now: Time.current)
    with_lock do
      reload
      return false unless claim_token == token && claimed_until && claimed_until > now

      next_attempt = dispatch_attempts + 1
      delay_seconds = [ 2**[ next_attempt - 1, 8 ].min, MAX_RETRY_DELAY.to_i ].min
      update!(
        dispatch_attempts: next_attempt,
        available_at: Time.current + delay_seconds.seconds,
        claim_token: nil,
        claimed_until: nil,
        last_error_class: error.class.name
      )
    end
    true
  end
end

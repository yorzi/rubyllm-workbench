class LifecycleEvent < ApplicationRecord
  EVENT_NAMES = %w[
    ai.run.created
    ai.run.started
    ai.run.resumed
    ai.run.waiting_for_approval
    ai.run.succeeded
    ai.run.failed
    ai.run.cancelled
    ai.agent.step
    ai.attempt.started
    ai.attempt.streaming
    ai.attempt.succeeded
    ai.attempt.failed
    ai.attempt.cancelled
    ai.tool.requested
    ai.tool.completed
    ai.approval.requested
    ai.approval.decided
    ai.artifact.created
    ai.provider.chat
    ai.provider.tool
    ai.provider.embedding
    ai.provider.rerank
  ].freeze

  belongs_to :run
  belongs_to :attempt, optional: true
  belongs_to :artifact, optional: true
  belongs_to :tool_invocation, optional: true
  belongs_to :approval, optional: true

  validates :name, presence: true, inclusion: { in: EVENT_NAMES }
  validates :event_key, :source, :occurred_at, presence: true
  validates :event_key, uniqueness: true

  scope :chronological, -> { order(occurred_at: :asc, id: :asc) }

  def payload
    payload_json || {}
  end
end

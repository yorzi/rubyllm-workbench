class ApplicationJob < ActiveJob::Base
  before_perform do
    raise Workbench::DemoMode::DisabledOperation, "Jobs are disabled in the read-only demo." if Workbench::DemoMode.enabled?
  end
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
end

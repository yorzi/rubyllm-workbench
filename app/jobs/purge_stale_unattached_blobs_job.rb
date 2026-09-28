class PurgeStaleUnattachedBlobsJob < ApplicationJob
  queue_as :maintenance

  MAX_UNATTACHED_AGE = 24.hours
  BATCH_SIZE = 100

  def perform(now = Time.current)
    cutoff = now - MAX_UNATTACHED_AGE
    ActiveStorage::Blob.unattached.where(created_at: ..cutoff).find_each(batch_size: BATCH_SIZE) do |blob|
      blob.purge
    end
  end
end

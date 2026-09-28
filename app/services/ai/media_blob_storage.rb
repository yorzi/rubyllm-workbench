module Ai
  class MediaBlobStorage
    def self.upload!(io:, filename:, content_type:)
      key = ActiveStorage::Blob.generate_unique_secure_token

      ActiveStorage::Blob.create_and_upload!(
        key: key,
        io: io,
        filename: filename,
        content_type: content_type,
        identify: false
      )
    rescue StandardError
      purge_if_unattached!(ActiveStorage::Blob.find_by(key: key)) if key
      raise
    end

    def self.purge_if_unattached!(blob)
      return unless blob&.persisted?
      return if blob.attachments.exists?

      blob.purge
    rescue StandardError => error
      Rails.logger.warn("Could not purge unattached media blob #{blob&.id}: #{error.class}")
    end
  end
end

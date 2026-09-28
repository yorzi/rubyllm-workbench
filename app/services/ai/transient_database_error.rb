module Ai
  # Classifies database errors that are worth retrying (lost connections,
  # lock contention) by walking the error's cause chain. Adapter classes are
  # matched by name so no database driver has to be loaded.
  module TransientDatabaseError
    CLASS_NAMES = %w[
      ActiveRecord::ConnectionNotEstablished
      ActiveRecord::ConnectionTimeoutError
      ActiveRecord::ConnectionFailed
      ActiveRecord::Deadlocked
      ActiveRecord::LockWaitTimeout
      SQLite3::BusyException
      SQLite3::LockedException
      PG::ConnectionBad
      PG::UnableToSend
      Mysql2::Error::TimeoutError
    ].freeze

    module_function

    def match?(error)
      current = error
      while current
        return true if CLASS_NAMES.include?(current.class.name)

        current = current.cause
      end
      false
    end
  end
end

require "digest"
require "json"

module Workbench
  # A separately built synthetic snapshot, never the operator's application DB.
  module DemoMode
    class DisabledOperation < StandardError; end

    class QueueAdapter
      def enqueue(_job)
        raise DisabledOperation, "Jobs are disabled in the read-only demo."
      end

      def enqueue_at(job, _timestamp)
        enqueue(job)
      end
    end

    module_function

    def enabled?
      ENV["WORKBENCH_DEMO"] == "1"
    end

    def preparing?
      enabled? && File.expand_path($PROGRAM_NAME) == root.join("bin/demo").to_s && ARGV == [ "prepare" ]
    end

    def root
      Pathname.new(File.expand_path("../..", __dir__))
    end

    def snapshot_path
      root.join("storage/demo/#{Rails.env}.sqlite3")
    end

    def database_path
      preparing? ? snapshot_path.sub_ext(".build-#{Process.pid}.sqlite3") : snapshot_path
    end

    def manifest_path
      snapshot_path.sub_ext(".json")
    end

    def verify_boot!
      raise ArgumentError, "WORKBENCH_DEMO must be 0 or 1." unless [ nil, "", "0", "1" ].include?(ENV["WORKBENCH_DEMO"])
      return unless enabled?

      if ENV.any? { |key, value| (key == "DATABASE_URL" || key.end_with?("_DATABASE_URL")) && !value.to_s.empty? }
        raise ArgumentError, "Remove database URL overrides before starting the isolated demo."
      end
      if ENV["SOLID_QUEUE_IN_PUMA"] && !ENV["SOLID_QUEUE_IN_PUMA"].empty?
        raise ArgumentError, "Remove SOLID_QUEUE_IN_PUMA: the demo never runs workers."
      end
      raise ArgumentError, "Demo storage must not be a symlink." if snapshot_path.dirname.symlink?
      return if preparing?

      manifest = JSON.parse(File.read(manifest_path))
      valid = manifest.is_a?(Hash) && snapshot_path.file? && !snapshot_path.symlink? && !manifest_path.symlink? &&
        manifest["format"] == 1 && manifest["synthetic"] == true &&
        manifest["schema_sha256"] == Digest::SHA256.file(root.join("db/schema.rb")).hexdigest &&
        manifest["database_sha256"] == Digest::SHA256.file(snapshot_path).hexdigest
      raise ArgumentError, "Demo snapshot is stale or invalid; run bin/demo prepare." unless valid
    rescue Errno::ENOENT, JSON::ParserError
      raise ArgumentError, "Demo snapshot is missing; run bin/demo prepare."
    end
  end
end

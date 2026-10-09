#!/usr/bin/env ruby
# Credential-free release smoke for standalone Ruby and Rails runner.
require_relative "deny_provider_http"
require "json"
require "open3"
require "rbconfig"

module WorkbenchCi
  module SourceSmoke
    ROOT = File.expand_path("../..", __dir__)
    SCRIPT = File.expand_path(__FILE__)
    TRANSPORT_GUARD = File.join(ROOT, "script", "ci", "deny_provider_http.rb")

    class << self
      def run!(mode)
        check(ENV["CI"] == "1", "Release smoke requires CI=1 and disposable data.")
        check(%w[prepare records demo-check].include?(mode), "Use prepare, records or demo-check.")
        check(Dir.glob(File.join(ROOT, "config", "**", "*.key")).empty? &&
          Dir.glob(File.join(ROOT, "config", "**", "credentials*.yml.enc")).empty? &&
          Dir.glob(File.join(ROOT, "config", "credentials", "*.yml.enc")).empty?,
          "Release smoke requires a credential-free checkout.")
        ENV["RAILS_ENV"] ||= "production"
        ENV["SECRET_KEY_BASE_DUMMY"] = "1" if ENV["SECRET_KEY_BASE"].to_s.empty?
        require_relative "../../config/environment"
        credential_options = RUBYLLM_CONFIGURATION_ENV.keys.grep(/(?:_api_key|_secret_key|_service_account_key)\z/)
        check(credential_options.all? { |option| RubyLLM.config.public_send(option).blank? }, "Provider credentials must be empty.")
        check_libvips!
        public_send(mode.tr("-", "_"))
        check(ProviderHttpGuard.attempts.zero?, "An outgoing provider request was attempted.")
        puts JSON.generate(smoke: mode, environment: Rails.env, provider_transport_attempts: ProviderHttpGuard.attempts, result: "passed")
      end

      def prepare
        check(!Workbench::DemoMode.enabled?, "Prepare the normal workspace before enabling demo mode.")
        connection = ActiveRecord::Base.connection
        check(!connection.data_source_exists?("projects") || Project.count.zero?, "Refusing to replace existing Projects.")
        Rails.application.load_tasks
        Rake::Task["db:prepare"].invoke
        Message.suppressing_turbo_broadcasts { Workbench::DemoTour.build! }
        imported = Workbench::KnowledgeCaseStudy.import!
        repeated = Workbench::KnowledgeCaseStudy.import!
        check(imported.created_count == 5 && repeated.created_count.zero? && repeated.reused_count == 5,
          "Original five-source import was not idempotent.")
        check(imported.sources.map { |row| row.fetch("item_id") } == repeated.sources.map { |row| row.fetch("item_id") },
          "Repeated import changed source ownership.")
        records
        child_environment = {
          "WORKBENCH_DEMO" => "1", "SOLID_QUEUE_IN_PUMA" => nil,
          "RUBYOPT" => [ ENV["RUBYOPT"], "-r#{TRANSPORT_GUARD}" ].compact.join(" ")
        }
        run_child(child_environment, RbConfig.ruby, File.join(ROOT, "bin", "demo"), "prepare")
        run_child(child_environment, RbConfig.ruby, SCRIPT, "demo-check")
      end

      def records
        check(!Workbench::DemoMode.enabled?, "Persistence check requires the normal workspace.")
        tour = Project.find_by!(slug: "demo-tour")
        case_project = Project.find_by!(slug: "rails-source-case-study")
        check(Project.count == 2 && tour.runs.count == 9 && Run.count == 9, "Synthetic Runs did not persist.")
        check(case_project.knowledge_collections.sum { |collection| collection.knowledge_items.count } == 5,
          "Case-study sources did not persist.")
      end

      def demo_check
        check(Workbench::DemoMode.enabled?, "Read-only check requires WORKBENCH_DEMO=1.")
        check(ActiveRecord::Base.connection_db_config.database == Workbench::DemoMode.snapshot_path.to_s,
          "Demo did not select its isolated snapshot.")
        check(Project.pluck(:slug) == [ "demo-tour" ] && Run.count == 9, "Demo exposed non-synthetic records.")
        check(RUBYLLM_CONFIGURATION_ENV.keys.all? { |option| RubyLLM.config.public_send(option).nil? },
          "Demo provider settings were not cleared.")
        begin
          Project.first.update!(name: "Forbidden smoke mutation")
          raise "Demo database allowed a mutation."
        rescue ActiveRecord::StatementInvalid => error
          raise unless error.cause.is_a?(SQLite3::ReadOnlyException)
        end
        begin
          ActiveJob::Base.queue_adapter.enqueue(ApplicationJob.new)
          raise "Demo allowed job submission."
        rescue Workbench::DemoMode::DisabledOperation
        end
      end

      private

      def check(condition, message)
        raise message unless condition
      end

      def check_libvips!
        expectation = ENV["EXPECT_LIBVIPS"]
        return unless expectation

        check(%w[present absent].include?(expectation), "EXPECT_LIBVIPS must be present or absent.")
        available = begin
          require "vips"
          true
        rescue LoadError
          false
        end
        check(available == (expectation == "present"), "libvips availability did not match the CI case.")
      end

      def run_child(environment, *command)
        output, status = Open3.capture2e(environment, *command, chdir: ROOT)
        puts output
        check(status.success?, "Independent demo process failed.")
      end
    end
  end
end

WorkbenchCi::SourceSmoke.run!(ARGV.first || "prepare") if File.expand_path($PROGRAM_NAME) == File.expand_path(__FILE__)

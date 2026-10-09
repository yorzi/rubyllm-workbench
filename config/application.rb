require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)
require_relative "../lib/workbench/demo_mode"
require_relative "../lib/workbench/demo_gate"

module RubyllmWorkbench
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])
    config.before_configuration { Workbench::DemoMode.verify_boot! }
    config.middleware.insert_before 0, Workbench::DemoGate
    initializer "workbench.demo_runtime", after: :load_environment_config, before: "active_job.set_configs" do
      if Workbench::DemoMode.enabled?
        config.solid_queue.connects_to = nil
        config.active_job.queue_adapter = Workbench::DemoMode::QueueAdapter.new
      end
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "support/workbench_test_helpers"

module ActiveSupport
  class TestCase
    # Keep the default parallel test behavior, while allowing constrained
    # environments and CI jobs to opt into a single process.
    test_workers = ENV["PARALLEL_WORKERS"].presence&.to_i
    parallelize(workers: test_workers&.positive? ? test_workers : :number_of_processors)

    # Tests create only the records they need so RubyLLM's required model
    # registry rows stay explicit and fixture ordering cannot hide lifecycle
    # problems.
  end
end

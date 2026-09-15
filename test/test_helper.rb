ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "support/workbench_test_helpers"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Tests create only the records they need so RubyLLM's required model
    # registry rows stay explicit and fixture ordering cannot hide lifecycle
    # problems.
  end
end

# Loaded before Rails in release smoke processes; never supplies fake responses.
require_relative "../../config/boot"
require "faraday"

module WorkbenchCi
  module ProviderHttpGuard
    class TransportAttempt < StandardError; end

    class << self
      attr_accessor :attempts
    end
    self.attempts = 0

    module DenyHttp
      def run_request(...)
        ProviderHttpGuard.attempts += 1
        raise TransportAttempt, "Release smoke forbids outgoing provider HTTP."
      end
    end
  end
end

Faraday::Connection.prepend(WorkbenchCi::ProviderHttpGuard::DenyHttp)
at_exit do
  abort "Release smoke attempted outgoing provider HTTP." if WorkbenchCi::ProviderHttpGuard.attempts.positive?
end

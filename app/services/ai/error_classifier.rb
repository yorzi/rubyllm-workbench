module Ai
  class ErrorClassifier
    class << self
      def code(error)
        return error.code.to_s if error.respond_to?(:code) && error.code.present?
        return "transport_error" if defined?(Faraday::Error) && error.is_a?(Faraday::Error)
        return "provider_error" if defined?(RubyLLM::Error) && error.is_a?(RubyLLM::Error)

        "application_error"
      end
    end
  end
end

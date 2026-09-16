module Ai
  class ToolPayloadSanitizer
    SENSITIVE_KEY = /key|token|secret|password|authorization|credential|cookie/i
    MAX_STRING_LENGTH = 2_000

    class << self
      def call(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested_value), sanitized|
            sanitized[key.to_s] = sensitive_key?(key) ? "[REDACTED]" : call(nested_value)
          end
        when Array
          value.map { |nested_value| call(nested_value) }
        when String
          value.truncate(MAX_STRING_LENGTH)
        else
          value
        end
      end

      def parse_and_call(value)
        parsed = JSON.parse(value.to_s)
        call(parsed)
      rescue JSON::ParserError
        call(value.to_s)
      end

      private

      def sensitive_key?(key)
        key.to_s.match?(SENSITIVE_KEY)
      end
    end
  end
end

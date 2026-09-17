module Ai
  module ErrorText
    SECRET_PATTERN = /\b(sk|rk|xai|AIza|gsk|pplx|r8)[-_][A-Za-z0-9_-]{12,}\b/i
    DEFAULT_LIMIT = 2_000

    class << self
      def redact(message)
        message.to_s.gsub(SECRET_PATTERN, "[REDACTED]")
      end

      def safe(message, limit: DEFAULT_LIMIT)
        redact(message).truncate(limit)
      end
    end
  end
end

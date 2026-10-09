require "webmock/minitest"

# A test-process boundary, separate from the live suite's model/price guards.
# Block with a safe message before WebMock can print headers or request bodies.
module AiNetworkPolicy
  class ConfigurationError < StandardError; end
  class BlockedRequest < StandardError; end

  def self.configure!(env: ENV)
    profile = env.fetch("AI_TEST_PROFILE", "mock")
    unless %w[mock free integration].include?(profile)
      raise ConfigurationError, "AI_TEST_PROFILE must be mock, free or integration; local inference is not configured."
    end

    live = env["LIVE_DOGFOOD"] == "1"
    if live
      unless env["RUN_LIVE_AI"] == "1" && profile != "mock"
        raise ConfigurationError, "Live tests require RUN_LIVE_AI=1 and an explicit free or integration profile; prefer bin/dogfood."
      end
      paid = env["LIVE_DOGFOOD_PAID"] == "1"
      unless paid == (profile == "integration")
        raise ConfigurationError, "The integration profile requires explicit paid acceptance; free mode must exclude it."
      end
    end

    WebMock.disable_net_connect!(allow_localhost: true, allow: lambda { |uri|
      if live && uri.scheme == "https" && uri.host == "openrouter.ai" && uri.port == 443
        true
      else
        raise BlockedRequest, "External HTTP is blocked by the AI test policy; no request was sent."
      end
    })
  end
end

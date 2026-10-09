require "test_helper"
require "net/http"

class AiNetworkPolicyTest < ActiveSupport::TestCase
  teardown do
    AiNetworkPolicy.configure!
  end

  test "default policy blocks real HTTP and never exposes credentials in its error" do
    AiNetworkPolicy.configure!(env: {})
    request = Net::HTTP::Get.new(URI("https://example.com/private?token=fake-secret"))
    request["Authorization"] = "Bearer fake-secret"

    error = assert_raises(AiNetworkPolicy::BlockedRequest) do
      Net::HTTP.start("example.com", 443, use_ssl: true) { |http| http.request(request) }
    end
    assert_no_match(/fake-secret|Authorization|private/, error.message)
    assert WebMock.net_connect_allowed?("http://127.0.0.1:3100")
  end

  test "live flags fail closed unless the profile and paid authorization agree" do
    [ { "LIVE_DOGFOOD" => "1" },
      live_env.merge("RUN_LIVE_AI" => "true"),
      live_env.merge("AI_TEST_PROFILE" => "mock"),
      live_env.merge("AI_TEST_PROFILE" => "integration"),
      live_env.merge("LIVE_DOGFOOD_PAID" => "1"),
      { "AI_TEST_PROFILE" => "local" } ].each do |env|
      assert_raises(AiNetworkPolicy::ConfigurationError) { AiNetworkPolicy.configure!(env:) }
    end
  end

  test "explicit live mode permits only the official HTTPS host and port" do
    AiNetworkPolicy.configure!(env: live_env)
    assert WebMock.net_connect_allowed?("https://openrouter.ai/api/v1/audio/speech")
    %w[http://openrouter.ai/api/v1/models https://openrouter.ai:8443/api/v1/models
      https://openrouter.ai.example.com/api/v1/models https://api.openai.com/v1/responses].each do |url|
      assert_raises(AiNetworkPolicy::BlockedRequest) { WebMock.net_connect_allowed?(url) }
    end
  end

  test "authorization flags alone do not open the ordinary test process" do
    AiNetworkPolicy.configure!(env: live_env.except("LIVE_DOGFOOD"))
    assert_raises(AiNetworkPolicy::BlockedRequest) { WebMock.net_connect_allowed?("https://openrouter.ai/api/v1/models") }
  end

  private

  def live_env
    { "RUN_LIVE_AI" => "1", "LIVE_DOGFOOD" => "1", "AI_TEST_PROFILE" => "free" }
  end
end

require "test_helper"
require_relative "../../script/diagnostics/support/openrouter_speech_probe"

class OpenRouterSpeechProbeTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :body, :headers) do
    def [](key)
      headers[key]
    end
  end

  setup do
    @catalog = [ {
      "id" => OpenRouterSpeechProbe::DEFAULT_MODEL,
      "architecture" => { "output_modalities" => [ "speech" ] },
      "pricing" => { "prompt" => "0", "completion" => "0", "request" => "0" }
    } ]
    @audio_response = Response.new("200", "ID3\x04fixture-audio".b, { "content-type" => "audio/mpeg", "x-generation-id" => "fixture-generation" })
    @requests = []
    @requester = lambda do |method, path, body, key|
      @requests << { method:, path:, body:, authenticated: !key.nil? }
      method == :get ? Response.new("200", JSON.generate(data: @catalog), {}) : @audio_response
    end
  end

  test "raw probe uses speech catalog and a single exact model POST then reports bounded audio evidence" do
    probe = build_probe
    result = probe.call
    assert_equal 1, probe.post_requests
    assert_equal [ :get, :post ], @requests.map { |request| request.fetch(:method) }
    assert_equal OpenRouterSpeechProbe::CATALOG_PATH, @requests.first.fetch(:path)
    assert_equal false, @requests.first.fetch(:authenticated), "the public catalog must not receive a key"
    request = @requests.last
    assert_equal OpenRouterSpeechProbe::SPEECH_PATH, request.fetch(:path)
    assert_equal true, request.fetch(:authenticated)
    assert_equal({ "model" => OpenRouterSpeechProbe::DEFAULT_MODEL, "input" => OpenRouterSpeechProbe::TEXT, "response_format" => "mp3" }, JSON.parse(request.fetch(:body)))
    assert_equal "fixture-generation", result.evidence.fetch(:generation_id)
    assert_equal "audio/mpeg", result.evidence.fetch(:http_mime_type)
    assert_equal Digest::SHA256.hexdigest(result.data), result.evidence.fetch(:sha256)
    assert_nil result.evidence.fetch(:cost_usd)
    assert_equal false, result.evidence.fetch(:cost_complete), "catalog price is not a provider-reported invoice"
    assert_raises(OpenRouterSpeechProbe::Refused) { probe.call }
    assert_equal 2, @requests.size, "a second invocation must refuse before any HTTP"
  end

  test "nonfree models and missing keys fail before any catalog or generation request" do
    [ { model: "fish-audio/s2.1-pro" }, { model: "openrouter/free" }, { api_key: nil } ].each do |options|
      assert_raises(OpenRouterSpeechProbe::Refused) { build_probe(**options).call }
    end
    assert_empty @requests
  end

  test "missing models output capability and unknown or nonzero prices refuse synthesis" do
    @catalog.first["architecture"]["output_modalities"] = [ "text" ]
    assert_raises(OpenRouterSpeechProbe::Refused) { build_probe.call }
    @catalog.first["architecture"]["output_modalities"] = [ "speech" ]
    [ {}, { "prompt" => "0" }, { "prompt" => "0", "completion" => "0", "request" => "0.01" },
      { "prompt" => "0", "completion" => "unknown" } ].each do |pricing|
      @catalog.first["pricing"] = pricing
      assert_raises(OpenRouterSpeechProbe::Refused) { build_probe.call }
    end
    @catalog.clear
    assert_raises(OpenRouterSpeechProbe::Refused) { build_probe.call }
    assert @requests.all? { |request| request[:method] == :get }
  end

  test "redirects rate limits and provider errors do not retry or fall back" do
    [ "302", "400", "401", "402", "429", "500", "503" ].each do |status|
      @requests.clear
      @audio_response.code = status
      probe = build_probe
      error = assert_raises(OpenRouterSpeechProbe::InvalidResponse) { probe.call }
      assert_includes error.message, "HTTP #{status}"
      assert_equal status.to_i, probe.http_status
      assert_equal 1, probe.post_requests
      assert_equal [ :get, :post ], @requests.map { |request| request.fetch(:method) }
    end
  end

  test "invalid MIME missing audio and disguised JSON responses fail validation" do
    [ [ "text/html", "ID3fixture" ], [ "audio/mpeg", "" ], [ "audio/mpeg", '{"error":"synthetic"}' ],
      [ "audio/mpeg", "ID3" ], [ "audio/mpeg", "ID3" + "x" * OpenRouterSpeechProbe::MAX_AUDIO_BYTES ] ].each do |mime_type, data|
      assert_raises(OpenRouterSpeechProbe::InvalidResponse) { OpenRouterSpeechProbe.validate_mp3!(data:, mime_type:) }
    end
    assert OpenRouterSpeechProbe.validate_mp3!(data: "\xff\xfb\x90\x64frame".b, mime_type: "audio/mpeg")
  end

  test "voice is omitted by default and a deliberate identifier passes through" do
    build_probe(voice: "fixture-voice").call
    assert_equal "fixture-voice", JSON.parse(@requests.last.fetch(:body)).fetch("voice")
  end

  private

  def build_probe(api_key: "unused-offline-key", model: OpenRouterSpeechProbe::DEFAULT_MODEL, voice: nil)
    OpenRouterSpeechProbe.new(api_key:, model:, voice:, requester: @requester)
  end
end

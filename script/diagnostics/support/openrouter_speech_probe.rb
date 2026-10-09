require "bigdecimal"
require "digest"
require "json"
require "net/http"

# Raw REST probe, independent of RubyLLM's adapter. Only the public speech
# catalog and one exact, zero-priced model are eligible; no retries/fallback.
class OpenRouterSpeechProbe
  class Refused < StandardError; end
  class InvalidResponse < StandardError; end

  DEFAULT_MODEL = "fish-audio/s2.1-pro-free:free".freeze
  TEXT = "Workbench audio check.".freeze
  BASE_URL = "https://openrouter.ai".freeze
  CATALOG_PATH = "/api/v1/models?output_modalities=speech".freeze
  SPEECH_PATH = "/api/v1/audio/speech".freeze
  MAX_AUDIO_BYTES = 1_048_576
  Result = Data.define(:data, :status, :mime_type, :generation_id, :model) do
    def evidence
      { model:, http_status: status, http_mime_type: mime_type, generation_id:,
        format: "mp3", byte_size: data.bytesize, sha256: Digest::SHA256.hexdigest(data),
        file_header: "mp3_signature", price_check: "current_catalog_all_zero",
        cost_usd: nil, cost_complete: false }
    end
  end

  attr_reader :post_requests, :http_status, :generation_id

  def initialize(api_key:, model: DEFAULT_MODEL, voice: nil, requester: nil)
    @api_key = api_key
    @model = model.to_s
    @voice = voice.to_s.strip
    @requester = requester || method(:request)
    @post_requests = 0
  end

  def call
    raise Refused, "An explicit :free speech model is required." unless @model.end_with?(":free")
    raise Refused, "OpenRouter API key is not configured." if @api_key.to_s.empty?
    raise Refused, "This probe permits one synthesis request only." unless @post_requests.zero?
    verify_catalog!

    payload = { model: @model, input: TEXT, response_format: "mp3" }
    payload[:voice] = @voice unless @voice.empty?
    @post_requests += 1
    response = @requester.call(:post, SPEECH_PATH, JSON.generate(payload), @api_key)
    @http_status = response.code.to_i
    @generation_id = response["x-generation-id"]
    raise InvalidResponse, "OpenRouter speech returned HTTP #{@http_status}; no retry or fallback was attempted." unless @http_status == 200

    mime_type = response["content-type"].to_s.split(";", 2).first
    data = response.body.to_s.b
    self.class.validate_mp3!(data:, mime_type:)
    Result.new(data:, status: @http_status, mime_type:, generation_id: @generation_id, model: @model)
  end

  def self.validate_mp3!(data:, mime_type:)
    raise InvalidResponse, "Expected an audio/mpeg response." unless mime_type == "audio/mpeg"
    raise InvalidResponse, "Audio is empty or exceeds the probe size limit." unless data.bytesize.between?(4, MAX_AUDIO_BYTES)
    frame_header = data.getbyte(0) == 0xff && (data.getbyte(1) & 0xe0) == 0xe0
    raise InvalidResponse, "Audio does not have an ID3 or MP3 frame header." unless data.start_with?("ID3") || frame_header
    true
  end

  private

  def verify_catalog!
    response = @requester.call(:get, CATALOG_PATH, nil, nil)
    raise Refused, "OpenRouter speech catalog could not be checked." unless response.code.to_i == 200
    entry = JSON.parse(response.body).fetch("data").find { |model| model["id"] == @model }
    raise Refused, "The selected model is absent from the current speech catalog." unless entry
    unless Array(entry.dig("architecture", "output_modalities")).include?("speech")
      raise Refused, "The selected model does not declare speech output."
    end
    prices = entry.fetch("pricing", {})
    unless prices.key?("prompt") && prices.key?("completion") && prices.values.all? { |value| zero_price?(value) }
      raise Refused, "The selected model has nonzero or unknown prices."
    end
  rescue JSON::ParserError, KeyError
    raise Refused, "OpenRouter speech catalog was malformed."
  end

  def zero_price?(value)
    BigDecimal(value.to_s).zero?
  rescue ArgumentError
    false
  end

  def request(method, path, body, api_key)
    uri = URI("#{BASE_URL}#{path}")
    request = method == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
    if body
      request["Authorization"] = "Bearer #{api_key}"
      request["Content-Type"] = "application/json"
      request.body = body
    end
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 60, max_retries: 0) do |http|
      http.request(request)
    end
  end
end

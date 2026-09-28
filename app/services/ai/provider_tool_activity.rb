module Ai
  # Extracts evidence of provider-hosted tool use (such as web_search) from a
  # RubyLLM response. Providers report it in two ways:
  #
  # - discrete server tool call blocks (`response.server_tool_calls`), and
  # - usage counters only (`response.tokens.server_tool_use`), which is how
  #   OpenRouter reports its transparently executed server tools.
  #
  # Both are recorded so a Run that searched is never summarized as if it had
  # not. Counters are provider-reported and not normalized across providers.
  module ProviderToolActivity
    MAX_COUNTER_KEYS = 20

    module_function

    def calls(response)
      return [] unless response.respond_to?(:server_tool_calls)

      Array(response.server_tool_calls).filter_map do |call|
        data = call.respond_to?(:to_h) ? call.to_h : call
        next unless data.is_a?(Hash)

        record = {
          "type" => data[:type] || data["type"],
          "name" => data[:name] || data["name"],
          "id" => data[:id] || data["id"],
          "input" => Ai::ToolPayloadSanitizer.call(data[:input] || data["input"])
        }.compact
        record if record.any?
      end
    end

    def usage(response)
      tokens = response.respond_to?(:tokens) ? response.tokens : nil
      counters = tokens.respond_to?(:server_tool_use) ? tokens.server_tool_use : nil
      return {} unless counters.is_a?(Hash)

      counters.first(MAX_COUNTER_KEYS).each_with_object({}) do |(key, value), result|
        count = Integer(value, exception: false)
        result[key.to_s.truncate(60)] = count if count&.positive?
      end
    end

    def merge_usage(existing, addition)
      existing.to_h.merge(addition.to_h) { |_key, left, right| left.to_i + right.to_i }
    end
  end
end

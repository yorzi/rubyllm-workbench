# Workaround for RubyLLM 2.0.0: OpenRouter's streaming `build_chunk` override
# drops the `citations:` and `server_tool_use:` fields that the generic Chat
# Completions stream parser maps. Workbench streams every Chat and Agent step,
# so without this, OpenRouter hosted web search leaves no citations and no
# usage evidence. Reproduce with
# `bundle exec ruby script/diagnostics/ruby_llm_openrouter_stream_citations.rb`.
#
# The patch installs itself only while a probe shows the upstream parser still
# drops the evidence, so an upstream fix makes it a no-op. An upstream fix with
# specs is prepared but not yet filed. Remove this file and its require once a
# RubyLLM release containing the fix is pinned.
module RubyLLMWorkarounds
  module OpenRouterStreamEvidence
    PROBE_EVENT = {
      "choices" => [ { "delta" => { "annotations" => [
        { "type" => "url_citation", "url_citation" => { "url" => "https://example.com", "title" => "probe" } }
      ] } } ]
    }.freeze

    module ChunkEvidence
      private

      def build_chunk(data)
        chunk = super
        delta = data.dig("choices", 0, "delta") || {}
        citations = extract_chunk_citations(delta, data)
        usage = data["usage"].is_a?(Hash) ? server_tool_use(data["usage"]) : nil

        chunk.instance_variable_set(:@citations, citations) if chunk.citations.empty? && citations.any?
        if usage && chunk.tokens && chunk.tokens.server_tool_use.nil?
          tokens = chunk.tokens
          chunk.instance_variable_set(:@tokens, RubyLLM::Tokens.new(
            input: tokens.input, output: tokens.output, cache_read: tokens.cache_read,
            cache_write: tokens.cache_write, thinking: tokens.thinking,
            server_tool_use: usage, reported_cost: tokens.reported_cost
          ))
        end
        chunk
      end
    end

    module_function

    def install!
      return :not_needed unless needed?

      RubyLLM::Providers::OpenRouter::ChatCompletions.prepend(ChunkEvidence)
      :installed
    end

    def installed?
      RubyLLM::Providers::OpenRouter::ChatCompletions.ancestors.include?(ChunkEvidence)
    end

    # True while RubyLLM's OpenRouter stream parser still drops citations.
    def needed?
      return false if installed?

      protocol = RubyLLM::Providers::OpenRouter::ChatCompletions.allocate
      protocol.send(:build_chunk, PROBE_EVENT).citations.empty?
    end
  end
end

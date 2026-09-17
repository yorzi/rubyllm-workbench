# Deterministic embedding double for knowledge tests.
#
# It builds a term-count vector over a fixed vocabulary, so cosine similarity
# has an explainable ordering that tests can assert without a provider call.
class FakeEmbeddingClient
  VOCABULARY = %w[sqlite retrieval embedding provider chunk evidence].freeze

  attr_reader :calls

  def initialize(error: nil, failing_texts: [])
    @error = error
    @failing_texts = Array(failing_texts)
    @calls = []
  end

  def embed(text, model:, provider: nil, **)
    @calls << { text: text, model: model, provider: provider }
    raise @error if @error

    texts = text.is_a?(Array) ? text : [ text ]
    texts.each do |value|
      raise StandardError, "provider rejected chunk" if @failing_texts.any? { |needle| value.to_s.include?(needle) }
    end

    vectors = texts.map { |value| vector_for(value) }
    RubyLLM::Embedding.new(
      vectors: text.is_a?(Array) ? vectors : vectors.first,
      model: model,
      input_tokens: texts.sum { |value| value.to_s.length }
    )
  end

  def vector_for(text)
    downcased = text.to_s.downcase
    VOCABULARY.map { |term| downcased.scan(term).length.to_f }
  end
end

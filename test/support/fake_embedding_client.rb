# Deterministic double for the RubyLLM knowledge boundary (embed + rerank).
#
# It builds a term-count vector over a fixed vocabulary, so cosine similarity
# has an explainable ordering that tests can assert without a provider call.
# Rerank scoring is deterministic too: documents are ordered by how many query
# terms they contain, then by input order, so a reorder is observable.
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

  def rerank(query, documents, model:, provider: nil, top_n: nil, **)
    @calls << { query: query, documents: documents, model: model, provider: provider }
    raise @error if @error

    terms = VOCABULARY.select { |term| query.to_s.downcase.include?(term) }
    scored = Array(documents).each_with_index.map do |document, index|
      downcased = document.to_s.downcase
      [ index, terms.sum { |term| downcased.scan(term).length }.to_f ]
    end
    scored = scored.sort_by { |index, score| [ -score, index ] }
    scored = scored.first(top_n.to_i) if top_n.present?
    scored = scored.map { |index, score| [ index, score ] }

    Struct.new(:results, :model, :raw, keyword_init: true).new(
      results: scored.map { |index, score| RerankRow.new(index: index, score: score) },
      model: model,
      raw: nil
    )
  end

  RerankRow = Struct.new(:index, :score, :document, keyword_init: true)

  def vector_for(text)
    downcased = text.to_s.downcase
    VOCABULARY.map { |term| downcased.scan(term).length.to_f }
  end
end

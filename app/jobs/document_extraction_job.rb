class DocumentExtractionJob < ApplicationJob
  queue_as :default

  def perform(knowledge_item_id)
    item = KnowledgeItem.find_by(id: knowledge_item_id)
    return if item.nil?

    Ai::Knowledge::DocumentIngestor.call(item)
  rescue Ai::Knowledge::DocumentIngestor::Error, Ai::Knowledge::Extractor::Unsupported => error
    Rails.logger.warn("Document extraction failed for item #{knowledge_item_id}: #{error.class}: #{error.message}")
  end
end

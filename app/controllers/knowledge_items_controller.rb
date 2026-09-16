class KnowledgeItemsController < ApplicationController
  before_action :set_project
  before_action :set_collection

  def create
    @item = @collection.knowledge_items.new(item_params.merge(source_kind: "text"))
    @item.save!
    Ai::Knowledge::Ingestor.call(@item)

    redirect_to project_knowledge_collection_path(@project, @collection),
      notice: "Source ingested into #{@item.knowledge_chunks.count} searchable chunks.",
      status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    redirect_to project_knowledge_collection_path(@project, @collection),
      alert: error.record.errors.full_messages.to_sentence
  rescue Ai::Knowledge::Ingestor::Error => error
    redirect_to project_knowledge_collection_path(@project, @collection), alert: error.message
  end

  private

  def set_project
    @project = Project.find_by!(slug: params[:project_id])
  end

  def set_collection
    @collection = @project.knowledge_collections.find(params[:knowledge_collection_id])
  end

  def item_params
    params.expect(knowledge_item: [ :title, :source_reference, :content_text ])
  end
end

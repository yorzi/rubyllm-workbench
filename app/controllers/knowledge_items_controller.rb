class KnowledgeItemsController < ApplicationController
  before_action :set_project
  before_action :set_collection

  def create
    if file_upload?
      create_file_source
    else
      create_text_source
    end
  end

  private

  def create_text_source
    @item = @collection.knowledge_items.new(item_params.merge(source_kind: "text"))
    @item.save!
    Ai::Knowledge::Ingestor.call(@item)

    redirect_to project_knowledge_collection_path(@project, @collection),
      notice: "Source ingested into #{@item.knowledge_chunks.count} searchable chunks.",
      status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    redirect_with_errors(error)
  rescue Ai::Knowledge::Ingestor::Error => error
    redirect_to project_knowledge_collection_path(@project, @collection), alert: error.message
  end

  def create_file_source
    @item = @collection.knowledge_items.new(source_kind: "file", title: file_title, source_reference: filename)
    @item.document.attach(document_params[:document])
    @item.save!
    DocumentExtractionJob.perform_later(@item.id)

    redirect_to project_knowledge_collection_path(@project, @collection),
      notice: "Uploaded #{filename}; extraction is running in the background.",
      status: :see_other
  rescue ActiveRecord::RecordInvalid => error
    redirect_with_errors(error)
  end

  def file_upload?
    document_params[:document].present?
  end

  def document_params
    params.fetch(:knowledge_item, {}).permit(:document)
  end

  def item_params
    params.expect(knowledge_item: [ :title, :source_reference, :content_text ])
  end

  def filename
    document_params[:document].original_filename.to_s
  end

  def file_title
    params.dig(:knowledge_item, :title).presence || filename
  end

  def redirect_with_errors(error)
    redirect_to project_knowledge_collection_path(@project, @collection),
      alert: error.record.errors.full_messages.to_sentence
  end

  def set_project
    @project = Project.find_by!(slug: params[:project_id])
  end

  def set_collection
    @collection = @project.knowledge_collections.find(params[:knowledge_collection_id])
  end
end

class KnowledgeEmbeddingsController < ApplicationController
  before_action :set_project
  before_action :set_collection

  def create
    model_id = params.expect(embedding: [ :model_id ]).fetch(:model_id)
    summary = Ai::Knowledge::Embedder.call(collection: @collection, model_id: model_id)

    redirect_to project_knowledge_collection_path(@project, @collection),
      notice: "Embedded #{summary.embedded} chunk(s) with #{summary.model_id} (#{summary.dimensions} dimensions).",
      status: :see_other
  rescue ActionController::ParameterMissing, Ai::Knowledge::Embedder::Error => error
    redirect_to project_knowledge_collection_path(@project, @collection), alert: error.message
  end

  def destroy
    cleared = KnowledgeEmbedding.where(knowledge_chunk_id: @collection.knowledge_chunks.select(:id)).delete_all
    @collection.update!(
      embedding_model_id: nil,
      embedding_provider: nil,
      embedding_dimensions: nil,
      embedding_status: "none",
      embedding_error: nil,
      embedded_at: nil
    )

    redirect_to project_knowledge_collection_path(@project, @collection),
      notice: "Cleared #{cleared} stored embedding(s). Lexical retrieval remains available.",
      status: :see_other
  end

  private

  def set_project
    @project = Project.find_by!(slug: params[:project_id])
  end

  def set_collection
    @collection = @project.knowledge_collections.find(params[:knowledge_collection_id])
  end
end

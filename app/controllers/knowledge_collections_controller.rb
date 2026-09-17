class KnowledgeCollectionsController < ApplicationController
  before_action :set_project
  before_action :set_collection, only: :show

  def index
    @collections = @project.knowledge_collections.recent
    @collection = @project.knowledge_collections.new
  end

  def create
    @collection = @project.knowledge_collections.new(collection_params)

    if @collection.save
      redirect_to project_knowledge_collection_path(@project, @collection), status: :see_other
    else
      @collections = @project.knowledge_collections.recent
      render :index, status: :unprocessable_entity
    end
  end

  def show
    @items = @collection.knowledge_items.order(created_at: :desc, id: :desc)
    @query = params[:q].to_s.strip.truncate(500)
    @mode = Ai::Knowledge::Search::MODES.include?(params[:mode].to_s) ? params[:mode].to_s : "lexical"
    @embedding_models = Ai::Knowledge::EmbeddingCatalog.configured_entries
    @rerank_models = Ai::Knowledge::RerankCatalog.configured_entries
    @rerank_model_id = params[:rerank_model_id].to_s.truncate(200).presence
    @rerank = params[:rerank].to_s.in?(%w[1 true])
    @adapter_selection = Ai::Knowledge::VectorStore.selection
    @outcome = @query.present? ? Ai::Knowledge::Search.call(
      collection: @collection,
      query: @query,
      mode: @mode,
      rerank: @rerank,
      rerank_model_id: @rerank_model_id
    ) : nil
    @results = @outcome&.results || []
  end

  private

  def set_project
    @project = Project.find_by!(slug: params[:project_id])
  end

  def set_collection
    @collection = @project.knowledge_collections.find(params[:id])
  end

  def collection_params
    params.expect(knowledge_collection: [ :name, :description ])
  end
end

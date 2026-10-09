class ModelsController < ApplicationController
  def index
    @projects = visible_projects.order(:name)
    @selected_project = selected_project
    @models = model_catalog.entries(
      query: params[:q],
      provider: params[:provider],
      capability: params[:capability],
      configured: params[:configured]
    )
    @model_count = @models.size
    @models = @models.first(180)
    @providers = model_catalog.providers
  end

  private

  def selected_project
    return @projects.first if params[:project_id].blank?

    @projects.find_by(slug: params[:project_id]) || @projects.first
  end
end

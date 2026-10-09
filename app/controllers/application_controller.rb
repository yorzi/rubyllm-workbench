class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  prepend_before_action :restrict_demo_records
  before_action :load_sidebar_projects

  helper_method :model_catalog, :ruby_llm_version, :workbench_app_version, :demo_mode?

  private

  def load_sidebar_projects
    @sidebar_projects = visible_projects.order(:name)
  end

  def demo_mode?
    Workbench::DemoMode.enabled?
  end

  def visible_projects
    demo_mode? ? Project.where(slug: Workbench::DemoTour::PROJECT_SLUG) : Project.all
  end

  def visible_runs
    demo_mode? ? Run.where(project: visible_projects, requested_by: "demo", app_version: "demo") : Run.all
  end

  def restrict_demo_records
    return unless demo_mode?

    project_slug = params[:project_id] || (params[:id] if controller_name == "projects" && action_name == "show")
    raise ActiveRecord::RecordNotFound if project_slug && project_slug != Workbench::DemoTour::PROJECT_SLUG
    visible_runs.find(params[:id]) if controller_name == "runs" && action_name != "index"
  end

  def model_catalog
    @model_catalog ||= Ai::ModelCatalog.new
  end

  def ruby_llm_version
    Gem.loaded_specs.fetch("ruby_llm").version.to_s
  end

  def workbench_app_version
    ENV.fetch("APP_VERSION", "local")
  end
end

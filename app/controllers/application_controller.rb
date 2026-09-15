class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  before_action :load_sidebar_projects

  helper_method :model_catalog, :ruby_llm_version, :workbench_app_version

  private

  def load_sidebar_projects
    @sidebar_projects = Project.order(:name)
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

class ExperimentExecutionsController < ApplicationController
  before_action :set_project
  before_action :set_experiment

  def create
    targets = selected_targets
    if targets.size < 2
      redirect_to project_experiment_path(@project, @experiment), alert: "Choose at least two configured structured-output models."
      return
    end

    execution = Ai::ExperimentExecutor.enqueue(experiment: @experiment, targets: targets)
    redirect_to project_experiment_path(@project, @experiment), notice: "Experiment execution ##{execution.id} queued.", status: :see_other
  rescue ArgumentError => error
    redirect_to project_experiment_path(@project, @experiment), alert: error.message
  end

  private

  def set_project
    @project = Project.find_by!(slug: params[:project_id])
  end

  def set_experiment
    @experiment = @project.experiments.find(params[:experiment_id])
  end

  def selected_targets
    raw_models = params.require(:execution).permit(models: []).fetch(:models, [])
    raw_models.filter_map do |value|
      provider, model_id = value.to_s.split("|", 2)
      next if provider.blank? || model_id.blank?

      { provider: provider, model_id: model_id }
    end.uniq
  end
end

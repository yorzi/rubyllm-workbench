class EvaluationCaseAttachmentsController < ApplicationController
  before_action :set_project
  before_action :set_dataset

  def show
    revision = @dataset.evaluation_dataset_revisions.find(params[:revision_id])
    attachment = revision.case_attachments.includes(file_attachment: :blob).find(params[:attachment_id])

    send_data attachment.file.download,
      filename: attachment.file.filename.to_s,
      type: "application/octet-stream",
      disposition: "attachment"
  end

  def create
    revision = @dataset.current_revision_record
    raise ActiveRecord::RecordNotFound unless revision

    raw_attachment_params = params.require(:evaluation_case_attachment)
    case_key = raw_attachment_params[:case_key].to_s
    files = Array(raw_attachment_params[:files]).compact
    raise ArgumentError, "Choose one or more files to attach." if files.empty?

    @dataset.create_revision!(
      revision.cases,
      uploads_by_case_key: { case_key => files },
      base_revision_id: revision.id
    )
    redirect_to project_evaluation_dataset_path(@project, @dataset),
      notice: "Case files saved in immutable revision #{@dataset.reload.current_revision}.", status: :see_other
  rescue ActiveRecord::RecordInvalid, ArgumentError, ActiveRecord::RecordNotFound => error
    redirect_to project_evaluation_dataset_path(@project, @dataset), alert: error.message, status: :see_other
  end

  def destroy
    revision = @dataset.current_revision_record
    raise ActiveRecord::RecordNotFound unless revision

    attachment = revision.case_attachments.find(params[:id])
    @dataset.create_revision!(revision.cases, removed_attachment_ids: [ attachment.id ], base_revision_id: revision.id)
    redirect_to project_evaluation_dataset_path(@project, @dataset),
      notice: "Case file removed from the new immutable revision #{@dataset.reload.current_revision}; prior revisions retain it.", status: :see_other
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => error
    redirect_to project_evaluation_dataset_path(@project, @dataset), alert: error.message, status: :see_other
  end

  private

  def set_project
    @project = Project.find_by!(slug: params[:project_id])
  end

  def set_dataset
    @dataset = @project.evaluation_datasets.find(params[:evaluation_dataset_id])
  end
end

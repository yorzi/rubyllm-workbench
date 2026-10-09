class KnowledgeAnswersController < ApplicationController
  def create
    project = Project.find_by!(slug: params[:project_id])
    collection = project.knowledge_collections.find(params[:knowledge_collection_id])
    attributes = params.expect(knowledge_answer: [ :question, :model_reference ])
    run = Ai::Knowledge::GroundedAnswer.enqueue(
      collection:, question: attributes[:question], model_reference: attributes[:model_reference], model_catalog:
    )
    redirect_to run_path(run), status: :see_other
  rescue ArgumentError, Ai::Knowledge::EvidenceSnapshot::StaleEvidence => error
    redirect_to project_knowledge_collection_path(project, collection), alert: error.message, status: :see_other
  end
end

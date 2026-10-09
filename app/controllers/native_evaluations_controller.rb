class NativeEvaluationsController < ApplicationController
  def create
    answer_run = Run.find(params[:id])
    attributes = params.expect(native_evaluation: [ :case_key, :evaluator_kind, :model_reference ])
    run = Ai::Knowledge::NativeEvaluation.enqueue(answer_run:, case_key: attributes[:case_key],
      evaluator_kind: attributes[:evaluator_kind].presence || "assertions", model_reference: attributes[:model_reference])
    redirect_to run_path(run), status: :see_other
  rescue ArgumentError, Ai::StructuredOutputError => error
    redirect_to run_path(answer_run), alert: Ai::ErrorText.safe(error.message), status: :see_other
  end
end

class LearningTopicsController < ApplicationController
  def show
    @topic = Learning::TopicRegistry.fetch!(params[:id])
    @snippets = @topic.code_references.map { |reference| Learning::SourceReader.new(reference).read }
    @return_to = safe_return_to

    if turbo_frame_request?
      render partial: "learning_topics/panel",
        locals: { frame: true, topic: @topic, snippets: @snippets, return_to: @return_to }
    end
  rescue KeyError => error
    raise ActiveRecord::RecordNotFound, error.message
  end

  private

  def safe_return_to
    candidate = params[:return_to].to_s
    return root_path if candidate.blank?
    return root_path unless candidate.start_with?("/")
    return root_path if candidate.start_with?("//")

    candidate
  end
end

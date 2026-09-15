class RunsController < ApplicationController
  def show
    @run = Run.includes(:project, :chat, :attempts).find(params[:id])
    @messages = @run.chat.messages
    @latest_assistant_message = @messages.reverse.find { |message| message.role.to_s == "assistant" }
  end
end

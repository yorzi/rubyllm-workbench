module Workbench
  # Runs before Rails parses a request body or dispatches engine routes.
  class DemoGate
    READ_ACTIONS = {
      "projects" => %w[index show], "models" => %w[index],
      "learning_topics" => %w[show], "chats" => %w[show],
      "tool_definitions" => %w[index], "agent_definitions" => %w[index show],
      "knowledge_collections" => %w[index show], "experiments" => %w[index show],
      "evaluation_datasets" => %w[index show], "runs" => %w[index show reproduction events],
      "rails/health" => %w[show]
    }.freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      return @app.call(env) unless DemoMode.enabled?
      return denied unless %w[GET HEAD].include?(env["REQUEST_METHOD"])
      return denied unless allowed_path?(env["PATH_INFO"])

      status, headers, body = @app.call(env)
      headers["cache-control"] = "no-store"
      [ status, headers, body ]
    end

    def self.allowed_path?(path)
      return false if path.to_s.split("/").any? { |segment| segment == ".." || segment == "." } || path.to_s.include?("%")
      return true if path.match?(%r{\A/(?:assets|vite|vite-test)/[a-zA-Z0-9_./-]+\z})
      return true if %w[/icon.png /icon.svg /favicon.ico].include?(path)

      route = Rails.application.routes.recognize_path(path, method: :get)
      READ_ACTIONS.fetch(route[:controller], []).include?(route[:action])
    rescue ActionController::RoutingError
      false
    end

    private

    def allowed_path?(path)
      self.class.allowed_path?(path)
    end

    def denied
      [ 403, { "content-type" => "text/plain; charset=utf-8", "cache-control" => "no-store" },
        [ "This synthetic demo is read-only. Browse the recorded examples; execution and uploads are disabled.\n" ] ]
    end
  end
end

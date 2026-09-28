module Ai
  class AgentRunExecutor
    def self.enqueue(agent_definition:, prompt:, requested_by: "local_user")
      new(agent_definition:, prompt:, requested_by:).enqueue
    end

    def initialize(agent_definition:, prompt:, requested_by:)
      @agent_definition = agent_definition
      @prompt = prompt.to_s.strip
      @requested_by = requested_by
    end

    def enqueue
      raise ArgumentError, "Enter a task for the Agent." if @prompt.blank?

      snapshot = @agent_definition.snapshot
      project = @agent_definition.project
      model = configured_model!(snapshot)
      available_tools = Ai::ChatTooling.snapshot(project)
      selected_tools = available_tools.select { |tool| snapshot.fetch("tool_keys").include?(tool.fetch("key")) }
      missing_tools = snapshot.fetch("tool_keys") - selected_tools.map { |tool| tool.fetch("key") }
      raise ArgumentError, "Selected tools are no longer available: #{missing_tools.join(', ')}" if missing_tools.any?

      run = project.transaction do
        chat_title = "#{snapshot.fetch('name').truncate(144)} · Agent run"
        chat = project.chats.new(title: chat_title, model: model)
        chat.save!

        run = chat.runs.create!(
          project: project,
          operation: "agent",
          status: :queued,
          requested_by: @requested_by,
          input_snapshot_json: {
            "prompt" => @prompt,
            "agent_definition" => snapshot,
            "tools" => selected_tools,
            "tool_options" => Ai::ToolExecutionPolicy.snapshot(project:, chat:),
            "provider_tools" => snapshot.fetch("provider_tools")
          },
          app_version: ENV.fetch("APP_VERSION", "local"),
          ruby_llm_version: Gem.loaded_specs.fetch("ruby_llm").version.to_s
        )
        run.attempts.create!(
          sequence: 1,
          provider: snapshot.fetch("provider"),
          model_id: snapshot.fetch("model_id"),
          status: :queued
        )
        AgentRunDelivery.record!(run:, intent: "execute", expected_generation: 0)
        run
      end

      run
    end

    private

    def configured_model!(snapshot)
      catalog = Ai::ModelCatalog.new
      Ai::AgentModelEligibility.new(catalog:).ensure_eligible!(
        provider: snapshot.fetch("provider"),
        model_id: snapshot.fetch("model_id"),
        tool_keys: snapshot.fetch("tool_keys")
      )
      entry = catalog.find_entry(snapshot.fetch("model_id"), provider: snapshot.fetch("provider"))
      unless entry&.configured
        missing = entry&.missing_configuration&.join(", ").presence || "provider configuration"
        raise ArgumentError, "This Agent model is not runnable yet. Configure #{missing} first."
      end

      catalog.find!(snapshot.fetch("model_id"), provider: snapshot.fetch("provider"))
    end
  end
end

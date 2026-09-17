module WorkbenchTestHelpers
  def chat_model
    @chat_model ||= RubyLLM.models.chat_models.first
  end

  def ensure_chat_model_record
    RubyLLM::ActiveRecord::Model.find_or_create_by!(model_id: chat_model.id, provider: chat_model.provider) do |record|
      record.assign_attributes(
        name: chat_model.name,
        family: chat_model.family,
        model_created_at: chat_model.created_at,
        context_window: chat_model.context_window,
        max_output_tokens: chat_model.max_output_tokens,
        knowledge_cutoff: chat_model.knowledge_cutoff,
        modalities: chat_model.modalities.to_h,
        capabilities: chat_model.capabilities,
        pricing: chat_model.pricing.to_h,
        metadata: chat_model.metadata
      )
    end
  end

  def create_project(name: "Test project")
    Project.create!(name: name)
  end

  def create_chat(project)
    ensure_chat_model_record
    Chat.create!(project: project, model_id: chat_model.id, provider: chat_model.provider)
  end

  def with_configured_provider(chat)
    with_provider_configuration(chat.provider) { yield }
  end

  # Routes every RubyLLM.embed call through a deterministic double for the
  # duration of the block. Knowledge services take `client:` explicitly, so
  # only the default global boundary needs redirecting here.
  def with_embedding_client(client)
    original = RubyLLM.method(:embed)
    RubyLLM.define_singleton_method(:embed) { |text, **options| client.embed(text, **options) }
    yield
  ensure
    RubyLLM.define_singleton_method(:embed, original)
  end

  def with_provider_configuration(provider, value: "test-only-key")
    provider_class = RubyLLM::Provider.resolve(provider)
    requirements = provider_class.configuration_requirements
    previous_values = requirements.to_h { |requirement| [ requirement, RubyLLM.config.public_send(requirement) ] }
    requirements.each { |requirement| RubyLLM.config.public_send("#{requirement}=", value) }
    yield
  ensure
    previous_values&.each { |requirement, value| RubyLLM.config.public_send("#{requirement}=", value) }
  end
end

ActiveSupport::TestCase.include(WorkbenchTestHelpers)
ActionDispatch::IntegrationTest.include(WorkbenchTestHelpers)

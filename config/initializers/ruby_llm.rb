RUBYLLM_CONFIGURATION_ENV = {
  anthropic_api_key: "ANTHROPIC_API_KEY",
  azure_api_base: "AZURE_API_BASE",
  azure_api_key: "AZURE_API_KEY",
  bedrock_api_key: "BEDROCK_API_KEY",
  bedrock_secret_key: "BEDROCK_SECRET_KEY",
  bedrock_region: "BEDROCK_REGION",
  cohere_api_key: "COHERE_API_KEY",
  deepgram_api_key: "DEEPGRAM_API_KEY",
  deepseek_api_key: "DEEPSEEK_API_KEY",
  elevenlabs_api_key: "ELEVENLABS_API_KEY",
  gemini_api_key: "GEMINI_API_KEY",
  gpustack_api_base: "GPUSTACK_API_BASE",
  gpustack_api_key: "GPUSTACK_API_KEY",
  hetzner_api_key: "HETZNER_API_KEY",
  mistral_api_key: "MISTRAL_API_KEY",
  ollama_api_base: "OLLAMA_API_BASE",
  ollama_api_key: "OLLAMA_API_KEY",
  ollama_cloud_api_key: "OLLAMA_CLOUD_API_KEY",
  ollama_cloud_api_base: "OLLAMA_CLOUD_API_BASE",
  openai_api_key: "OPENAI_API_KEY",
  openai_api_base: "OPENAI_API_BASE",
  openai_organization_id: "OPENAI_ORGANIZATION_ID",
  openai_project_id: "OPENAI_PROJECT_ID",
  openrouter_api_key: "OPENROUTER_API_KEY",
  openrouter_api_base: "OPENROUTER_API_BASE",
  openrouter_app_url: "OPENROUTER_APP_URL",
  openrouter_app_name: "OPENROUTER_APP_NAME",
  perplexity_api_key: "PERPLEXITY_API_KEY",
  typesafe_api_key: "TYPESAFE_API_KEY",
  vertexai_project_id: "VERTEXAI_PROJECT_ID",
  vertexai_location: "VERTEXAI_LOCATION",
  vertexai_service_account_key: "VERTEXAI_SERVICE_ACCOUNT_KEY",
  xai_api_key: "XAI_API_KEY"
}.freeze

RUBYLLM_CREDENTIALS = begin
  Workbench::DemoMode.enabled? ? {} : Rails.application.credentials.config
rescue ActiveSupport::EncryptedFile::MissingKeyError
  {}
end.freeze

RubyLLM.configure do |config|
  RUBYLLM_CONFIGURATION_ENV.each do |option, environment_key|
    if Workbench::DemoMode.enabled?
      config.public_send("#{option}=", nil)
      next
    end
    value = ENV[environment_key]
    value ||= RUBYLLM_CREDENTIALS.dig(option)
    config.public_send("#{option}=", value) if value.present?
  end
end

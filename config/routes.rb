Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "projects#index"

  resources :projects, only: %i[index create show] do
    resources :chats, only: %i[new create show destroy] do
      resources :messages, only: :create
      resources :approvals, only: :update
    end
    resources :tool_definitions, only: %i[index update], controller: :tool_definitions
    patch "tool-settings", to: "tool_definitions#update_settings", as: :tool_settings
    resources :knowledge_collections, path: "knowledge", only: %i[index create show] do
      resources :items, only: :create, controller: :knowledge_items
      resource :embeddings, only: %i[create destroy], controller: :knowledge_embeddings
    end
    resources :experiments, only: %i[index new create show edit update] do
      resources :executions, only: :create, controller: :experiment_executions
    end
  end

  resources :runs, only: %i[index show]
  get "models", to: "models#index", as: :models
  get "learn/:id", to: "learning_topics#show", as: :learning_topic
end

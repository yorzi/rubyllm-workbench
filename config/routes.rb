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
    resources :experiments, only: %i[index new create show edit update] do
      resources :executions, only: :create, controller: :experiment_executions
    end
  end

  resources :runs, only: %i[index show]
  get "models", to: "models#index", as: :models
end

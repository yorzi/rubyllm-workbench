Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "projects#index"

  resources :projects, only: %i[index create show] do
    resources :chats, only: %i[new create show destroy] do
      resources :messages, only: :create
    end
    resources :experiments, only: %i[index new create show edit update] do
      resources :executions, only: :create, controller: :experiment_executions
    end
  end

  resources :runs, only: %i[index show]
  get "models", to: "models#index", as: :models
end

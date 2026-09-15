Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "projects#index"

  resources :projects, only: %i[index create show] do
    resources :chats, only: %i[new create show destroy] do
      resources :messages, only: :create
    end
  end

  resources :runs, only: :show
  get "models", to: "models#index", as: :models
end

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "projects#index"

  resources :projects, only: %i[index create show] do
    resources :chats, only: %i[new create show destroy] do
      resources :image_runs, path: "images", only: %i[new create], controller: :image_runs
      resources :transcription_runs, path: "transcriptions", only: %i[new create], controller: :transcription_runs
      resources :video_runs, path: "videos", only: %i[new create], controller: :video_runs
      resources :messages, only: :create do
        resource :speech_run, only: %i[new create], controller: :speech_runs
      end
      resources :approvals, only: :update
    end
    resources :tool_definitions, only: %i[index update], controller: :tool_definitions
    resources :agent_definitions, path: "agents", only: %i[index new create show edit update destroy] do
      post "runs", to: "agent_runs#create", as: :runs
    end
    patch "tool-settings", to: "tool_definitions#update_settings", as: :tool_settings
    resources :knowledge_collections, path: "knowledge", only: %i[index create show] do
      resources :items, only: :create, controller: :knowledge_items
      resource :embeddings, only: %i[create destroy], controller: :knowledge_embeddings
    end
    resources :experiments, only: %i[index new create show edit update] do
      resources :executions, only: :create, controller: :experiment_executions
    end
    resources :evaluation_datasets, path: "evaluations", only: %i[index new create show edit update] do
      resources :case_attachments, only: %i[create destroy], controller: :evaluation_case_attachments
      get "revisions/:revision_id/case_attachments/:attachment_id",
        to: "evaluation_case_attachments#show",
        as: :revision_case_attachment
      resources :executions, only: :create, controller: :evaluation_executions do
        post :resume, on: :member
        post :resume_judgments, on: :member
        post :refresh, on: :member
        post :close_unknown, on: :member
        resources :case_results, only: [] do
          resources :reviews, only: :create, controller: :evaluation_case_reviews
        end
      end
    end
  end

  resources :runs, only: %i[index show] do
    post :cancel, on: :member
    get :reproduction, on: :member
    get :events, on: :member
    post :upstream_candidates, on: :member
    get "upstream_candidates/:artifact_id/issue-draft", action: :upstream_issue_draft, on: :member, as: :upstream_issue_draft
  end
  get "models", to: "models#index", as: :models
  get "learn/:id", to: "learning_topics#show", as: :learning_topic
end

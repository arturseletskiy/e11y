# frozen_string_literal: true

Rails.application.routes.draw do
  # Test routes for integration testing
  resources :posts, only: %i[index show create]

  get "/test_error", to: "posts#error"
  get "/test_redirect", to: "posts#redirect"
  get "/posts_list", to: "posts#list"

  resources :users, only: [:create]
  resources :orders, only: [:create]
  resources :documents, only: [:create]
  resources :reports, only: [:create]

  namespace :api do
    namespace :v1 do
      resources :payments, only: [:create]
      get "/protected", to: "protected#index"
    end
  end
end

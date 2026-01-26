# frozen_string_literal: true

Rails.application.routes.draw do
  # Test routes for integration testing
  resources :posts, only: %i[index show create]

  get "/test_error", to: "posts#error"
  get "/test_redirect", to: "posts#redirect"
end

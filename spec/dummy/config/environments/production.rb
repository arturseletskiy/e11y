# frozen_string_literal: true

Dummy::Application.configure do
  # Production-like settings for integration tests
  config.cache_classes = true
  config.eager_load = true

  # Show full error reports
  config.consider_all_requests_local = false

  # Disable request forgery protection in test environment
  config.action_controller.allow_forgery_protection = false

  # Print deprecation notices
  config.active_support.deprecation = :stderr

  # Raises error for missing translations
  # config.i18n.raise_on_missing_translations = true

  # Disable caching
  config.action_controller.perform_caching = false
  config.cache_store = :null_store
end

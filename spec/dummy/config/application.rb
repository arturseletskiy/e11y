# frozen_string_literal: true

# Set RAILS_ROOT before loading Rails so paths resolve correctly
DUMMY_APP_ROOT = File.expand_path("..", __dir__)

require "rails"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_mailer/railtie"
require "active_job/railtie"
require "rails/test_unit/railtie"

# Load E11y gem and configure BEFORE defining Application class
# This ensures Railtie is registered before Rails collects railties
require "e11y"

E11y.configure do |config|
  config.enabled = true
  config.service_name = "dummy_app"
  config.environment = ENV["RAILS_ENV"] || "test"

  # Use in-memory adapter for testing
  config.adapters[:memory] = E11y::Adapters::InMemory.new

  # Also register as :logs adapter so events go to memory by default
  config.adapters[:logs] = config.adapters[:memory]

  # Enable instrumentation
  config.rails_instrumentation.enabled = true
  config.active_job.enabled = true
  config.sidekiq.enabled = true if defined?(Sidekiq)
  config.logger_bridge.enabled = false

  # Reconfigure pipeline for tests: 100% sampling (capture all events)
  config.pipeline.clear
  config.pipeline.use E11y::Middleware::TraceContext
  config.pipeline.use E11y::Middleware::Validation
  config.pipeline.use E11y::Middleware::PIIFilter
  config.pipeline.use E11y::Middleware::AuditSigning
  config.pipeline.use E11y::Middleware::Sampling,
                      default_sample_rate: 1.0,
                      trace_aware: false,
                      severity_rates: { debug: 1.0, info: 1.0, warn: 1.0, error: 1.0, fatal: 1.0 }
  config.pipeline.use E11y::Middleware::Routing
end

module Dummy
  class Application < Rails::Application
    # Set root to dummy app directory (must be first)
    config.root = DUMMY_APP_ROOT

    # Rails 8 requires setting paths before they're frozen
    # Override the default database config path
    config.paths.add "config/database", with: File.join(DUMMY_APP_ROOT, "config", "database.yml")

    # Rails configuration
    # Don't load defaults to avoid version-specific settings
    # config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = true # Load all files to ensure models/controllers are available
    config.cache_classes = true
    config.consider_all_requests_local = true
    config.action_controller.perform_caching = false
    config.action_dispatch.show_exceptions = :none
    config.action_controller.allow_forgery_protection = false
    config.active_support.deprecation = :stderr
    config.active_support.test_order = :random

    # Secret key base (required for Rails)
    config.secret_key_base = "test_secret_key_base_for_dummy_app_integration_tests"

    # Disable Rails logs in test output (E11y will handle logging)
    config.logger = Logger.new(nil) unless ENV["VERBOSE"]
    config.log_level = :fatal
  end
end

# WORKAROUND: Rails 8.1+ removed sqlite3_production_warning but railtie still tries to set it
# Add empty setter to prevent NoMethodError
module ActiveRecord
  class Base
    class << self
      attr_accessor :sqlite3_production_warning unless respond_to?(:sqlite3_production_warning=)
    end
  end
end

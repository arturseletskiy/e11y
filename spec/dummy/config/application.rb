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

# Load E11y gem BEFORE defining Application class
# This ensures Railtie is registered before Rails collects railties
require "e11y"

# Configure E11y ONCE (guard against multiple loads during test suite)
# rubocop:disable Style/GlobalVars
unless $e11y_dummy_configured
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
    # NOTE: This must happen BEFORE Rails.application.initialize! is called
    config.pipeline.clear
    config.pipeline.use E11y::Middleware::TraceContext
    config.pipeline.use E11y::Middleware::Validation
    config.pipeline.use E11y::Middleware::PIIFilter
    config.pipeline.use E11y::Middleware::AuditSigning
    config.pipeline.use E11y::Middleware::RateLimiting
    config.pipeline.use E11y::Middleware::Sampling,
                        default_sample_rate: 1.0,
                        trace_aware: false,
                        severity_rates: { debug: 1.0, info: 1.0, warn: 1.0, error: 1.0, fatal: 1.0 }
    config.pipeline.use E11y::Middleware::Routing
    config.pipeline.use E11y::Middleware::EventSlo
  end
  $e11y_dummy_configured = true
end
# rubocop:enable Style/GlobalVars

module Dummy
  # Guard against redefining Application class during test suite
  unless defined?(Application)
    class Application < Rails::Application
    end
  end

  # ALWAYS apply configuration (even if Application is already defined)
  # This ensures settings are applied consistently across all test files
  Application.configure do
    # Set root to dummy app directory (must be first)
    config.root = DUMMY_APP_ROOT

    # Rails configuration
    # Don't load defaults to avoid version-specific settings
    # config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false # Set to false to avoid frozen array issues during multiple test runs
    config.cache_classes = false # Set to false to allow reloading during tests
    config.consider_all_requests_local = true
    config.action_controller.perform_caching = false
    # Use false to ensure exceptions are raised (not handled) in tests
    # Rails 7.0: false is the correct value
    # Rails 7.1+: false is deprecated (should use :none) but still works
    # NOTE: :none doesn't work in Rails 7.0 (it's treated as truthy, causing exceptions to be swallowed)
    config.action_dispatch.show_exceptions = false
    config.action_controller.allow_forgery_protection = false
    config.active_support.deprecation = :stderr
    config.active_support.test_order = :random

    # Fix Rails 8.1 deprecation warning for to_time timezone behavior
    config.active_support.to_time_preserves_timezone = :zone

    # Secret key base (required for Rails)
    config.secret_key_base = "test_secret_key_base_for_dummy_app_integration_tests"

    # Disable Rails logs in test output (E11y will handle logging)
    config.logger = Logger.new(nil) unless ENV["VERBOSE"]
    config.log_level = :fatal

    # Disable host authorization for testing
    # Rails 6.1+ has HostAuthorization middleware that blocks requests without proper Host header
    config.hosts.clear if config.respond_to?(:hosts)

    # Filter parameters for PII filtering integration tests
    config.filter_parameters += %i[
      password
      password_confirmation
      api_key
      token
      authorization
      secret
      cvv
    ]
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

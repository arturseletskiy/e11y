# frozen_string_literal: true

require "rails/railtie"

module E11y
  # Rails integration via Railtie
  #
  # Provides zero-config Rails integration:
  # - Auto-initialization on Rails boot
  # - Middleware insertion (request context, tracing)
  # - ActiveSupport::Notifications integration
  # - Rails.logger bridge (optional)
  # - Console helpers
  #
  # @example Basic usage (no config needed)
  #   # In Rails app, E11y auto-configures:
  #   # - Service name from Rails.application.name
  #   # - Environment from Rails.env
  #   # - Adapters: stdout (dev), loki (prod)
  #
  # @example Custom configuration
  #   # config/initializers/e11y.rb
  #   E11y.configure do |config|
  #     config.service_name = "my-app"
  #     config.adapters[:loki] = E11y::Adapters::Loki.new(url: ENV['LOKI_URL'])
  #   end
  #
  # @see ADR-008 §3 (Railtie & Initialization)

  # Rails integration engine that handles E11y initialization and setup
  #
  # This Railtie manages the lifecycle of E11y within a Rails application,
  # including configuration, middleware insertion, instrumentation setup,
  # and console integration.
  class Railtie < Rails::Railtie
    # Wire up generators so `rails g e11y:*` commands are discoverable.
    generators do
      require "generators/e11y/install/install_generator"
      require "generators/e11y/event/event_generator"
      require "generators/e11y/grafana_dashboard/grafana_dashboard_generator"
      require "generators/e11y/prometheus_alerts/prometheus_alerts_generator"
    end
    # Derive service name from Rails application class
    # @return [String] Service name (e.g., "my_app")
    def self.derive_service_name
      Rails.application.class.module_parent_name.underscore
    rescue StandardError
      "rails_app"
    end

    # Run before framework initialization
    config.before_initialize do
      # Set up basic configuration from Rails
      E11y.configure do |config|
        config.environment ||= Rails.env.to_s
        config.service_name ||= E11y::Railtie.derive_service_name
        # Enable in dev/prod; disable in test by default — only when still unset (nil).
        # Respects explicit true/false from earlier E11y.configure (e.g. config/application.rb).
        config.enabled = !Rails.env.test? if config.enabled.nil?
      end
    end

    # Setup instrumentation after Rails initialization
    initializer "e11y.setup_instrumentation", after: :load_config_initializers do
      next unless E11y.config.enabled

      # Setup instruments (each can be enabled/disabled separately)
      E11y::Railtie.setup_rails_instrumentation if E11y.config.rails_instrumentation_enabled
      E11y::Railtie.setup_logger_bridge if E11y.config.logger_bridge_enabled
      E11y::Railtie.setup_sidekiq if defined?(::Sidekiq) && E11y.config.sidekiq_enabled
      E11y::Railtie.setup_active_job if defined?(::ActiveJob) && E11y.config.active_job_enabled
    end

    # Outgoing HTTP trace propagation (UC-009)
    initializer "e11y.http_tracing", after: :load_config_initializers do
      next unless E11y.configuration.enable_http_tracing

      E11y::Tracing.patch_net_http!
    end

    # Auto-register DevLog adapter and alias standard adapter slots in development.
    # Only runs in development. Skipped if user already registered :dev_log.
    # Slot aliasing (:logs, :errors_tracker) respects user-set values via ||=.
    initializer "e11y.dev_log_adapter", after: :load_config_initializers do
      next unless Rails.env.development?
      next if E11y.configuration.adapters.key?(:dev_log)

      dev_log = E11y::Adapters::DevLog.new(
        path: Rails.root.join("log", "e11y_dev.jsonl"),
        max_lines: ENV.fetch("E11Y_MAX_EVENTS", "10000").to_i,
        max_size: ENV.fetch("E11Y_MAX_SIZE", "50").to_i * 1024 * 1024,
        keep_rotated: ENV.fetch("E11Y_KEEP_ROTATED", "5").to_i,
        enable_watcher: true
      )
      E11y::Railtie.setup_development_adapters(dev_log)
    end

    # Insert DevLogSource middleware in development.
    # Always runs — even if user provided a custom :dev_log adapter —
    # because the middleware is needed for overlay/TUI source tagging.
    initializer "e11y.dev_log_middleware", after: :load_config_initializers do |app|
      next unless Rails.env.development?

      require "e11y/middleware/dev_log_source"
      app.middleware.use E11y::Middleware::DevLogSource
    end

    # Middleware insertion
    initializer "e11y.middleware" do |app|
      next unless E11y.config.enabled

      # Insert E11y request middleware before Rails logger
      # This ensures trace context is set up before any Rails logging
      # API-only mode may omit Rails::Rack::Logger — fall back to unshift
      begin
        app.middleware.insert_before(Rails::Rack::Logger, E11y::Middleware::Request)
      rescue RuntimeError
        # Rails::Rack::Logger not in stack (e.g. api_only)
        app.middleware.unshift(E11y::Middleware::Request)
      end
    end

    # Console helpers
    console do
      next unless E11y.config.enabled

      require "e11y/console"
      E11y::Console.enable!

      puts "E11y loaded. Try: E11y.stats"
    end

    # Rake task helpers
    rake_tasks do
      load File.expand_path("../tasks/e11y_slo.rake", __dir__)
      load File.expand_path("../tasks/e11y_lint.rake", __dir__)
      load File.expand_path("../tasks/e11y_events.rake", __dir__)
      load File.expand_path("../tasks/e11y_docs.rake", __dir__)
    end

    # Setup Rails instrumentation (ActiveSupport::Notifications → E11y)
    # @return [void]
    def self.setup_rails_instrumentation
      require "e11y/instruments/rails_instrumentation"
      E11y::Instruments::RailsInstrumentation.setup!
    end

    # Setup Rails.logger bridge (optional, replaces Rails.logger)
    # @return [void]
    def self.setup_logger_bridge
      require "e11y/logger/bridge"
      E11y::Logger::Bridge.setup!
    end

    # Setup Sidekiq integration (client + server middleware)
    # @return [void]
    def self.setup_sidekiq
      require "e11y/instruments/sidekiq"

      # Configure server middleware
      ::Sidekiq.configure_server do |config|
        config.server_middleware do |chain|
          chain.add E11y::Instruments::Sidekiq::ServerMiddleware
        end
      end

      # Configure client middleware
      ::Sidekiq.configure_client do |config|
        config.client_middleware do |chain|
          chain.add E11y::Instruments::Sidekiq::ClientMiddleware
        end
      end
    end

    # Setup ActiveJob integration (callbacks)
    # @return [void]
    def self.setup_active_job
      require "e11y/instruments/active_job"

      # Include callbacks into ApplicationJob (if defined)
      ::ApplicationJob.include(E11y::Instruments::ActiveJob::Callbacks) if defined?(::ApplicationJob)

      # Also include into ActiveJob::Base as fallback
      ::ActiveJob::Base.include(E11y::Instruments::ActiveJob::Callbacks)
    end

    # Setup development adapter slots — aliases :logs and :errors_tracker to
    # the DevLog instance unless the user has already configured those slots.
    # Also updates fallback_adapters when still at the default [:stdout].
    #
    # @param dev_log [E11y::Adapters::DevLog] The DevLog instance to alias
    # @return [void]
    def self.setup_development_adapters(dev_log)
      E11y.configure do |config|
        config.register_adapter :dev_log, dev_log
        config.adapters[:logs]           ||= dev_log
        config.adapters[:errors_tracker] ||= dev_log
        config.fallback_adapters = [:dev_log] if config.fallback_adapters == [:stdout]
      end
    end
  end
end

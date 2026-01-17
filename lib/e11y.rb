# frozen_string_literal: true

require "zeitwerk"

# Zeitwerk autoloader setup
loader = Zeitwerk::Loader.for_gem
loader.setup

# E11y - Event-Driven Observability for Ruby on Rails
#
# @example Basic usage
#   E11y.configure do |config|
#     config.adapters = [:loki, :sentry]
#   end
#
#   E11y.track(Events::UserSignup.new(user_id: 123))
#
# @see https://e11y.dev Documentation
module E11y
  class Error < StandardError; end
  class ValidationError < Error; end
  class ZoneViolationError < Error; end
  class InvalidPipelineError < Error; end

  class << self
    # Configure E11y
    #
    # @yield [Configuration] configuration object
    # @return [void]
    #
    # @example
    #   E11y.configure do |config|
    #     config.adapters = [:loki, :stdout]
    #     config.log_level = :debug
    #   end
    def configure
      yield configuration if block_given?
    end

    # Get current configuration
    #
    # @return [Configuration] current configuration instance
    def configuration
      @configuration ||= Configuration.new
    end

    # Track an event
    #
    # @param event [Event] event instance to track
    # @return [void]
    #
    # @example
    #   E11y.track(Events::UserSignup.new(user_id: 123))
    def track(event)
      # TODO: Implement in Phase 1
      raise NotImplementedError, "E11y.track will be implemented in Phase 1"
    end

    # Get logger instance
    #
    # @return [Logger] logger instance
    def logger
      require "logger"
      @logger ||= ::Logger.new($stdout)
    end

    # Reset configuration (primarily for testing)
    #
    # @return [void]
    # @api private
    def reset!
      @configuration = nil
      @logger = nil
    end
  end

  # Configuration class for E11y
  #
  # Adapters are referenced by name (e.g., :logs, :errors_tracker).
  # The actual implementation (Loki, Sentry, etc.) is configured separately.
  #
  # @example Configure adapters
  #   E11y.configure do |config|
  #     # Register adapter instances
  #     config.adapters[:logs] = E11y::Adapters::Loki.new(url: "...")
  #     config.adapters[:errors_tracker] = E11y::Adapters::Sentry.new(dsn: "...")
  #   end
  #
  # @example Configure severity => adapter mapping
  #   E11y.configure do |config|
  #     config.adapter_mapping[:error] = [:logs, :errors_tracker]
  #     config.adapter_mapping[:info] = [:logs]
  #   end
  class Configuration
    attr_accessor :adapters, :log_level
    attr_reader :adapter_mapping

    def initialize
      @adapters = {} # Hash of adapter_name => adapter_instance
      @log_level = :info
      @adapter_mapping = default_adapter_mapping
    end

    # Get adapters for given severity
    #
    # @param severity [Symbol] Severity level
    # @return [Array<Symbol>] Adapter names (e.g., [:logs, :errors_tracker])
    def adapters_for_severity(severity)
      @adapter_mapping[severity] || @adapter_mapping[:default] || []
    end

    private

    # Default adapter mapping (convention-based)
    #
    # Adapter names represent PURPOSE, not implementation:
    # - :logs → centralized logging (implementation: Loki, Elasticsearch, CloudWatch, etc.)
    # - :errors_tracker → error tracking with alerting (implementation: Sentry, Rollbar, Bugsnag, etc.)
    #
    # @return [Hash{Symbol => Array<Symbol>}] Default mapping (severity => adapter names)
    def default_adapter_mapping
      {
        error: %i[logs errors_tracker],  # Errors: both logging + alerting
        fatal: %i[logs errors_tracker],  # Fatal: both logging + alerting
        default: [:logs]                 # Others: logging only
      }
    end
  end
end

# Eager load for production (optional - uncomment if needed)
# loader.eager_load if ENV["RAILS_ENV"] == "production"

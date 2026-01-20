# frozen_string_literal: true

require "zeitwerk"

# Zeitwerk autoloader setup
loader = Zeitwerk::Loader.for_gem
# Configure inflector for acronyms
loader.inflector.inflect(
  "pii" => "PII",
  "pii_filter" => "PIIFilter"
)
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
    alias config configuration

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
  #
  # @example Configure middleware pipeline
  #   E11y.configure do |config|
  #     config.pipeline.use E11y::Middleware::Sampling, default_sample_rate: 0.1
  #   end
  class Configuration
    attr_accessor :adapters, :log_level, :enabled, :environment, :service_name
    attr_reader :adapter_mapping, :pipeline, :rails_instrumentation, :logger_bridge, :request_buffer, :error_handling,
                :dlq_storage, :dlq_filter, :rate_limiting, :slo_tracking

    def initialize
      @adapters = {} # Hash of adapter_name => adapter_instance
      @log_level = :info
      @adapter_mapping = default_adapter_mapping
      @pipeline = E11y::Pipeline::Builder.new
      @enabled = true
      @environment = nil
      @service_name = nil
      @rails_instrumentation = RailsInstrumentationConfig.new
      @logger_bridge = LoggerBridgeConfig.new
      @request_buffer = RequestBufferConfig.new
      @error_handling = ErrorHandlingConfig.new # ✅ C18 Resolution
      @dlq_storage = nil # Set by user (e.g., DLQ::FileStorage instance)
      @dlq_filter = nil # Set by user (e.g., DLQ::Filter instance)
      @rate_limiting = RateLimitingConfig.new
      @slo_tracking = SLOTrackingConfig.new # ✅ L3.14.1
      configure_default_pipeline
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

    # Setup default middleware pipeline
    #
    # Default pipeline order (per ADR-015):
    # 1. TraceContext - Add trace_id, span_id, timestamp (zone: :pre_processing)
    # 2. Validation - Schema validation (zone: :pre_processing)
    # 3. PIIFilter - PII filtering (zone: :security)
    # 4. AuditSigning - Audit event signing (zone: :security)
    # 5. Sampling - Adaptive sampling (zone: :routing)
    # 6. Routing - Buffer routing (zone: :adapters)
    #
    # @return [void]
    # @see ADR-015 Middleware Execution Order
    def configure_default_pipeline
      # Zone: :pre_processing
      @pipeline.use E11y::Middleware::TraceContext
      @pipeline.use E11y::Middleware::Validation

      # Zone: :security
      @pipeline.use E11y::Middleware::PIIFilter
      @pipeline.use E11y::Middleware::AuditSigning

      # Zone: :routing
      @pipeline.use E11y::Middleware::Sampling

      # Zone: :adapters
      @pipeline.use E11y::Middleware::Routing
    end
  end

  # Rails Instrumentation configuration
  class RailsInstrumentationConfig
    attr_accessor :enabled, :custom_mappings, :ignore_events

    def initialize
      @enabled = false # Disabled by default, enabled by Railtie
      @custom_mappings = {}
      @ignore_events = []
    end

    # Override event class for specific ASN pattern (Devise-style)
    # @param pattern [String] ActiveSupport::Notifications pattern
    # @param event_class [Class] E11y event class
    # @return [void]
    def event_class_for(pattern, event_class)
      @custom_mappings[pattern] = event_class
    end

    # Ignore specific ASN event
    # @param pattern [String] ActiveSupport::Notifications pattern
    # @return [void]
    def ignore_event(pattern)
      @ignore_events << pattern
    end
  end

  # Logger Bridge configuration
  class LoggerBridgeConfig
    attr_accessor :enabled, :dual_logging

    def initialize
      @enabled = false # Opt-in
      @dual_logging = true # Keep writing to original Rails.logger
    end
  end

  # Request Buffer configuration
  class RequestBufferConfig
    attr_accessor :enabled

    def initialize
      @enabled = false # Disabled by default
    end
  end

  # Error Handling configuration (C18 Resolution)
  #
  # Controls whether event tracking failures should raise exceptions.
  # Default: true (for web requests - fast feedback)
  # Exception: false (for background jobs - don't fail business logic)
  #
  # @see ADR-013 §3.6 (Event Tracking in Background Jobs)
  class ErrorHandlingConfig
    attr_accessor :fail_on_error

    def initialize
      @fail_on_error = true # Default: raise errors (fast feedback for web requests)
    end
  end

  # Rate Limiting configuration (UC-011, C02 Resolution)
  #
  # Protects adapters from event floods using token bucket algorithm.
  #
  # @see UC-011 (Rate Limiting - DoS Protection)
  # @see ADR-013 §4.6 (C02 Resolution)
  class RateLimitingConfig
    attr_accessor :enabled, :global_limit, :per_event_limit, :window

    def initialize
      @enabled = false # Opt-in (enable explicitly)
      @global_limit = 10_000 # Max 10K events/sec globally
      @per_event_limit = 1_000 # Max 1K events/sec per event type
      @window = 1.0 # 1 second window
    end
  end

  # SLO Tracking configuration (UC-004, ADR-003)
  #
  # Zero-config SLO tracking for HTTP requests and background jobs.
  # Automatically emits SLO metrics (availability, latency, success rate).
  #
  # @see UC-004 (Zero-Config SLO Tracking)
  # @see ADR-003 (SLO & Observability)
  #
  # @note C11 Resolution (Sampling Correction): Requires Phase 2.8 (Stratified Sampling).
  #   Without stratified sampling, SLO metrics may be inaccurate when adaptive sampling is enabled.
  class SLOTrackingConfig
    attr_accessor :enabled

    def initialize
      @enabled = false # Opt-in (enable explicitly)
    end
  end
end

# Load Railtie if Rails is present
require "e11y/railtie" if defined?(Rails::Railtie)

# Eager load for production (optional - uncomment if needed)
# loader.eager_load if ENV["RAILS_ENV"] == "production"

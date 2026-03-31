# frozen_string_literal: true

require "zeitwerk"
require "active_support/core_ext/numeric/time" # For 30.days, 7.years, etc.

# Zeitwerk autoloader setup
loader = Zeitwerk::Loader.for_gem
# Configure inflector for acronyms
loader.inflector.inflect(
  "documentation" => "Documentation",
  "debug" => "Debug",
  # Directory lib/e11y/opentelemetry/ must map to E11y::OpenTelemetry (issue #15)
  "opentelemetry" => "OpenTelemetry",
  "opentelemetry_collector" => "OpenTelemetryCollector",
  "otel_span" => "OtelSpan",
  "pii" => "PII",
  "pii_filter" => "PIIFilter",
  "otel_logs" => "OTelLogs",
  "slo" => "SLO",
  "dlq" => "DLQ",
  "net_http_patch" => "NetHTTPPatch",
  "rspec_matchers" => "RSpecMatchers",
  "have_tracked_event_matcher" => "HaveTrackedEventMatcher",
  "snapshot_matcher" => "SnapshotMatcher"
)
# Don't autoload railtie - it will be required manually when Rails is available
loader.do_not_eager_load("#{__dir__}/e11y/railtie.rb")
# Adapters below require optional gems — skip Rails eager_load_all (issue #15 and same pattern)
loader.do_not_eager_load("#{__dir__}/e11y/adapters/otel_logs.rb")
loader.do_not_eager_load("#{__dir__}/e11y/adapters/loki.rb")
loader.do_not_eager_load("#{__dir__}/e11y/adapters/sentry.rb")
loader.do_not_eager_load("#{__dir__}/e11y/adapters/yabeda.rb")
loader.do_not_eager_load("#{__dir__}/e11y/adapters/opentelemetry_collector.rb")
# Generators live under lib/generators/ — not part of the autoloaded tree
loader.ignore("#{__dir__}/generators")
# Optional HTTP tracing files require external gems (faraday, net/http) — loaded on demand only
loader.ignore("#{__dir__}/e11y/tracing/faraday_middleware.rb")
loader.ignore("#{__dir__}/e11y/tracing/net_http_patch.rb")
loader.setup

# E11y - Event-Driven Observability for Ruby on Rails
#
# @example Basic usage
#   E11y.configure do |config|
#     config.adapters = [:loki, :sentry]
#   end
#
# @see https://e11y.dev Documentation
module E11y
  class Error < StandardError; end
  class ValidationError < Error; end
  class ZoneViolationError < Error; end
  class InvalidPipelineError < Error; end

  # Raised when PII key is blocked in baggage (ADR-006 §5.5). Used by BaggageProtection and E11y::Current.add_baggage.
  class BaggagePiiError < Error; end

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

    # Test adapter for specs (InMemoryTest in unit tests, InMemory in integration).
    # Returns :test adapter (unit tests) or :memory adapter (integration tests from dummy config).
    #
    # @return [E11y::Adapters::InMemory, E11y::Adapters::InMemoryTest, nil]
    def test_adapter
      configuration.adapters[:test] || configuration.adapters[:memory]
    end

    # Trace an event through the pipeline (debug utility).
    # Delegates to PipelineInspector.trace_event. Loads the inspector on demand.
    #
    # @param event_class [Class] event class (e.g., Events::OrderCreated)
    # @param payload [Hash] keyword arguments for the event payload
    # @return [Hash] event_data after pipeline
    #
    # @example
    #   E11y.trace(Events::OrderCreated, order_id: "123", amount: 99.99)
    def trace(event_class, **payload)
      require "e11y/debug/pipeline_inspector"
      E11y::Debug::PipelineInspector.trace_event(event_class, **payload)
    end

    # Get logger instance.
    # Priority: config.logger > Rails.logger (when in Rails) > $stdout.
    # Set config.logger = Logger.new(nil) in tests to suppress output.
    #
    # @return [Logger] logger instance
    def logger
      return configuration.logger if configuration&.logger

      return @logger if defined?(@logger) && !@logger.nil?

      require "logger"
      @logger = if defined?(Rails) && Rails.respond_to?(:application) && Rails.application
                  Rails.logger
                else
                  ::Logger.new($stdout)
                end
    end

    # Initialize E11y and all configured adapters.
    # Call after the configure block at application startup.
    #
    # @return [void]
    def start!
      return unless configuration.enabled

      configuration.adapters.each_value do |adapter|
        adapter.start! if adapter.respond_to?(:start!)
      end
      logger.info("[E11y] Started (#{configuration.adapters.size} adapters)")
    end

    # Gracefully shut down E11y, flushing pending events.
    #
    # @param timeout [Integer] Seconds to wait for each adapter flush (default: 5)
    # @return [void]
    def stop!(timeout: 5)
      require "timeout"
      configuration.adapters.each_value do |adapter|
        if adapter.respond_to?(:stop!)
          adapter.stop!(timeout: timeout)
        elsif adapter.respond_to?(:flush!)
          Timeout.timeout(timeout) { adapter.flush! }
        end
      rescue StandardError => e
        logger.warn("[E11y] Adapter stop error: #{e.message}")
      end
      logger.info("[E11y] Stopped")
    end

    # Check whether E11y will process events with the given severity.
    # Returns false if no healthy adapter is registered for that severity.
    #
    # @param severity [Symbol] e.g. :debug, :info, :error
    # @return [Boolean]
    def enabled_for?(severity)
      return false unless configuration.enabled

      configuration.adapters_for_severity(severity).any? do |name|
        configuration.adapters[name]&.healthy?
      end
    rescue StandardError
      false
    end

    # Current size of the request-scoped debug buffer for this thread.
    #
    # @return [Integer]
    def buffer_size
      buffer = Thread.current[:e11y_ephemeral_buffer]
      buffer.respond_to?(:size) ? buffer.size : 0
    end

    # Circuit breaker states for all adapters.
    #
    # @return [Hash{Symbol => Symbol}] adapter_name => :closed / :open / :half_open
    def circuit_breaker_state
      configuration.adapters.transform_values do |adapter|
        if adapter.respond_to?(:circuit_breaker_state)
          adapter.circuit_breaker_state
        else
          :closed
        end
      end
    end

    # Access the global Event Registry singleton.
    #
    # The registry auto-populates as event classes are defined (via the `event_name` DSL setter).
    # Useful for introspection, documentation generation, and admin dashboards.
    #
    # @return [E11y::Registry]
    #
    # @example
    #   E11y.registry.event_classes
    #   E11y.registry.find("order.created")
    def registry
      Registry.instance
    end

    # Returns true when Rails is booting in asset-precompile / image-build mode.
    #
    # During `RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 rails assets:precompile`
    # (the standard Kamal / Docker build pattern) encrypted credentials and most
    # runtime secrets are unavailable. E11y detects this automatically and skips
    # adapter instrumentation so the build succeeds without secrets.
    #
    # Use this predicate to guard initializer code that accesses credentials:
    #
    # @example
    #   # config/initializers/e11y.rb
    #   unless E11y.build_mode?
    #     E11y.configure do |config|
    #       config.adapters[:errors_tracker] = E11y::Adapters::Sentry.new(
    #         dsn: Rails.application.credentials.sentry_dsn,
    #         required: true
    #       )
    #     end
    #   end
    #
    # @return [Boolean]
    def build_mode?
      !ENV["SECRET_KEY_BASE_DUMMY"].to_s.strip.empty?
    end

    # Reset configuration (primarily for testing)
    #
    # @return [void]
    # @api private
    def reset!
      @configuration = nil
      @logger = nil
      E11y::Metrics.reset_backend!
    end
  end

  # Default allowed keys for baggage protection (ADR-006 §5.5).
  # Used when security_baggage_protection_allowed_keys is not set.
  BAGGAGE_PROTECTION_DEFAULT_ALLOWED_KEYS = %w[
    trace_id span_id environment version service_name deployment_id request_id
    user_id experiment experiment_id tenant feature_flag
  ].freeze
end

# Load Railtie if Rails is present
require "e11y/railtie" if defined?(Rails::Railtie)

# Eager load for production (optional - uncomment if needed)
# loader.eager_load if ENV["RAILS_ENV"] == "production"

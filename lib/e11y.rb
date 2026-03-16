# frozen_string_literal: true

require "zeitwerk"
require "active_support/core_ext/numeric/time" # For 30.days, 7.years, etc.

# Zeitwerk autoloader setup
loader = Zeitwerk::Loader.for_gem
# Configure inflector for acronyms
loader.inflector.inflect(
  "documentation" => "Documentation",
  "debug" => "Debug",
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

    # Track an event
    #
    # Accepts either an event instance or an event class with an optional payload.
    # Delegates to the event class's `.track` method.
    #
    # @param event_or_class [E11y::Event::Base, Class] event instance or event class
    # @param payload [Hash] keyword arguments forwarded to EventClass.track (used with class form)
    # @return [void]
    #
    # @example Pass an event instance
    #   E11y.track(Events::UserSignup.new)
    #
    # @example Pass an event class with payload
    #   E11y.track(Events::UserSignup, user_id: 123)
    def track(event_or_class, **payload)
      event_class = event_or_class.is_a?(Class) ? event_or_class : event_or_class.class
      event_class.track(**payload)
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
  # Default allowed keys for baggage protection (ADR-006 §5.5).
  # Used when security_baggage_protection_allowed_keys is not set.
  BAGGAGE_PROTECTION_DEFAULT_ALLOWED_KEYS = %w[
    trace_id span_id environment version service_name deployment_id request_id
    experiment experiment_id tenant feature_flag
  ].freeze

  class Configuration
    attr_accessor :adapters, :log_level, :logger, :enabled, :environment, :service_name, :default_retention_period,
                  :routing_rules, :fallback_adapters, :enable_http_tracing,
                  :rails_instrumentation_enabled, :rails_instrumentation_custom_mappings, :rails_instrumentation_ignore_events,
                  :logger_bridge_enabled, :logger_bridge_track_severities, :logger_bridge_ignore_patterns,
                  :sidekiq_enabled, :active_job_enabled,
                  :ephemeral_buffer_enabled, :ephemeral_buffer_flush_on_error, :ephemeral_buffer_flush_on_statuses,
                  :ephemeral_buffer_debug_adapters, :ephemeral_buffer_job_buffer_limit,
                  :error_handling_fail_on_error,
                  :rate_limiting_enabled, :rate_limiting_global_limit, :rate_limiting_global_window,
                  :rate_limiting_per_event_limit, :rate_limiting_per_event_limits,
                  :slo_tracking_enabled, :slo_tracking_http_ignore_statuses, :slo_tracking_latency_percentiles,
                  :slo_tracking_controller_configs, :slo_tracking_job_configs,
                  :security_baggage_protection_enabled, :security_baggage_protection_allowed_keys, :security_baggage_protection_block_mode,
                  :tracing_source, :tracing_default_sample_rate, :tracing_respect_parent_sampling,
                  :tracing_per_event_sample_rates, :tracing_always_sample_if,
                  :opentelemetry_span_creation_patterns,
                  :cardinality_protection_max_cardinality_limit, :cardinality_protection_denylist, :cardinality_protection_overflow_strategy
    attr_reader :adapter_mapping, :pipeline, :dlq_storage, :dlq_filter

    def initialize
      initialize_basic_config
      initialize_routing_config
      initialize_feature_configs
      configure_default_pipeline
    end

    private

    def initialize_basic_config
      @adapters = {} # Hash of adapter_name => adapter_instance
      @log_level = :info
      @pipeline = E11y::Pipeline::Builder.new
      @enabled = nil
      @environment = nil
      @service_name = nil
      @enable_http_tracing = false # Opt-in: disabled by default
    end

    def initialize_routing_config
      @adapter_mapping = default_adapter_mapping
      @default_retention_period = 30.days # Default: 30 days retention
      @routing_rules = [] # Array of lambdas for retention-based routing
      @fallback_adapters = [:stdout] # Fallback if no routing rule matches
    end

    def initialize_feature_configs
      @rails_instrumentation_enabled = false
      @rails_instrumentation_custom_mappings = {}
      @rails_instrumentation_ignore_events = []
      @logger_bridge_enabled = false
      @logger_bridge_track_severities = nil
      @logger_bridge_ignore_patterns = []
      @sidekiq_enabled = false
      @active_job_enabled = false
      @ephemeral_buffer_enabled = false
      @ephemeral_buffer_flush_on_error = true
      @ephemeral_buffer_flush_on_statuses = []
      @ephemeral_buffer_debug_adapters = nil
      @ephemeral_buffer_job_buffer_limit = nil
      @error_handling_fail_on_error = true # C18 Resolution: default true for web requests
      @dlq_storage = nil # Set by user (e.g., DLQ::FileAdapter instance)
      @dlq_filter = nil # Set by user (e.g., DLQ::Filter instance)
      @rate_limiting_enabled = false
      @rate_limiting_global_limit = 10_000
      @rate_limiting_global_window = 1.0
      @rate_limiting_per_event_limit = 1_000
      @rate_limiting_per_event_limits = []
      @slo_tracking_enabled = true
      @slo_tracking_http_ignore_statuses = []
      @slo_tracking_latency_percentiles = [50, 95, 99]
      @slo_tracking_controller_configs = {}
      @slo_tracking_job_configs = {}
      @security_baggage_protection_enabled = true
      @security_baggage_protection_allowed_keys = E11y::BAGGAGE_PROTECTION_DEFAULT_ALLOWED_KEYS.dup
      @security_baggage_protection_block_mode = :silent
      @tracing_source = :e11y
      @tracing_default_sample_rate = 0.1
      @tracing_respect_parent_sampling = true
      @tracing_per_event_sample_rates = {}
      @tracing_always_sample_if = nil
      @opentelemetry_span_creation_patterns = []
      @cardinality_protection_max_cardinality_limit = 1000
      @cardinality_protection_denylist = []
      @cardinality_protection_overflow_strategy = :relabel
    end

    public

    # Get adapters for given severity
    #
    # @param severity [Symbol] Severity level
    # @return [Array<Symbol>] Adapter names (e.g., [:logs, :errors_tracker])
    def adapters_for_severity(severity)
      @adapter_mapping[severity] || @adapter_mapping[:default] || []
    end

    # Get built pipeline (cached after first call)
    #
    # @return [#call] Built middleware pipeline
    def built_pipeline
      @built_pipeline ||= @pipeline.build(->(_event_data) {})
    end

    # Add per-event rate limit rule.
    #
    # @param pattern [String] Event name or glob pattern (e.g. "payment.*")
    # @param limit [Integer] Max events per window for this pattern
    # @param window [Numeric] Window size in seconds
    # @example config.add_rate_limit_per_event "payment.*", limit: 500, window: 60
    def add_rate_limit_per_event(pattern, limit:, window: 1.0)
      (@rate_limiting_per_event_limits ||= []) << {
        pattern: pattern.to_s,
        limit: limit,
        window: window.to_f
      }
    end

    # Find the most specific rate limit config for a given event name.
    # Per-event rules take precedence; falls back to per_event_limit + global_window.
    #
    # @param event_name [String] Event name to look up
    # @return [Hash] { limit:, window: }
    def rate_limit_for(event_name)
      limits = @rate_limiting_per_event_limits || []
      match = limits.find do |rule|
        pattern = rule[:pattern].gsub(".", "\\.").gsub("*", ".*")
        Regexp.new("^#{pattern}$").match?(event_name.to_s)
      end
      m = match || { limit: @rate_limiting_per_event_limit, window: @rate_limiting_global_window }
      { limit: m[:limit], window: m[:window] }
    end

    # Add per-controller SLO config.
    #
    # @param name [String] Controller class name
    # @param action [String, nil] Specific action (nil = all actions)
    # @yield [ControllerSLOConfig] Block for slo_target, latency_target, etc.
    def add_slo_controller(name, action: nil, &block)
      key = action ? "#{name}##{action}" : name
      cfg = ControllerSLOConfig.new
      cfg.instance_eval(&block) if block_given?
      (@slo_tracking_controller_configs ||= {})[key] = cfg
    end

    # Add per-job SLO config.
    #
    # @param name [String] Job class name
    # @yield [JobSLOConfig] Block for ignore, etc.
    def add_slo_job(name, &block)
      cfg = JobSLOConfig.new
      cfg.instance_eval(&block) if block_given?
      (@slo_tracking_job_configs ||= {})[name] = cfg
    end

    # Set slo_tracking enabled — accepts Boolean.
    #
    # @param value [Boolean]
    # @example config.slo_tracking = true
    def slo_tracking=(value)
      @slo_tracking_enabled = value if value.is_a?(TrueClass) || value.is_a?(FalseClass)
    end

    # Filter baggage hash to only allowed keys (for tracestate/job propagation).
    # Used by Propagator and Sidekiq/ActiveJob when injecting E11y::Current.baggage.
    #
    # @param hash [Hash, nil] Baggage key-value pairs
    # @return [Hash] Only allowed keys (empty if disabled or nil input)
    def filter_baggage_for_propagation(hash)
      return {} if hash.nil? || !hash.is_a?(Hash)
      return hash unless @security_baggage_protection_enabled

      allowed = (@security_baggage_protection_allowed_keys || E11y::BAGGAGE_PROTECTION_DEFAULT_ALLOWED_KEYS).map(&:to_s)
      hash.select { |k, _| allowed.include?(k.to_s) }
    end

    # Register an adapter instance by name (convenience alias for config.adapters[name] = instance).
    #
    # @param name [Symbol, String] Adapter name (e.g. :loki, :sentry)
    # @param instance [E11y::Adapters::Base] Adapter instance
    # @example config.register_adapter :loki, E11y::Adapters::Loki.new(url: ENV["LOKI_URL"])
    def register_adapter(name, instance)
      @adapters[name.to_sym] = instance
    end

    # Set the default adapter(s) used when no severity-specific mapping matches.
    #
    # @param names [Symbol, Array<Symbol>]
    # @example config.default_adapters = [:loki]
    def default_adapters=(names)
      @adapter_mapping[:default] = Array(names).map(&:to_sym)
    end

    # @return [Array<Symbol>] Default adapter names
    def default_adapters
      @adapter_mapping[:default]
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
    # 1. TraceContext  - Add trace_id, span_id, timestamp (zone: :pre_processing)
    # 2. Validation   - Schema validation (zone: :pre_processing)
    # 3. AuditSigning - Sign audit events with ORIGINAL data before PII filter (zone: :security)
    # 4. PIIFilter    - PII filtering (zone: :security)
    # 5. RateLimiting - Token-bucket rate limiting (zone: :routing)
    # 6. Sampling     - Adaptive sampling (zone: :routing)
    # 7. Versioning   - Normalize event names (LAST before Routing, zone: :adapters)
      # 0. TrackLatency  - Self-monitoring: Event.track() latency (first, wraps entire pipeline)
      # 1. TraceContext  - Distributed tracing metadata
      # ...
      # 9. Routing      - Buffer routing (zone: :adapters)
      # 10. EventSlo     - Event-driven SLO tracking (after adapters, observes dispatch)
      # 11. SelfMonitoringEmit - e11y_events_tracked_total (last, when e11y_self_monitoring.enabled)
      #
      # @return [void]
      # @see ADR-015 Middleware Execution Order
      def configure_default_pipeline
      # Zone: :pre_processing (TrackLatency first — measures full pipeline)
      @pipeline.use E11y::Middleware::TrackLatency
      @pipeline.use E11y::Middleware::TraceContext
      @pipeline.use E11y::Middleware::Validation

      # Zone: :security (AuditSigning BEFORE PIIFilter — sign original data per GDPR Art. 30)
      @pipeline.use E11y::Middleware::BaggageProtection # ADR-006 §5.5: OTel Baggage PII protection
      @pipeline.use E11y::Middleware::AuditSigning
      @pipeline.use E11y::Middleware::PIIFilter

      # Zone: :routing (ADR-015: RateLimiting #4, Sampling #5)
      @pipeline.use E11y::Middleware::RateLimiting
      @pipeline.use E11y::Middleware::Sampling

      # Zone: :adapters (Versioning LAST — normalize names only for adapters)
      @pipeline.use E11y::Middleware::Versioning
      @pipeline.use E11y::Middleware::Routing

      # After adapters: observes dispatch outcome for SLO tracking
      @pipeline.use E11y::Middleware::EventSlo
      @pipeline.use E11y::Middleware::SelfMonitoringEmit
    end
  end

  # Per-controller SLO config (used by add_slo_controller).
  class ControllerSLOConfig
    def slo_target(value = nil)
      value ? @slo_target = value : @slo_target
    end

    def latency_target(value = nil)
      value ? @latency_target = value : @latency_target
    end
  end

  # Per-job SLO config (used by add_slo_job).
  class JobSLOConfig
    def ignore(value = nil)
      value.nil? ? @ignore : @ignore = value
    end
  end

end

# Load Railtie if Rails is present
require "e11y/railtie" if defined?(Rails::Railtie)

# Eager load for production (optional - uncomment if needed)
# loader.eager_load if ENV["RAILS_ENV"] == "production"

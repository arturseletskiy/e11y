# frozen_string_literal: true

require "zeitwerk"
require "active_support/core_ext/numeric/time" # For 30.days, 7.years, etc.

# Zeitwerk autoloader setup
loader = Zeitwerk::Loader.for_gem
# Configure inflector for acronyms
loader.inflector.inflect(
  "pii" => "PII",
  "pii_filter" => "PIIFilter",
  "otel_logs" => "OTelLogs",
  "slo" => "SLO",
  "dlq" => "DLQ",
  "net_http_patch" => "NetHTTPPatch"
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
      buffer = Thread.current[:e11y_request_buffer]
      buffer.respond_to?(:size) ? buffer.size : 0
    end

    # Circuit breaker states for all adapters.
    #
    # @return [Hash{Symbol => Symbol}] adapter_name => :closed / :open / :half_open
    def circuit_breaker_state
      configuration.adapters.each_with_object({}) do |(name, adapter), result|
        result[name] = if adapter.respond_to?(:circuit_breaker_state)
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
    #   E11y.registry.all_events
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
  class Configuration
    attr_accessor :adapters, :log_level, :logger, :enabled, :environment, :service_name, :default_retention_period,
                  :routing_rules, :fallback_adapters, :enable_http_tracing
    attr_reader :adapter_mapping, :pipeline, :rails_instrumentation, :logger_bridge, :request_buffer, :active_job,
                :sidekiq, :error_handling, :dlq_storage, :dlq_filter, :cardinality_protection

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
      @rails_instrumentation = RailsInstrumentationConfig.new
      @logger_bridge = LoggerBridgeConfig.new
      @request_buffer = RequestBufferConfig.new
      @active_job = ActiveJobConfig.new
      @sidekiq = SidekiqConfig.new
      @error_handling = ErrorHandlingConfig.new # ✅ C18 Resolution
      @dlq_storage = nil # Set by user (e.g., DLQ::FileAdapter instance)
      @dlq_filter = nil # Set by user (e.g., DLQ::Filter instance)
      @rate_limiting = RateLimitingConfig.new
      @slo_tracking = SLOTrackingConfig.new # ✅ L3.14.1
      @cardinality_protection = CardinalityProtectionConfig.new
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

    # Rate limiting config — call with block for DSL, without for plain access.
    #
    # @example DSL form
    #   config.rate_limiting do
    #     global limit: 10_000, window: 1.minute
    #     per_event "user.login.failed", limit: 100, window: 1.minute
    #   end
    # @example Plain access
    #   config.rate_limiting.enabled = true
    def rate_limiting(&block)
      block_given? ? @rate_limiting.instance_eval(&block) : @rate_limiting
    end

    # SLO tracking config — call with block for DSL, without for plain access.
    #
    # @example DSL form
    #   config.slo do
    #     http_ignore_statuses [404, 401]
    #     latency_percentiles [50, 95, 99]
    #     controller "Api::OrdersController", action: "show" do
    #       slo_target 0.999
    #       latency_target 200
    #     end
    #   end
    def slo(&block)
      block_given? ? @slo_tracking.instance_eval(&block) : @slo_tracking
    end

    # @return [SLOTrackingConfig]
    def slo_tracking(&block)
      block_given? ? @slo_tracking.instance_eval(&block) : @slo_tracking
    end

    # Set slo_tracking — accepts Boolean (coerced) or SLOTrackingConfig.
    #
    # @param value [Boolean, SLOTrackingConfig]
    # @example config.slo_tracking = true  # enables; no longer crashes
    def slo_tracking=(value)
      case value
      when TrueClass, FalseClass
        @slo_tracking.enabled = value
      when SLOTrackingConfig
        @slo_tracking = value
      end
    end

    # Cardinality protection config — call with block for DSL, without for plain access.
    #
    # @example
    #   config.cardinality_protection do
    #     max_cardinality 1000
    #     denylist [:user_id, :order_id, :email]
    #     overflow_strategy :relabel
    #   end
    def cardinality_protection(&block)
      block_given? ? @cardinality_protection.instance_eval(&block) : @cardinality_protection
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
    # 2. Versioning    - Normalize event names: OrderPaidEvent → order.paid (zone: :pre_processing)
    # 3. Validation    - Schema validation (zone: :pre_processing)
    # 4. PIIFilter     - PII filtering (zone: :security)
    # 5. AuditSigning  - Audit event signing (zone: :security)
    # 6. RateLimiting  - Token-bucket rate limiting (zone: :routing)
    # 7. Sampling      - Adaptive sampling (zone: :routing)
    # 8. Routing       - Buffer routing (zone: :adapters)
    # 9. EventSlo      - Event-driven SLO tracking (after adapters, observes dispatch)
    #
    # @return [void]
    # @see ADR-015 Middleware Execution Order
    def configure_default_pipeline
      # Zone: :pre_processing
      @pipeline.use E11y::Middleware::TraceContext
      @pipeline.use E11y::Middleware::Versioning   # normalise names before validation
      @pipeline.use E11y::Middleware::Validation

      # Zone: :security
      @pipeline.use E11y::Middleware::PIIFilter
      @pipeline.use E11y::Middleware::AuditSigning

      # Zone: :routing (ADR-015: Sampling before RateLimiting)
      @pipeline.use E11y::Middleware::Sampling
      @pipeline.use E11y::Middleware::RateLimiting

      # Zone: :adapters
      @pipeline.use E11y::Middleware::Routing

      # After adapters: observes dispatch outcome for SLO tracking
      @pipeline.use E11y::Middleware::EventSlo
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
  #
  # Controls Rails.logger integration:
  # - When enabled = true: wraps Rails.logger and sends logs to E11y
  # - When enabled = false: no integration (default)
  #
  # @example Enable logger bridge
  #   E11y.configure do |config|
  #     config.logger_bridge.enabled = true  # Wrap Rails.logger + send to E11y
  #   end
  #
  # @see lib/e11y/logger/bridge.rb
  class LoggerBridgeConfig
    attr_accessor :enabled

    def initialize
      @enabled = false # Opt-in: disabled by default
    end
  end

  # Request Buffer configuration
  class RequestBufferConfig
    attr_accessor :enabled, :flush_on_error, :flush_on_statuses

    # Explicit list of adapter names that receive flushed debug events on request failure.
    #
    # If nil (default), falls back to config.fallback_adapters.
    # Set this to limit debug flushes to adapters that can handle the extra load.
    #
    # @example Only flush debug events to Loki (not Sentry)
    #   config.request_buffer.debug_adapters = [:loki_logger]
    attr_accessor :debug_adapters

    def initialize
      @enabled           = false  # Disabled by default
      @flush_on_error    = true   # Flush buffer on 5xx server errors (default: true)
      @flush_on_statuses = []     # Additional HTTP statuses that trigger a flush (e.g. [403])
      @debug_adapters    = nil    # nil → use fallback_adapters
    end
  end

  # ActiveJob configuration
  #
  # Controls ActiveJob integration (callbacks for event tracking).
  # When enabled, E11y will automatically track job lifecycle events:
  # - job.enqueued
  # - job.started
  # - job.completed
  # - job.failed
  #
  # @see lib/e11y/instruments/active_job.rb
  class ActiveJobConfig
    attr_accessor :enabled

    def initialize
      @enabled = false # Disabled by default, enabled by Railtie
    end
  end

  # Sidekiq configuration
  #
  # Controls Sidekiq middleware integration for trace propagation and context setup.
  # Automatically enabled by Railtie when Sidekiq is detected.
  #
  # @see ADR-008 §9 (Sidekiq Integration)
  class SidekiqConfig
    attr_accessor :enabled

    def initialize
      @enabled = false # Disabled by default, enabled by Railtie when Sidekiq is present
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
  # Supports global limits and per-event-pattern limits.
  #
  # @see UC-011 (Rate Limiting - DoS Protection)
  # @see ADR-013 §4.6 (C02 Resolution)
  #
  # @example Block DSL
  #   config.rate_limiting do
  #     global limit: 10_000, window: 1.minute
  #     per_event "user.login.failed", limit: 100, window: 1.minute
  #     per_event "payment.*", limit: 500, window: 1.minute
  #   end
  class RateLimitingConfig
    attr_accessor :enabled, :global_limit, :global_window, :per_event_limit
    attr_reader :per_event_limits

    def initialize
      @enabled = false      # Opt-in (enable explicitly)
      @global_limit = 10_000 # Max 10K events/sec globally
      @global_window = 1.0   # 1 second window
      @per_event_limit = 1_000 # Default per-event limit (used when no per_event_limits rules match)
      @per_event_limits = []
    end

    # Alias for middleware compatibility (uses global_window)
    def window
      @global_window
    end

    def window=(value)
      @global_window = (defined?(ActiveSupport::Duration) && value.is_a?(ActiveSupport::Duration)) ? value.to_f : value.to_f
    end

    # Set global rate limit.
    # @param limit [Integer] Max events per window globally
    # @param window [Numeric, ActiveSupport::Duration] Window size
    def global(limit:, window: 1.0)
      @global_limit = limit
      @global_window = window.is_a?(ActiveSupport::Duration) ? window.to_f : window.to_f
    end

    # Set per-event (or per-pattern) rate limit.
    # @param pattern [String] Event name or glob pattern (e.g. "payment.*")
    # @param limit [Integer] Max events per window for this pattern
    # @param window [Numeric, ActiveSupport::Duration] Window size
    def per_event(pattern, limit:, window: 1.0)
      @per_event_limits << {
        pattern: pattern.to_s,
        limit: limit,
        window: window.is_a?(ActiveSupport::Duration) ? window.to_f : window.to_f
      }
    end

    # Find the most specific rate limit config for a given event name.
    # Per-event rules take precedence; falls back to global config.
    #
    # @param event_name [String] Event name to look up
    # @return [Hash] { limit:, window: }
    def limit_for(event_name)
      match = @per_event_limits.find do |rule|
        pattern = rule[:pattern].gsub(".", "\\.").gsub("*", ".*")
        Regexp.new("^#{pattern}$").match?(event_name.to_s)
      end
      match || { limit: @global_limit, window: @global_window }
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
  #
  # @example Block DSL
  #   config.slo do
  #     http_ignore_statuses [404, 401]
  #     latency_percentiles [50, 95, 99]
  #     controller "Api::OrdersController", action: "show" do
  #       slo_target 0.999
  #       latency_target 200
  #     end
  #     job "ReportGenerationJob" do
  #       ignore true
  #     end
  #   end
  class SLOTrackingConfig
    attr_accessor :enabled
    attr_reader :http_ignore_statuses, :latency_percentiles, :controller_configs, :job_configs

    def initialize
      @enabled = true # Zero-config: enabled by default
      @http_ignore_statuses = []
      @latency_percentiles = [50, 95, 99]
      @controller_configs = {}
      @job_configs = {}
    end

    # @param statuses [Array<Integer>] HTTP status codes to exclude from SLO calculations
    def http_ignore_statuses(statuses)
      @http_ignore_statuses = Array(statuses)
    end

    # @param percentiles [Array<Integer>] Latency percentiles to track (e.g. [50, 95, 99])
    def latency_percentiles(percentiles)
      @latency_percentiles = Array(percentiles)
    end

    # Per-controller SLO config.
    # @param name [String] Controller class name
    # @param action [String, nil] Specific action (nil = all actions)
    def controller(name, action: nil, &block)
      key = action ? "#{name}##{action}" : name
      cfg = ControllerSLOConfig.new
      cfg.instance_eval(&block) if block_given?
      @controller_configs[key] = cfg
    end

    # Per-job SLO config.
    # @param name [String] Job class name
    def job(name, &block)
      cfg = JobSLOConfig.new
      cfg.instance_eval(&block) if block_given?
      @job_configs[name] = cfg
    end

    # Per-controller SLO target config.
    class ControllerSLOConfig
      attr_reader :slo_target, :latency_target

      def slo_target(value = nil)
        value ? @slo_target = value : @slo_target
      end

      def latency_target(value = nil)
        value ? @latency_target = value : @latency_target
      end
    end

    # Per-job SLO config.
    class JobSLOConfig
      attr_reader :ignore

      def ignore(value = nil)
        value.nil? ? @ignore : @ignore = value
      end
    end
  end

  # Cardinality Protection configuration
  #
  # Global cardinality limits applied by adapters that support it (e.g. Yabeda).
  # Per-adapter config can still be passed at instantiation; this provides a global default.
  #
  # @example
  #   config.cardinality_protection do
  #     max_cardinality 1000
  #     denylist [:user_id, :order_id, :email]
  #     overflow_strategy :relabel
  #   end
  class CardinalityProtectionConfig
    attr_reader :max_cardinality_limit, :denylist, :overflow_strategy

    def initialize
      @max_cardinality_limit = 1000
      @overflow_strategy = :relabel
      @denylist = []
    end

    # @param value [Integer]
    def max_cardinality(value)
      @max_cardinality_limit = value
    end

    # @param keys [Array<Symbol>]
    def denylist(keys)
      @denylist = Array(keys).map(&:to_sym)
    end

    # @param strategy [Symbol] :relabel or :drop
    def overflow_strategy(strategy)
      @overflow_strategy = strategy
    end
  end
end

# Load Railtie if Rails is present
require "e11y/railtie" if defined?(Rails::Railtie)

# Eager load for production (optional - uncomment if needed)
# loader.eager_load if ENV["RAILS_ENV"] == "production"

# frozen_string_literal: true

module E11y
  # Configuration class for E11y.
  #
  # Adapters are referenced by name (e.g., :logs, :errors_tracker).
  # The actual implementation (Loki, Sentry, etc.) is configured separately.
  #
  # @example Configure adapters
  #   E11y.configure do |config|
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
                  :cardinality_protection_max_cardinality_limit, :cardinality_protection_denylist, :cardinality_protection_overflow_strategy,
                  :dlq_storage, :dlq_filter
    attr_reader :adapter_mapping, :pipeline

    def initialize
      initialize_basic_config
      initialize_routing_config
      initialize_feature_configs
      configure_default_pipeline
    end

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
    def add_rate_limit_per_event(pattern, limit:, window: 1.0)
      (@rate_limiting_per_event_limits ||= []) << {
        pattern: pattern.to_s,
        limit: limit,
        window: window.to_f
      }
    end

    # Find the most specific rate limit config for a given event name.
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
    def add_slo_controller(name, action: nil, &)
      key = action ? "#{name}##{action}" : name
      cfg = ControllerSLOConfig.new
      cfg.instance_eval(&) if block_given?
      (@slo_tracking_controller_configs ||= {})[key] = cfg
    end

    # Add per-job SLO config.
    def add_slo_job(name, &)
      cfg = JobSLOConfig.new
      cfg.instance_eval(&) if block_given?
      (@slo_tracking_job_configs ||= {})[name] = cfg
    end

    # Set slo_tracking enabled — accepts Boolean.
    def slo_tracking=(value)
      @slo_tracking_enabled = value if value.is_a?(TrueClass) || value.is_a?(FalseClass)
    end

    # Filter baggage hash to only allowed keys (for tracestate/job propagation).
    def filter_baggage_for_propagation(hash)
      return {} if hash.nil? || !hash.is_a?(Hash)
      return hash unless @security_baggage_protection_enabled

      allowed = (@security_baggage_protection_allowed_keys || E11y::BAGGAGE_PROTECTION_DEFAULT_ALLOWED_KEYS).map(&:to_s)
      hash.select { |k, _| allowed.include?(k.to_s) }
    end

    # Register an adapter instance by name.
    def register_adapter(name, instance)
      @adapters[name.to_sym] = instance
    end

    # Set the default adapter(s) used when no severity-specific mapping matches.
    def default_adapters=(names)
      @adapter_mapping[:default] = Array(names).map(&:to_sym)
    end

    # @return [Array<Symbol>] Default adapter names
    def default_adapters
      @adapter_mapping[:default]
    end

    private

    def initialize_basic_config
      @adapters = {}
      @log_level = :info
      @pipeline = E11y::Pipeline::Builder.new
      @enabled = nil
      @environment = nil
      @service_name = nil
      @enable_http_tracing = false
    end

    def initialize_routing_config
      @adapter_mapping = default_adapter_mapping
      @default_retention_period = 30.days
      @routing_rules = []
      @fallback_adapters = [:stdout]
    end

    def initialize_feature_configs
      init_instrumentation_configs
      init_ephemeral_buffer_configs
      init_error_handling_configs
      init_rate_limiting_configs
      init_slo_configs
      init_security_configs
      init_tracing_configs
      init_cardinality_configs
    end

    def init_instrumentation_configs
      @rails_instrumentation_enabled = false
      @rails_instrumentation_custom_mappings = {}
      @rails_instrumentation_ignore_events = []
      @logger_bridge_enabled = false
      @logger_bridge_track_severities = nil
      @logger_bridge_ignore_patterns = []
      @sidekiq_enabled = false
      @active_job_enabled = false
    end

    def init_ephemeral_buffer_configs
      @ephemeral_buffer_enabled = false
      @ephemeral_buffer_flush_on_error = true
      @ephemeral_buffer_flush_on_statuses = []
      @ephemeral_buffer_debug_adapters = nil
      @ephemeral_buffer_job_buffer_limit = nil
    end

    def init_error_handling_configs
      @error_handling_fail_on_error = true
      @dlq_storage = nil
      @dlq_filter = nil
    end

    def init_rate_limiting_configs
      @rate_limiting_enabled = false
      @rate_limiting_global_limit = 10_000
      @rate_limiting_global_window = 1.0
      @rate_limiting_per_event_limit = 1_000
      @rate_limiting_per_event_limits = []
    end

    def init_slo_configs
      @slo_tracking_enabled = true
      @slo_tracking_http_ignore_statuses = []
      @slo_tracking_latency_percentiles = [50, 95, 99]
      @slo_tracking_controller_configs = {}
      @slo_tracking_job_configs = {}
    end

    def init_security_configs
      @security_baggage_protection_enabled = true
      @security_baggage_protection_allowed_keys = E11y::BAGGAGE_PROTECTION_DEFAULT_ALLOWED_KEYS.dup
      @security_baggage_protection_block_mode = :silent
    end

    def init_tracing_configs
      @tracing_source = :e11y
      @tracing_default_sample_rate = 0.1
      @tracing_respect_parent_sampling = true
      @tracing_per_event_sample_rates = {}
      @tracing_always_sample_if = nil
      @opentelemetry_span_creation_patterns = []
    end

    def init_cardinality_configs
      @cardinality_protection_max_cardinality_limit = 1000
      @cardinality_protection_denylist = []
      @cardinality_protection_overflow_strategy = :relabel
    end

    def default_adapter_mapping
      {
        error: %i[logs errors_tracker],
        fatal: %i[logs errors_tracker],
        default: [:logs]
      }
    end

    def configure_default_pipeline
      @pipeline.use E11y::Middleware::TrackLatency
      @pipeline.use E11y::Middleware::TraceContext
      @pipeline.use E11y::Middleware::Validation
      @pipeline.use E11y::Middleware::BaggageProtection
      @pipeline.use E11y::Middleware::AuditSigning
      @pipeline.use E11y::Middleware::PIIFilter
      @pipeline.use E11y::Middleware::RateLimiting
      @pipeline.use E11y::Middleware::Sampling
      @pipeline.use E11y::Middleware::Versioning
      @pipeline.use E11y::Middleware::Routing
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

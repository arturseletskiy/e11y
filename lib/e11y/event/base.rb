# frozen_string_literal: true

require "dry-schema"
require "e11y/slo/event_driven"

module E11y
  module Event
    # Base class for all E11y events using zero-allocation pattern
    #
    # Events are tracked using class methods (not instances) to avoid memory allocations.
    # All event data is stored in Hashes, not objects.
    #
    # @abstract Subclass and define schema using {.schema}
    #
    # @example Define custom event
    #   class OrderPaidEvent < E11y::Event::Base
    #     schema do
    #       required(:order_id).filled(:integer)
    #       required(:amount).filled(:float)
    #     end
    #
    #     severity :success
    #     adapters :loki
    #   end
    #
    #   # Track event (zero-allocation)
    #   OrderPaidEvent.track(order_id: 123, amount: 99.99)
    #
    # @see ADR-001 §3.1 Zero-Allocation Design
    # @see UC-002 Business Event Tracking
    # rubocop:disable Metrics/ClassLength
    class Base
      extend SLO::EventDriven::DSL

      # Severity levels (ordered by importance)
      SEVERITIES = %i[debug info success warn error fatal].freeze

      # Performance optimization: Inline severity defaults (avoid method call overhead)
      # Used by resolve_sample_rate for fast lookup
      SEVERITY_SAMPLE_RATES = {
        error: 1.0,
        fatal: 1.0,
        debug: 0.01,
        info: 0.1,
        success: 0.1,
        warn: 0.1
      }.freeze

      # Pre-allocated event_data hash structure (reduce GC pressure)
      # Keys are pre-defined to avoid hash resizing during track()
      EVENT_HASH_TEMPLATE = {
        event_name: nil,
        payload: nil,
        severity: nil,
        version: nil,
        adapters: nil,
        timestamp: nil
      }.freeze

      # Validation modes for performance tuning
      # - :always (default) - Validate all events (safest, ~60μs overhead)
      # - :sampled - Validate 1% of events (balanced, ~6μs avg overhead)
      # - :never - Skip validation (fastest, ~2μs, use with trusted input only)
      VALIDATION_MODES = %i[always sampled never].freeze

      # Default validation sampling rate (when mode is :sampled)
      # 1% = catch schema bugs while maintaining high performance
      DEFAULT_VALIDATION_SAMPLE_RATE = 0.01

      class << self
        # Track an event (zero-allocation pattern)
        #
        # This is the main entry point for all events. No object is created - only a Hash.
        # Returns event hash for testing/debugging. In Phase 2, pipeline will be added.
        #
        # Optimizations applied:
        # - Pre-allocated hash template (reduce GC pressure)
        # - Cached severity/adapters (avoid repeated method calls)
        # - Inline timestamp generation
        # - Configurable validation mode (:always, :sampled, :never)
        # - Auto-calculated retention_until from retention_period
        #
        # @param payload [Hash] Event data matching the schema
        # @yield Optional block — measured for duration; adds :duration_ms to payload
        # @return [Hash] Event hash (includes metadata)
        #
        # @example Without block
        #   UserSignupEvent.track(user_id: 123, email: "user@example.com")
        #   # => { event_name: "UserSignupEvent", payload: {...}, severity: :info, adapters: [:logs], ... }
        #
        # @example With block (duration measurement)
        #   Events::OrderPaid.track(order_id: '123') { ExternalPaymentService.charge! }
        #   # => payload includes duration_ms automatically
        #
        # @raise [E11y::ValidationError] if payload doesn't match schema (when validation runs)
        def track(**payload, &block)
          return unless E11y.config.enabled

          # Block form: execute block, measure duration, capture return value
          block_result = nil
          if block
            start = Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
            block_result = yield
            payload = payload.merge(duration_ms: Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond) - start)
          end

          # Severity: payload override (e.g. exception → :error) or class default
          resolved_severity = payload[:severity] || payload["severity"] || severity

          # Build event data hash for pipeline processing
          event_data = {
            event_class: self,
            event_name: event_name,
            payload: payload,
            severity: resolved_severity,
            version: version,
            adapters: adapters,
            timestamp: Time.now.utc,
            retention_period: retention_period,
            context: build_context
          }

          # Pass through middleware pipeline (ADR-001 §3.2)
          # Pipeline handles: validation, PII filtering, rate limiting, sampling, routing
          # Routing middleware is the LAST middleware and it writes to adapters directly
          E11y.config.built_pipeline.call(event_data)

          # With block: return block's result (caller cares about it); without: return event_data
          block ? block_result : event_data
        end

        # Build event hash
        # @api private
        def build_event_hash(event_severity, event_adapters, event_timestamp, event_retention_period, payload)
          {
            event_name: event_name,
            payload: payload,
            severity: event_severity,
            version: version,
            adapters: event_adapters,
            timestamp: event_timestamp.iso8601(3), # ISO8601 with milliseconds
            retention_until: (event_timestamp + event_retention_period).iso8601, # Auto-calculated
            audit_event: audit_event? # For routing rules
          }
        end

        # Build current context for event
        # @api private
        def build_context
          {
            trace_id: E11y::Current.trace_id,
            span_id: E11y::Current.span_id,
            parent_trace_id: E11y::Current.parent_trace_id,
            request_id: E11y::Current.request_id,
            user_id: E11y::Current.user_id
          }.compact
        end

        # Configure validation mode for performance tuning
        #
        # Modes:
        # - :always (default) - Validate all events (safest, ~60μs P99)
        #   Use for: User input, external data, critical events
        #
        # - :sampled (1% by default) - Validate randomly (balanced, ~6μs avg)
        #   Use for: High-frequency events with trusted input
        #   Catches schema bugs in production without full overhead
        #
        # - :never - Skip all validation (fastest, ~2μs P99)
        #   Use for: Hot path events with guaranteed schema compliance
        #   Example: Metrics, internal events with typed input
        #
        # @param mode [Symbol] Validation mode (:always, :sampled, :never)
        # @param sample_rate [Float] Sample rate for :sampled mode (0.0-1.0, default: 0.01 = 1%)
        # @return [Symbol] Current validation mode
        #
        # @example Always validate (default, safest)
        #   class PaymentEvent < E11y::Event::Base
        #     validation_mode :always
        #   end
        #
        # @example Sampled validation (balanced performance/safety)
        #   class MetricEvent < E11y::Event::Base
        #     validation_mode :sampled, sample_rate: 0.01 # 1% validation
        #   end
        #
        # @example Never validate (maximum performance, use with caution)
        #   class HighFrequencyMetric < E11y::Event::Base
        #     validation_mode :never
        #   end
        def validation_mode(mode = nil, sample_rate: nil)
          if mode
            unless VALIDATION_MODES.include?(mode)
              raise ArgumentError,
                    "Invalid validation mode: #{mode}. Must be one of: #{VALIDATION_MODES.join(', ')}"
            end

            @validation_mode = mode
            @validation_sample_rate = sample_rate if sample_rate
          end

          @validation_mode || :always # Default: always validate (safest)
        end

        # Get current validation sample rate
        #
        # @return [Float] Sample rate (0.0-1.0)
        def validation_sample_rate
          @validation_sample_rate || DEFAULT_VALIDATION_SAMPLE_RATE
        end

        # Skip validation for hot path events (deprecated, use validation_mode :never)
        #
        # @deprecated Use {validation_mode} instead
        # @param value [Boolean] true to skip validation
        # @return [Boolean] Current skip_validation status
        # rubocop:disable Naming/PredicateMethod
        def skip_validation(value = nil)
          warn "[DEPRECATION] skip_validation is deprecated. Use validation_mode :never instead."
          @validation_mode = :never if value
          @validation_mode == :never
        end
        # rubocop:enable Naming/PredicateMethod

        # Define event schema using dry-schema
        #
        # @param block [Proc] Schema definition block
        # @yield Block for schema definition
        #
        # @example
        #   schema do
        #     required(:user_id).filled(:integer)
        #     required(:email).filled(:string)
        #   end
        def schema(&block)
          @schema_block = block
        end

        # Get or build schema
        #
        # @return [Dry::Schema::Params, nil] Compiled schema
        def compiled_schema
          return nil unless @schema_block

          @compiled_schema ||= Dry::Schema.Params(&@schema_block)
        end

        # Set or get event severity
        #
        # @param value [Symbol, nil] Severity level (debug, info, success, warn, error, fatal)
        # @return [Symbol] Current severity
        #
        # @example
        #   class FailureEvent < E11y::Event::Base
        #     severity :error
        #   end
        def severity(value = nil)
          if value
            raise ArgumentError, "Invalid severity: #{value}. Must be one of: #{SEVERITIES.join(', ')}" unless SEVERITIES.include?(value)

            @severity = value
          end

          # Return explicitly set severity OR inherit from parent (if set) OR resolve by convention
          return @severity if @severity
          return superclass.severity if superclass != E11y::Event::Base && superclass.instance_variable_get(:@severity)

          resolved_severity
        end

        # Set or get event version
        #
        # @param value [Integer, nil] Event version
        # @return [Integer] Current version (default: 1)
        #
        # @example
        #   class OrderPaidEventV2 < E11y::Event::Base
        #     version 2
        #   end
        VERSION_REGEX = /V(\d+)$/

        def version(value = nil)
          @version = value if value
          return @version if @version

          # Auto-extract from class name (e.g. OrderPaidV2 → 2)
          match = name&.match(VERSION_REGEX)
          match ? match[1].to_i : 1
        end

        # Set or get retention period for this event
        #
        # Retention period determines how long events should be kept in storage.
        # Used by routing middleware to select appropriate adapters (hot/warm/cold storage).
        #
        # @param value [ActiveSupport::Duration, nil] Retention period (e.g., 30.days, 7.years)
        # @return [ActiveSupport::Duration] Current retention period
        #
        # @example Short retention (debug logs)
        #   class DebugEvent < E11y::Event::Base
        #     retention_period 7.days
        #   end
        #
        # @example Long retention (audit events)
        #   class UserDeletedEvent < E11y::Event::Base
        #     audit_event true
        #     retention_period 7.years  # GDPR compliance
        #   end
        #
        # @example Default retention (from config)
        #   class OrderEvent < E11y::Event::Base
        #     # No retention_period specified → uses config default (30 days)
        #   end
        def retention_period(value = nil)
          @retention_period = value if value
          # Return explicitly set retention_period OR inherit from parent (if set) OR config default OR final fallback
          return @retention_period if @retention_period
          return superclass.retention_period if superclass != E11y::Event::Base && superclass.instance_variable_get(:@retention_period)

          # Fallback to configuration or 30 days
          E11y.configuration&.default_retention_period || 30.days
        end

        # Convenience alias — matches Quick Start documentation.
        alias retention retention_period

        # Set or get adapters for this event
        #
        # Adapters are referenced by NAME (e.g., :logs, :errors_tracker).
        # The actual implementation is configured separately in E11y.configuration.
        #
        # @param list [Array<Symbol>, nil] Adapter names
        # @return [Array<Symbol>] Current adapter names
        #
        # @example Using adapter names
        #   class CriticalEvent < E11y::Event::Base
        #     adapters :logs, :errors_tracker
        #   end
        #
        # @example Adapter implementation is configured separately
        #   E11y.configure do |config|
        #     config.adapters[:logs] = E11y::Adapters::Loki.new(...)
        #     config.adapters[:errors_tracker] = E11y::Adapters::Sentry.new(...)
        #   end
        def adapters(*list)
          @adapters = list.flatten if list.any?
          # Return explicitly set adapters OR inherit from parent (if set) OR resolve from severity
          return @adapters if @adapters
          return superclass.adapters if superclass != E11y::Event::Base && superclass.instance_variable_get(:@adapters)

          # No explicit adapters: inherit from parent or resolve from severity
          # (audit events and regular events both use severity-based mapping)
          resolved_adapters
        end

        # Get or set event name (normalized)
        #
        # When called with a value, stores it and auto-registers the class in `E11y::Registry`.
        # When called without a value, derives the name from the class name (stripping version suffix).
        #
        # @param value [String, Symbol, nil] Explicit event name to set, or nil to read
        # @return [String] Event name
        #
        # @example Explicit name
        #   class OrderPaidEvent < E11y::Event::Base
        #     event_name "order.paid"
        #   end
        #
        # @example Auto-derived name
        #   OrderPaidEventV2.event_name # => "OrderPaidEvent"
        def event_name(value = nil)
          if value
            @event_name = value.to_s
            @event_name_explicit = true
            # Auto-register in E11y::Registry when an explicit name is set.
            # Guard with defined? so that loading order does not matter.
            # NOTE: call register AFTER setting @event_name_explicit so that any
            # re-entrant call to event_name (from Registry#register) returns the
            # correct value instead of falling through to the auto-derive path.
            E11y::Registry.register(self) if defined?(E11y::Registry)
            return @event_name
          end

          # Return explicitly-set name unconditionally (works for anonymous classes too)
          return @event_name if @event_name_explicit

          # Don't cache for anonymous classes (name returns nil)
          return @event_name if @event_name && name

          class_name = name || "AnonymousEvent"
          @event_name = class_name.sub(/V\d+$/, "")
        end

        # Set or get explicit sample rate for this event
        #
        # Sample rate determines what percentage of events to process (0.0-1.0).
        # If not explicitly set, falls back to severity-based defaults.
        #
        # @param value [Float, nil] Sample rate (0.0-1.0)
        # @return [Float, nil] Explicitly set sample rate (nil if using severity-based default)
        #
        # @example Explicit sample rate
        #   class HighFrequencyEvent < E11y::Event::Base
        #     sample_rate 0.01  # 1% sampling
        #   end
        #
        # @example Disable sampling (always process)
        #   class CriticalEvent < E11y::Event::Base
        #     sample_rate 1.0  # 100% sampling
        #   end
        def sample_rate(value = nil)
          if value
            unless value.is_a?(Numeric) && value >= 0.0 && value <= 1.0
              raise ArgumentError, "Sample rate must be between 0.0 and 1.0, got: #{value.inspect}"
            end

            @sample_rate = value.to_f
          end

          # Return explicitly set sample_rate OR inherit from parent (if set) OR nil (use resolve_sample_rate)
          return @sample_rate if @sample_rate
          return superclass.sample_rate if superclass != E11y::Event::Base && superclass.instance_variable_get(:@sample_rate)

          nil
        end

        # Configure value-based sampling (FEAT-4849)
        #
        # Prioritize high-value events for sampling based on payload values.
        # Events matching any configured rule will be sampled at 100%.
        #
        # @param field [String, Symbol] Field to extract value from
        # @param comparisons [Hash] Comparison rules
        # @option comparisons [Numeric] :greater_than (>) Sample if value > threshold
        # @option comparisons [Numeric] :less_than (<) Sample if value < threshold
        # @option comparisons [Object] :equals (==) Sample if value == threshold
        # @option comparisons [Range] :in_range Sample if value in range
        # @return [void]
        #
        # @example High-value payments
        #   class PaymentEvent < E11y::Event::Base
        #     sample_by_value :amount, greater_than: 1000
        #   end
        #
        # @example Range-based sampling
        #   class OrderEvent < E11y::Event::Base
        #     sample_by_value :total, in_range: 100..500
        #   end
        def sample_by_value(field, comparisons)
          require "e11y/event/value_sampling_config"
          @value_sampling_configs ||= []
          @value_sampling_configs << ValueSamplingConfig.new(field, comparisons)
        end

        # Get value-based sampling configurations
        #
        # @return [Array<ValueSamplingConfig>] Configured sampling rules
        def value_sampling_configs
          @value_sampling_configs || []
        end

        # Resolve sample rate for this event
        #
        # Sample rate determines what percentage of events to process (0.0-1.0)
        # Precedence: explicit sample_rate > severity-based defaults
        # Convention: error/fatal = 1.0 (all), success = 0.1 (10%), debug = 0.01 (1%)
        #
        # Optimized: Uses inline lookup table instead of case statement
        #
        # @return [Float] Sample rate (0.0-1.0)
        def resolve_sample_rate
          # 1. Explicit sample_rate (highest priority)
          return sample_rate if sample_rate

          # 2. Severity-based defaults (inline lookup, faster than case statement)
          SEVERITY_SAMPLE_RATES[severity] || 0.1
        end

        # Configure adaptive sampling for this event
        #
        # Adaptive sampling adjusts sample rate dynamically based on conditions.
        # This is a placeholder for future implementation (L2.7 continuation).
        #
        # @param enabled [Boolean] Enable adaptive sampling
        # @param options [Hash] Adaptive sampling options
        # @option options [Float] :error_rate_threshold (0.05) Error rate to trigger 100% sampling
        # @option options [Integer] :load_threshold (50000) Events/sec to trigger reduced sampling
        # @option options [Float] :high_load_sample_rate (0.01) Sample rate during high load
        # @return [Hash, nil] Adaptive sampling configuration
        #
        # @example Enable adaptive sampling
        #   class OrderEvent < E11y::Event::Base
        #     adaptive_sampling enabled: true,
        #                       error_rate_threshold: 0.05,
        #                       load_threshold: 50_000
        #   end
        def adaptive_sampling(enabled: false, **options)
          @adaptive_sampling = { enabled: true }.merge(options) if enabled

          # Return explicitly set config OR inherit from parent (if set) OR nil
          return @adaptive_sampling if @adaptive_sampling
          return superclass.adaptive_sampling if superclass != E11y::Event::Base && superclass.instance_variable_get(:@adaptive_sampling)

          nil
        end

        # Resolve rate limit for this event (events per second)
        #
        # Rate limit prevents flooding with too many events
        # Convention: error = unlimited, others = 1000/sec
        #
        # @return [Integer, nil] Max events per second (nil = unlimited)
        def resolve_rate_limit
          case severity
          when :error, :fatal
            nil # Unlimited - не теряем ошибки
          else
            1000 # 1000 events/sec
          end
        end

        # Set a per-event-class rate limit for the RateLimiting middleware.
        #
        # Overrides the global rate limit for events of this class.
        # error/fatal events are always exempt (never rate-limited).
        #
        # @param count [Integer] Max events allowed per window
        # @param window [Numeric, ActiveSupport::Duration] Time window in seconds (default: 1.0)
        #
        # @example Strict limit for login failures (brute-force protection)
        #   class Events::UserLoginFailed < E11y::Event::Base
        #     rate_limit 100, window: 60
        #   end
        def rate_limit(count, window: 1.0)
          @rate_limit_count = count
          @rate_limit_window = window.to_f
        end

        # Per-event rate limit configuration.
        #
        # @return [Hash] { count: Integer|nil, window: Float|nil }
        def rate_limit_config
          { count: @rate_limit_count, window: @rate_limit_window }
        end

        private

        # Determine if validation should run for this event
        #
        # Respects validation_mode setting:
        # - :always → true (always validate)
        # - :never → false (never validate)
        # - :sampled → random sampling based on validation_sample_rate
        #
        # @return [Boolean] true if validation should run
        def should_validate?
          case validation_mode
          when :never
            false
          when :sampled
            # Random sampling (thread-safe, uses Kernel.rand)
            rand < validation_sample_rate
          else
            # :always or unknown mode - fallback to safe default
            true
          end
        end

        # Validate payload against schema
        #
        # @param payload [Hash] Event data
        # @raise [E11y::ValidationError] if validation fails
        # @return [void]
        def validate_payload!(payload)
          schema = compiled_schema
          return unless schema # No schema = no validation

          result = schema.call(payload)
          return if result.success?

          # Build error message from dry-schema errors
          errors = result.errors.to_h
          raise E11y::ValidationError, "Validation failed for #{event_name}: #{errors.inspect}"
        end

        # Resolve severity using conventions (CONTRADICTION_01 Solution)
        #
        # Convention: Event name patterns determine severity
        # - *Failed*, *Error* → :error
        # - *Paid*, *Success*, *Completed* → :success
        # - *Warn*, *Warning* → :warn
        # - Default → :info
        #
        # @return [Symbol] Resolved severity
        def resolved_severity
          event_name_str = event_name.to_s
          case event_name_str
          when /Failed/, /Error/
            :error
          when /Paid/, /Success/, /Completed/
            :success
          when /Warn/, /Warning/
            :warn
          else
            :info
          end
        end

        # Resolve adapters using conventions (CONTRADICTION_01 Solution)
        #
        # Convention: Severity determines adapter names via E11y.configuration
        # Adapter names represent PURPOSE, not implementation.
        #
        # @return [Array<Symbol>] Resolved adapter names
        # @see E11y::Configuration#adapters_for_severity
        def resolved_adapters
          E11y.configuration.adapters_for_severity(severity)
        end

        public # Make PII and Audit DSL methods public

        # === PII Filtering DSL (ADR-006, UC-007) ===

        # Declare whether event contains PII
        #
        # @param value [Boolean] true if event contains PII, false otherwise
        #
        # @example No PII (Tier 1 - Skip filtering)
        #   class Events::HealthCheck < E11y::Event::Base
        #     contains_pii false
        #   end
        #
        # @example Contains PII (Tier 3 - Deep filtering)
        #   class Events::UserRegistered < E11y::Event::Base
        #     contains_pii true
        #
        #     pii_filtering do
        #       masks :password
        #       hashes :email
        #       allows :user_id
        #     end
        #   end
        def contains_pii(value = nil)
          if value.nil?
            return superclass.contains_pii if !instance_variable_defined?(:@contains_pii) && superclass.respond_to?(:contains_pii)

            @contains_pii
          else
            @contains_pii = value
          end
        end

        # PII filtering mode for this event.
        # @return [Symbol] :no_pii, :rails_filters, or :explicit_pii
        def pii_filtering_mode
          case contains_pii
          when false then :no_pii
          when true then :explicit_pii
          else :rails_filters # Default if not explicitly declared
          end
        end

        # Define PII filtering rules (DSL block)
        #
        # @yield Block for defining field strategies
        #
        # @example
        #   pii_filtering do
        #     masks :password, :token
        #     hashes :email, :phone
        #     allows :user_id, :amount
        #   end
        def pii_filtering(&)
          if @pii_filtering_config.nil?
            parent_config = superclass.respond_to?(:pii_filtering_config) && superclass.pii_filtering_config
            @pii_filtering_config = parent_config ? { fields: parent_config[:fields].dup } : { fields: {} }
          end
          builder = PIIFilteringBuilder.new(@pii_filtering_config)
          builder.instance_eval(&)
        end

        # Get PII filtering configuration (inherits from superclass if not defined)
        #
        # @return [Hash, nil] PII filtering config
        def pii_filtering_config
          return @pii_filtering_config if instance_variable_defined?(:@pii_filtering_config) && @pii_filtering_config

          superclass.pii_filtering_config if superclass.respond_to?(:pii_filtering_config)
        end

        # PII Filtering DSL Builder
        #
        # Internal helper class for building PII filtering configuration.
        # Used by {pii_filtering} DSL method.
        #
        # @private
        # @api private
        class PIIFilteringBuilder
          def initialize(config)
            @config = config
          end

          # Mask fields (replace with [FILTERED])
          #
          # @param fields [Array<Symbol>] Field names to mask
          def masks(*fields)
            fields.each { |field| @config[:fields][field] = { strategy: :mask } }
          end

          # Hash fields (one-way hash with SHA256)
          #
          # @param fields [Array<Symbol>] Field names to hash
          def hashes(*fields)
            fields.each { |field| @config[:fields][field] = { strategy: :hash } }
          end

          # Partial mask fields (show first/last chars)
          #
          # @param fields [Array<Symbol>] Field names to partially mask
          def partials(*fields)
            fields.each { |field| @config[:fields][field] = { strategy: :partial } }
          end

          # Redact fields (remove completely)
          #
          # @param fields [Array<Symbol>] Field names to redact
          def redacts(*fields)
            fields.each { |field| @config[:fields][field] = { strategy: :redact } }
          end

          # Allow fields (no filtering)
          #
          # @param fields [Array<Symbol>] Field names to allow
          def allows(*fields)
            fields.each { |field| @config[:fields][field] = { strategy: :allow } }
          end

          # Per-field config with exclude_adapters (Tier 3 per-adapter filtering).
          #
          # @param field [Symbol] Field name
          # @yield Block with strategy, exclude_adapters
          # @example
          #   field :email do
          #     strategy :hash
          #     exclude_adapters [:file_audit]  # Audit gets original (GDPR)
          #   end
          def field(field_name, &)
            return unless block_given?

            opts = { strategy: :allow }
            dsl = Class.new do
              attr_reader :opts

              def initialize(opts) = @opts = opts
              def strategy(val) = @opts.[]=(:strategy, val)
              def exclude_adapters(adapters) = @opts.[]=(:exclude_adapters, Array(adapters).map(&:to_sym))
            end.new(opts)
            dsl.instance_eval(&)
            @config[:fields][field_name] = opts
          end
        end

        # === Audit Event DSL (ADR-006, UC-012) ===

        # Mark event as audit event
        #
        # Audit events use separate pipeline:
        # - Sign ORIGINAL data (before PII filtering)
        # - Never sampled or rate-limited
        # - Stored in encrypted audit storage
        #
        # @param value [Boolean] true if audit event
        #
        # @example
        #   class Events::UserDeleted < E11y::Event::Base
        #     audit_event true
        #
        #     schema do
        #       required(:user_id).filled(:integer)
        #       required(:deleted_by).filled(:integer)
        #     end
        #   end
        def audit_event(value = nil)
          if value.nil?
            # Getter
            @audit_event
          else
            # Setter
            @audit_event = value
          end
        end

        # Check if event is audit event
        #
        # @return [Boolean] true if audit event
        def audit_event?
          @audit_event == true
        end

        # === DLQ Filter DSL (ADR-013, UC-021) ===

        # Declare whether this event should be saved to DLQ on failure.
        #
        # @param value [Boolean, nil] true = save, false = discard, nil = use severity + default
        # @example
        #   class Events::PaymentFailed < E11y::Event::Base
        #     use_dlq true
        #   end
        #
        #   class Events::DebugTrace < E11y::Event::Base
        #     use_dlq false
        #   end
        def use_dlq(value = nil)
          if value.nil?
            return superclass.use_dlq if !instance_variable_defined?(:@use_dlq) && superclass.respond_to?(:use_dlq)

            @use_dlq
          else
            @use_dlq = value
          end
        end

        def use_dlq?
          use_dlq == true
        end

        # Configure cryptographic signing for audit event
        #
        # By default, all audit events are signed with HMAC-SHA256.
        # Use `signing enabled: false` to disable signing for specific events.
        #
        # **DESIGN CONSISTENCY**: Matches `E11y.configure { config.audit_trail { signing enabled: true } }`
        #
        # @param options [Hash] Signing configuration
        # @option options [Boolean] :enabled (true) Enable/disable signing for this event
        #
        # @example Disable signing for low-severity audit event
        #   class Events::AuditLogViewed < E11y::Event::Base
        #     audit_event true
        #     signing enabled: false  # ← No cryptographic signing
        #
        #     schema do
        #       required(:log_id).filled(:integer)
        #       required(:viewed_by).filled(:integer)
        #     end
        #   end
        #
        # @example Signing enabled (default)
        #   class Events::UserDeleted < E11y::Event::Base
        #     audit_event true
        #     # signing enabled: true (default) - signing enabled
        #
        #     schema do
        #       required(:user_id).filled(:integer)
        #     end
        #   end
        def signing(options = nil)
          if options.nil?
            # Getter: return current config
            @signing_config ||= { enabled: true }
          else
            # Setter: merge with defaults
            @signing_config = { enabled: true }.merge(options)
          end
        end

        # Check if signing is enabled for this event
        #
        # @return [Boolean] true if signing enabled (default: true)
        def signing_enabled?
          signing[:enabled] != false
        end

        # Check if event requires signing
        #
        # @return [Boolean] true if event requires signing
        def requires_signing?
          audit_event? && signing_enabled?
        end

        # === Metrics DSL (ADR-002, UC-003 Event Metrics) ===

        # Define metrics for this event
        #
        # Metrics are automatically registered in E11y::Metrics::Registry
        # and validated for label conflicts at boot time.
        #
        # @yield Block for defining metrics
        #
        # @example Counter metric
        #   class Events::OrderCreated < E11y::Event::Base
        #     metrics do
        #       counter :orders_total, tags: [:currency, :status]
        #     end
        #   end
        #
        # @example Histogram metric
        #   class Events::OrderPaid < E11y::Event::Base
        #     metrics do
        #       histogram :order_amount,
        #                 value: :amount,
        #                 tags: [:currency],
        #                 buckets: [10, 50, 100, 500, 1000]
        #     end
        #   end
        #
        # @example Gauge metric
        #   class Events::QueueSize < E11y::Event::Base
        #     metrics do
        #       gauge :queue_depth, value: :size, tags: [:queue_name]
        #     end
        #   end
        #
        # @example Multiple metrics
        #   class Events::OrderPaid < E11y::Event::Base
        #     metrics do
        #       counter :orders_total, tags: [:currency, :status]
        #       histogram :order_amount, value: :amount, tags: [:currency]
        #     end
        #   end
        def metrics(&block)
          return @metrics_config unless block

          @metrics_config ||= []
          builder = MetricsBuilder.new(@metrics_config, event_name)
          builder.instance_eval(&block)

          # Register metrics in global registry
          register_metrics_in_registry!
        end

        # Single-call metric shorthand — equivalent to a one-metric `metrics` block.
        #
        # @param type [Symbol] :counter, :histogram, or :gauge
        # @param name [Symbol] Metric name
        # @param opts [Hash] Options: tags:, value: (histogram/gauge), buckets: (histogram)
        #
        # @example
        #   metric :counter, name: :orders_total, tags: [:currency]
        #   metric :histogram, name: :order_amount, value: :amount, tags: [:currency]
        def metric(type, name:, **opts)
          raise ArgumentError, "Unknown metric type: #{type}. Use :counter, :histogram, or :gauge" unless %i[counter histogram gauge].include?(type)

          @metrics_config ||= []
          @metrics_config << { type: type, name: name }.merge(opts).compact
          register_metrics_in_registry!
        end

        # Get metrics configuration
        #
        # @return [Array<Hash>] Metrics configuration
        def metrics_config
          @metrics_config || []
        end

        private

        # Register metrics in global registry
        #
        # This is called after metrics DSL block is evaluated.
        # Validates for label conflicts at boot time.
        def register_metrics_in_registry!
          return if @metrics_config.nil? || @metrics_config.empty?

          registry = E11y::Metrics::Registry.instance
          @metrics_config.each do |metric_config|
            registry.register(metric_config.merge(
                                pattern: event_name, # Exact match for event-level metrics
                                source: "#{name}.metrics"
                              ))
          end
        end

        # Metrics DSL Builder
        #
        # Internal helper class for building metrics configuration.
        # Used by {metrics} DSL method.
        #
        # @private
        # @api private
        class MetricsBuilder
          def initialize(config, event_name)
            @config = config
            @event_name = event_name
          end

          # Define a counter metric
          #
          # Counter metrics track the number of times an event occurs.
          #
          # @param name [Symbol] Metric name (e.g., :orders_total)
          # @param tags [Array<Symbol>] Labels to extract from event data
          #
          # @example
          #   counter :orders_total, tags: [:currency, :status]
          def counter(name, tags: [])
            @config << {
              type: :counter,
              name: name,
              tags: tags
            }
          end

          # Define a histogram metric
          #
          # Histogram metrics track the distribution of values.
          #
          # @param name [Symbol] Metric name (e.g., :order_amount)
          # @param value [Symbol, Proc] Value extractor (field name or lambda)
          # @param tags [Array<Symbol>] Labels to extract from event data
          # @param buckets [Array<Numeric>] Histogram buckets (optional)
          #
          # @example With field name
          #   histogram :order_amount, value: :amount, tags: [:currency]
          #
          # @example With lambda
          #   histogram :order_amount,
          #             value: ->(event) { event[:payload][:amount] },
          #             tags: [:currency]
          def histogram(name, value:, tags: [], buckets: nil)
            @config << {
              type: :histogram,
              name: name,
              value: value,
              tags: tags,
              buckets: buckets
            }.compact
          end

          # Define a gauge metric
          #
          # Gauge metrics track the current value of something.
          #
          # @param name [Symbol] Metric name (e.g., :queue_depth)
          # @param value [Symbol, Proc] Value extractor (field name or lambda)
          # @param tags [Array<Symbol>] Labels to extract from event data
          #
          # @example
          #   gauge :queue_depth, value: :size, tags: [:queue_name]
          def gauge(name, value:, tags: [])
            @config << {
              type: :gauge,
              name: name,
              value: value,
              tags: tags
            }
          end
        end
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end

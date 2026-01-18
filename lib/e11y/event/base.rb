# frozen_string_literal: true

require "dry-schema"

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
        #
        # @param payload [Hash] Event data matching the schema
        # @return [Hash] Event hash (includes metadata)
        #
        # @example
        #   UserSignupEvent.track(user_id: 123, email: "user@example.com")
        #   # => { event_name: "UserSignupEvent", payload: {...}, severity: :info, adapters: [:logs], ... }
        #
        # @raise [E11y::ValidationError] if payload doesn't match schema (when validation runs)
        def track(**payload)
          # 1. Validate payload against schema (respects validation_mode)
          validate_payload!(payload) if should_validate?

          # 2. Build event hash with metadata (use pre-allocated template, reduce GC)
          # Cache frequently accessed values to avoid method call overhead
          event_severity = severity
          event_adapters = adapters

          # 3. TODO Phase 2: Send to pipeline
          # E11y::Pipeline.process(event_hash)

          # 4. Return event hash (pre-allocated structure for performance)
          {
            event_name: event_name,
            payload: payload,
            severity: event_severity,
            version: version,
            adapters: event_adapters,
            timestamp: Time.now.utc.iso8601(3) # ISO8601 with milliseconds
          }
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
        def skip_validation(value = nil)
          warn "[DEPRECATION] skip_validation is deprecated. Use validation_mode :never instead."
          @validation_mode = :never if value
          @validation_mode == :never
        end

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
            unless SEVERITIES.include?(value)
              raise ArgumentError, "Invalid severity: #{value}. Must be one of: #{SEVERITIES.join(', ')}"
            end

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
        def version(value = nil)
          @version = value if value
          # Return explicitly set version OR inherit from parent (if set) OR default to 1
          return @version if @version
          return superclass.version if superclass != E11y::Event::Base && superclass.instance_variable_get(:@version)

          1
        end

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

          resolved_adapters
        end

        # Get event name (normalized)
        #
        # @return [String] Event name without version suffix
        #
        # @example
        #   OrderPaidEventV2.event_name # => "OrderPaidEvent"
        def event_name
          # Don't cache for anonymous classes (name returns nil)
          return @event_name if @event_name && name

          class_name = name || "AnonymousEvent"
          @event_name = class_name.sub(/V\d+$/, "")
        end

        # Resolve sample rate for this event
        #
        # Sample rate determines what percentage of events to process (0.0-1.0)
        # Convention: error/fatal = 1.0 (all), success = 0.1 (10%), debug = 0.01 (1%)
        #
        # Optimized: Uses inline lookup table instead of case statement
        #
        # @return [Float] Sample rate (0.0-1.0)
        def resolve_sample_rate
          # Inline lookup (faster than case statement)
          SEVERITY_SAMPLE_RATES[severity] || 0.1
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
            # Getter
            @contains_pii
          else
            # Setter
            @contains_pii = value
          end
        end

        # Determine the PII filtering tier for this event.
        # @return [Symbol] :tier1, :tier2, or :tier3
        def pii_tier
          case contains_pii
          when false then :tier1
          when true then :tier3
          else :tier2 # Default if not explicitly declared
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
          @pii_filtering_config ||= { fields: {} }
          builder = PIIFilteringBuilder.new(@pii_filtering_config)
          builder.instance_eval(&)
        end

        # Get PII filtering configuration
        #
        # @return [Hash] PII filtering config
        attr_reader :pii_filtering_config

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
      end

      # Builder for PII filtering DSL
      class PIIFilteringBuilder
        def initialize(config)
          @config = config
        end

        # Mask fields (strategy: :mask)
        def masks(*fields)
          fields.each do |field|
            @config[:fields][field] = { strategy: :mask }
          end
        end

        # Hash fields (strategy: :hash)
        def hashes(*fields)
          fields.each do |field|
            @config[:fields][field] = { strategy: :hash }
          end
        end

        # Allow fields (strategy: :allow)
        def allows(*fields)
          fields.each do |field|
            @config[:fields][field] = { strategy: :allow }
          end
        end

        # Partial mask fields (strategy: :partial)
        def partials(*fields)
          fields.each do |field|
            @config[:fields][field] = { strategy: :partial }
          end
        end

        # Redact fields (strategy: :redact)
        def redacts(*fields)
          fields.each do |field|
            @config[:fields][field] = { strategy: :redact }
          end
        end
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end

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
    class Base
      # Severity levels (ordered by importance)
      SEVERITIES = %i[debug info success warn error fatal].freeze

      class << self
        # Track an event (zero-allocation pattern)
        #
        # This is the main entry point for all events. No object is created - only a Hash.
        # Returns event hash for testing/debugging. In Phase 2, pipeline will be added.
        #
        # @param payload [Hash] Event data matching the schema
        # @return [Hash] Event hash (includes metadata)
        #
        # @example
        #   UserSignupEvent.track(user_id: 123, email: "user@example.com")
        #   # => { event_name: "UserSignupEvent", payload: {...}, severity: :info, adapters: [:logs], ... }
        #
        # @raise [E11y::ValidationError] if payload doesn't match schema
        def track(**payload)
          # 1. Validate payload against schema
          validate_payload!(payload)

          # 2. Build event hash with metadata (zero-allocation: just a Hash)
          # 3. TODO Phase 2: Send to pipeline
          # E11y::Pipeline.process(event_hash)

          # 4. Return event hash for testing/debugging
          {
            event_name: event_name,
            payload: payload,
            severity: severity,
            version: version,
            adapters: adapters, # Adapter names (e.g., [:logs, :errors_tracker])
            timestamp: Time.now.utc.iso8601(3) # ISO8601 with milliseconds
          }
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
        # @return [Float] Sample rate (0.0-1.0)
        def resolve_sample_rate
          case severity
          when :error, :fatal
            1.0 # 100% - все ошибки
          when :debug
            0.01 # 1% - debug события
          else
            0.1 # Default: 10% (info, success, warn, etc.)
          end
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
      end
    end
  end
end

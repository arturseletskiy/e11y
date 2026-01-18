# frozen_string_literal: true

module E11y
  module Adapters
    # Base class for all E11y adapters
    #
    # Provides standard interface for event destinations following ADR-004.
    # All adapters must implement {#write} method, optionally override {#write_batch}
    # for performance optimization.
    #
    # @abstract Subclass and implement {#write}, optionally {#write_batch}
    #
    # @example Define custom adapter
    #   class CustomAdapter < E11y::Adapters::Base
    #     def initialize(config = {})
    #       super
    #       @url = config.fetch(:url)
    #       validate_config!
    #     end
    #
    #     def write(event_data)
    #       # Send single event to external system
    #       send_to_api(event_data)
    #       true
    #     rescue => e
    #       warn "Adapter error: #{e.message}"
    #       false
    #     end
    #
    #     def capabilities
    #       {
    #         batching: false,
    #         compression: false,
    #         async: false,
    #         streaming: false
    #       }
    #     end
    #
    #     private
    #
    #     def validate_config!
    #       raise ArgumentError, "url is required" unless @url
    #     end
    #   end
    #
    # @see ADR-004 Section 3.1 (Base Adapter Contract)
    class Base
      # Initialize adapter with config
      #
      # @param config [Hash] Adapter-specific configuration
      def initialize(config = {})
        @config = config
        validate_config!
      end

      # Write a single event (synchronous)
      #
      # Subclasses must implement this method to send events to external systems.
      # This method is called for each event when batching is not used.
      #
      # @param event_data [Hash] Event payload with keys:
      #   - :event_name [String] Event name (e.g., "order.paid")
      #   - :severity [Symbol] Severity level (:debug, :info, :success, :warn, :error, :fatal)
      #   - :timestamp [Time] Event timestamp
      #   - :payload [Hash] Event-specific data
      #   - :trace_id [String, nil] Trace ID (if tracing enabled)
      #   - :span_id [String, nil] Span ID (if tracing enabled)
      #
      # @return [Boolean] true on success, false on failure (failures should be logged)
      # @raise [NotImplementedError] if not overridden in subclass
      #
      # @example
      #   def write(event_data)
      #     send_to_api(event_data)
      #     true
      #   rescue => e
      #     warn "Adapter error: #{e.message}"
      #     false
      #   end
      def write(_event_data)
        raise NotImplementedError, "#{self.class}#write must be implemented"
      end

      # Write a batch of events (preferred for performance)
      #
      # Default implementation calls {#write} for each event.
      # Subclasses should override for better batch performance.
      #
      # @param events [Array<Hash>] Array of event payloads (same format as {#write})
      # @return [Boolean] true if all events written successfully, false otherwise
      #
      # @example Override for batch API
      #   def write_batch(events)
      #     send_batch_to_api(events)
      #     true
      #   rescue => e
      #     warn "Batch error: #{e.message}"
      #     false
      #   end
      def write_batch(events)
        # Default: call write for each event
        events.all? { |event| write(event) }
      end

      # Check if adapter is healthy
      #
      # Subclasses can override to implement health checks (e.g., ping destination).
      # Called periodically to determine if adapter can accept events.
      #
      # @return [Boolean] Health status (true = healthy, false = unhealthy)
      #
      # @example
      #   def healthy?
      #     ping_api
      #     true
      #   rescue
      #     false
      #   end
      def healthy?
        true
      end

      # Close connections, flush buffers
      #
      # Called during graceful shutdown. Subclasses should override to:
      # - Close HTTP connections
      # - Flush internal buffers
      # - Release resources
      #
      # @return [void]
      #
      # @example
      #   def close
      #     @buffer.flush! if @buffer.any?
      #     @connection.close
      #   end
      def close
        # Default: no-op
      end

      # Adapter capabilities
      #
      # Returns hash of capability flags. Subclasses should override to declare
      # supported features.
      #
      # @return [Hash] Capability flags with keys:
      #   - :batching [Boolean] Supports efficient batch writes
      #   - :compression [Boolean] Supports compression
      #   - :async [Boolean] Non-blocking writes
      #   - :streaming [Boolean] Supports streaming
      #
      # @example
      #   def capabilities
      #     {
      #       batching: true,
      #       compression: true,
      #       async: false,
      #       streaming: false
      #     }
      #   end
      def capabilities
        {
          batching: false,
          compression: false,
          async: false,
          streaming: false
        }
      end

      private

      # Validate adapter config
      #
      # Subclasses should override to validate configuration during initialization.
      # Raise ArgumentError for invalid config.
      #
      # @raise [ArgumentError] if configuration is invalid
      #
      # @example
      #   def validate_config!
      #     raise ArgumentError, "url is required" unless @config[:url]
      #   end
      def validate_config!
        # Default: no validation
      end

      # Format event for this adapter
      #
      # Subclasses can override to transform event_data to adapter-specific format.
      #
      # @param event_data [Hash] Event payload
      # @return [Hash, String] Formatted event
      #
      # @example
      #   def format_event(event_data)
      #     {
      #       timestamp: event_data[:timestamp].iso8601,
      #       message: event_data[:event_name],
      #       level: event_data[:severity]
      #     }
      #   end
      def format_event(event_data)
        event_data
      end
    end
  end
end

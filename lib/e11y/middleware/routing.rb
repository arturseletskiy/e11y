# frozen_string_literal: true

module E11y
  module Middleware
    # Routing middleware routes events to appropriate buffers/adapters.
    #
    # This is the FINAL middleware in the pipeline (adapters zone),
    # running AFTER all processing (TraceContext, Validation, PII Filtering,
    # Rate Limiting, Sampling, Versioning).
    #
    # **Phase 1 Implementation:**
    # - Determines target adapters from event configuration
    # - Logs routing decisions for debugging
    # - Increments metrics for observability
    # - Does NOT actually send events (Phase 2: Collector will handle delivery)
    #
    # **Routing Logic:**
    # 1. Get adapters from event_data[:adapters] (configured in Event class)
    # 2. Determine buffer type based on severity/flags
    # 3. Log/metric routing decision
    # 4. Pass event_data to next app (Collector in Phase 2)
    #
    # @see ADR-015 §3.1 Pipeline Flow (line 113-117)
    # @see ADR-001 §3 Adapter Architecture
    # @see UC-001 Request-Scoped Debug Buffering
    #
    # @example Standard event routing
    #   event_data = {
    #     event_name: 'Events::OrderPaid',
    #     severity: :info,
    #     adapters: [:logs, :errors_tracker],
    #     payload: { ... }
    #   }
    #
    #   # Routes to: main buffer → [:logs, :errors_tracker] adapters
    #
    # @example Debug event routing (request-scoped)
    #   event_data = {
    #     event_name: 'Events::DebugInfo',
    #     severity: :debug,
    #     adapters: [:logs],
    #     payload: { ... }
    #   }
    #
    #   # Routes to: request-scoped buffer (buffered, flushed on error)
    #
    # @example Audit event routing
    #   event_data = {
    #     event_name: 'Events::PermissionChanged',
    #     severity: :warn,
    #     audit_event: true,
    #     adapters: [:audit_encrypted],
    #     payload: { ... }
    #   }
    #
    #   # Routes to: audit buffer → [:audit_encrypted] adapter
    class Routing < Base
      middleware_zone :adapters

      # Routes event to appropriate buffer/adapters.
      #
      # @param event_data [Hash] The event data to route
      # @option event_data [Array<Symbol>] :adapters Target adapter names (required)
      # @option event_data [Symbol] :severity Event severity (required)
      # @option event_data [Boolean] :audit_event Audit event flag (optional)
      # @return [Hash, nil] Event data (passed to Collector in Phase 2), or nil if dropped
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      def call(event_data)
        # Skip if no adapters or severity
        unless event_data[:adapters] && event_data[:severity]
          increment_metric("e11y.middleware.routing.skipped")
          return @app.call(event_data)
        end

        adapters = event_data[:adapters]
        severity = event_data[:severity]
        audit_event = event_data[:audit_event] || false

        # Determine buffer type
        buffer_type = determine_buffer_type(severity, audit_event)

        # Add routing metadata to event_data
        event_data[:routing] = {
          buffer_type: buffer_type,
          adapters: adapters,
          routed_at: Time.now.utc
        }

        # Increment metrics
        increment_metric("e11y.middleware.routing.routed",
                         buffer: buffer_type,
                         severity: severity,
                         adapters_count: adapters.size)

        # Log routing decision (for Phase 1 debugging)
        log_routing_decision(event_data, buffer_type, adapters) if debug_enabled?

        # Pass to next app (Collector in Phase 2)
        @app.call(event_data)
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      private

      # Determine which buffer type to use based on severity and flags.
      #
      # @param severity [Symbol] Event severity
      # @param audit_event [Boolean] Audit event flag
      # @return [Symbol] Buffer type (:main, :request_scoped, :audit)
      #
      # Routing rules:
      # - Audit events → :audit buffer (separate pipeline, no PII filtering)
      # - Debug events → :request_scoped buffer (buffered, flushed on error)
      # - Other events → :main buffer (immediate sending)
      def determine_buffer_type(severity, audit_event)
        return :audit if audit_event
        return :request_scoped if severity == :debug

        :main
      end

      # Log routing decision for debugging (Phase 1).
      #
      # @param event_data [Hash] Event data
      # @param buffer_type [Symbol] Determined buffer type
      # @param adapters [Array<Symbol>] Target adapters
      # @return [void]
      def log_routing_decision(event_data, buffer_type, adapters)
        # TODO: Replace with structured logging in Phase 2
        # Rails.logger.debug "[E11y] Routing: #{event_data[:event_name]} → #{buffer_type} → #{adapters.inspect}"
      end

      # Check if debug logging is enabled.
      #
      # @return [Boolean]
      def debug_enabled?
        # TODO: Read from configuration in Phase 2
        # E11y.configuration.debug_enabled
        false # Disabled in Phase 1
      end

      # Placeholder for metrics instrumentation.
      #
      # @param metric_name [String] Metric name
      # @param tags [Hash] Metric tags
      # @return [void]
      def increment_metric(_metric_name, **_tags)
        # TODO: Integrate with Yabeda/Prometheus in Phase 2
        # Yabeda.e11y.middleware_routing_routed.increment(
        #   buffer: buffer,
        #   severity: severity,
        #   adapters_count: adapters_count
        # )
      end
    end
  end
end

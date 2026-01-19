# frozen_string_literal: true

require "securerandom"
require "time"

module E11y
  module Middleware
    # TraceContext middleware adds distributed tracing metadata to all events.
    #
    # This is the FIRST middleware in the pipeline (pre-processing zone),
    # ensuring every event has tracing context for correlation across services.
    #
    # @see ADR-015 §3.1 Pipeline Flow
    # @see ADR-005 Tracing Context Management
    # @see UC-006 Trace Context Management
    # @see UC-009 Multi-Service Tracing
    #
    # @example Automatic tracing metadata
    #   Events::OrderPaid.track(order_id: 123)
    #
    #   # Event data after TraceContext middleware:
    #   {
    #     event_name: 'Events::OrderPaid',
    #     payload: { order_id: 123 },
    #     trace_id: 'a1b2c3d4e5f6g7h8',       # 32-char hex
    #     span_id: 'i9j0k1l2',                 # 16-char hex
    #     timestamp: '2026-01-17T12:34:56.789Z' # ISO8601
    #   }
    #
    # @example Request-scoped tracing (propagation)
    #   # In Rails controller/middleware:
    #   Thread.current[:e11y_trace_id] = request.headers['X-Trace-ID']
    #
    #   Events::OrderPaid.track(order_id: 123)
    #   # Uses propagated trace_id from thread-local storage
    #
    # @example Manual trace_id injection
    #   Events::OrderPaid.track(order_id: 123, trace_id: 'custom-trace-id')
    #   # Manual trace_id preserved (not overridden)
    class TraceContext < Base
      middleware_zone :pre_processing

      # Adds tracing metadata to event data.
      #
      # **Hybrid Tracing (C17 Resolution)**:
      # - trace_id: Current trace (from E11y::Current or generated)
      # - span_id: Always new for each event
      # - parent_trace_id: Link to parent trace (for background jobs)
      #
      # @param event_data [Hash] The event data to enrich
      # @option event_data [String] :trace_id Existing trace ID (optional)
      # @option event_data [String] :span_id Existing span ID (optional)
      # @option event_data [String] :parent_trace_id Parent trace ID (optional)
      # @option event_data [Time,String] :timestamp Existing timestamp (optional)
      # @return [Hash, nil] Enriched event data, or nil if dropped
      def call(event_data)
        # Add trace_id (propagate from E11y::Current or Thread.current or generate new)
        event_data[:trace_id] ||= current_trace_id || generate_trace_id

        # Add span_id (always generate new for this event)
        event_data[:span_id] ||= generate_span_id

        # Add parent_trace_id (if job has parent trace) - C17 Resolution
        event_data[:parent_trace_id] ||= current_parent_trace_id if current_parent_trace_id

        # Add timestamp (use existing or current time)
        event_data[:timestamp] ||= format_timestamp(Time.now.utc)

        # Increment metrics
        increment_metric("e11y.middleware.trace_context.processed")

        @app.call(event_data)
      end

      private

      # Get current trace ID from E11y::Current or thread-local storage (request context).
      #
      # Priority: E11y::Current > Thread.current
      #
      # @return [String, nil] Current trace ID if set, nil otherwise
      def current_trace_id
        E11y::Current.trace_id || Thread.current[:e11y_trace_id]
      end

      # Get current parent trace ID from E11y::Current (background job context).
      #
      # Only set for background jobs that have a parent request trace.
      #
      # @return [String, nil] Parent trace ID if set, nil otherwise
      def current_parent_trace_id
        E11y::Current.parent_trace_id
      end

      # Generate a new trace ID (32-character hexadecimal).
      #
      # Compatible with OpenTelemetry trace_id format (16 bytes = 32 hex chars).
      #
      # @return [String] New trace ID
      def generate_trace_id
        SecureRandom.hex(16) # 32 chars
      end

      # Generate a new span ID (16-character hexadecimal).
      #
      # Compatible with OpenTelemetry span_id format (8 bytes = 16 hex chars).
      #
      # @return [String] New span ID
      def generate_span_id
        SecureRandom.hex(8) # 16 chars
      end

      # Format timestamp to ISO8601 with millisecond precision.
      #
      # @param time [Time] Time object to format
      # @return [String] ISO8601 formatted timestamp (e.g., "2026-01-17T12:34:56.789Z")
      def format_timestamp(time)
        time.utc.iso8601(3)
      end

      # Placeholder for metrics instrumentation.
      #
      # @param metric_name [String] Metric name
      # @return [void]
      def increment_metric(_metric_name)
        # TODO: Integrate with Yabeda/Prometheus in Phase 2
        # Yabeda.e11y.middleware_trace_context_processed.increment
      end
    end
  end
end

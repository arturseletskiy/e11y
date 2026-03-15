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
        enrich_trace_context(event_data)
        enrich_service_context(event_data)
        E11y::Metrics.increment("e11y.middleware.trace_context.processed")
        @app.call(event_data)
      end

      private

      # rubocop:disable Metrics/AbcSize
      # Add distributed tracing fields to event data
      # @param event_data [Hash] Event data to enrich
      # @return [void]
      def enrich_trace_context(event_data)
        event_data[:trace_id] ||= current_trace_id || generate_trace_id
        event_data[:span_id] ||= current_span_id || generate_span_id
        event_data[:parent_trace_id] ||= current_parent_trace_id if current_parent_trace_id

        # Format timestamp if it's a Time object
        timestamp = event_data[:timestamp]
        event_data[:timestamp] = if timestamp.is_a?(Time)
                                   format_timestamp(timestamp)
                                 else
                                   timestamp || format_timestamp(Time.now.utc)
                                 end

        # Calculate retention_until from retention_period
        if event_data[:retention_period] && !event_data[:retention_until]
          # Parse timestamp back to Time to calculate retention_until
          base_time = timestamp.is_a?(Time) ? timestamp : Time.parse(event_data[:timestamp])
          retention_time = base_time + event_data[:retention_period]
          event_data[:retention_until] = retention_time.iso8601
        end

        # Add audit_event flag
        event_class = event_data[:event_class]
        return unless event_class.respond_to?(:audit_event?)

        event_data[:audit_event] = event_class.audit_event?
      end
      # rubocop:enable Metrics/AbcSize

      # Add service context fields to event data
      # @param event_data [Hash] Event data to enrich
      # @return [void]
      def enrich_service_context(event_data)
        event_data[:service_name] ||= E11y.config.service_name
        event_data[:environment] ||= E11y.config.environment
      end

      # Get current trace ID from configured source (ADR-007 §8).
      #
      # When config.tracing.source is :opentelemetry and OTel SDK has an active span,
      # uses trace_id from OpenTelemetry::Trace.current_span.
      # Otherwise: E11y::Current > Thread.current
      #
      # @return [String, nil] Current trace ID if set, nil otherwise
      def current_trace_id
        if tracing_source_opentelemetry?
          otel = otel_trace_context
          return otel[:trace_id] if otel[:trace_id]
        end
        E11y::Current.trace_id || Thread.current[:e11y_trace_id]
      end

      # Get current span ID (for event correlation).
      # When using OTel source and span exists, returns OTel span_id; otherwise nil (caller generates).
      #
      # @return [String, nil]
      def current_span_id
        return nil unless tracing_source_opentelemetry?

        otel = otel_trace_context
        otel[:span_id]
      end

      def tracing_source_opentelemetry?
        E11y.config&.tracing&.source == :opentelemetry
      end

      def otel_trace_context
        return {} unless defined?(OpenTelemetry::Trace)

        span = OpenTelemetry::Trace.current_span
        ctx = span.context
        return {} unless ctx.respond_to?(:valid?) && ctx.valid?

        trace_id = ctx.respond_to?(:hex_trace_id) ? ctx.hex_trace_id : nil
        span_id = ctx.respond_to?(:hex_span_id) ? ctx.hex_span_id : nil
        return {} if trace_id.to_s.empty?

        # Sync to E11y::Current so downstream uses same context
        E11y::Current.trace_id = trace_id
        E11y::Current.span_id = span_id

        { trace_id: trace_id, span_id: span_id }
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
    end
  end
end

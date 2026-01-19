# frozen_string_literal: true

require "e11y/metrics"

module E11y
  module SelfMonitoring
    # Performance monitoring for E11y internal operations.
    #
    # Tracks latency metrics for:
    # - Event tracking (E11y.track)
    # - Middleware execution
    # - Adapter writes
    # - Buffer flushes
    #
    # @see ADR-016 §3.1 (Performance Metrics)
    # @example
    #   E11y::SelfMonitoring::PerformanceMonitor.track_latency(0.5, event_class: 'OrderCreated', severity: :info)
    module PerformanceMonitor
      # Track E11y.track() latency.
      #
      # @param duration_ms [Numeric] Duration in milliseconds
      # @param event_class [String] Event class name
      # @param severity [Symbol] Event severity
      # @return [void]
      def self.track_latency(duration_ms, event_class:, severity:)
        E11y::Metrics.histogram(
          :e11y_track_duration_seconds,
          duration_ms / 1000.0,
          {
            event_class: event_class,
            severity: severity
          },
          buckets: [0.0001, 0.0005, 0.001, 0.005, 0.01, 0.05, 0.1] # 0.1ms to 100ms
        )
      end

      # Track middleware execution time.
      #
      # @param middleware_name [String] Middleware class name
      # @param duration_ms [Numeric] Duration in milliseconds
      # @return [void]
      def self.track_middleware_latency(middleware_name, duration_ms)
        E11y::Metrics.histogram(
          :e11y_middleware_duration_seconds,
          duration_ms / 1000.0,
          { middleware: middleware_name },
          buckets: [0.00001, 0.0001, 0.0005, 0.001, 0.005] # 0.01ms to 5ms
        )
      end

      # Track adapter send latency.
      #
      # @param adapter_name [String] Adapter class name
      # @param duration_ms [Numeric] Duration in milliseconds
      # @return [void]
      def self.track_adapter_latency(adapter_name, duration_ms)
        E11y::Metrics.histogram(
          :e11y_adapter_send_duration_seconds,
          duration_ms / 1000.0,
          { adapter: adapter_name },
          buckets: [0.001, 0.01, 0.05, 0.1, 0.5, 1.0, 5.0] # 1ms to 5s
        )
      end

      # Track buffer flush latency.
      #
      # @param duration_ms [Numeric] Duration in milliseconds
      # @param event_count [Integer] Number of events flushed
      # @return [void]
      def self.track_flush_latency(duration_ms, event_count)
        E11y::Metrics.histogram(
          :e11y_buffer_flush_duration_seconds,
          duration_ms / 1000.0,
          { event_count_bucket: bucket_event_count(event_count) },
          buckets: [0.001, 0.01, 0.05, 0.1, 0.5, 1.0]
        )
      end

      # Convert event count to a low-cardinality bucket label.
      #
      # @param count [Integer] Event count
      # @return [String] Bucket label
      # @api private
      def self.bucket_event_count(count)
        case count
        when 0..10 then "1-10"
        when 11..50 then "11-50"
        when 51..100 then "51-100"
        when 101..500 then "101-500"
        else "500+"
        end
      end

      private_class_method :bucket_event_count
    end
  end
end

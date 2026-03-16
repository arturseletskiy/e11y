# frozen_string_literal: true

require "e11y/metrics"

module E11y
  module SelfMonitoring
    # Performance monitoring for E11y internal operations.
    #
    # Tracks:
    # - Event.track() latency (via TrackLatency middleware)
    # - Adapter send latency (used by Base adapter)
    #
    # @see ADR-016 §3.1 (Performance Metrics)
    # @example
    #   E11y::SelfMonitoring::PerformanceMonitor.track_latency(0.5, event_class: 'Events::OrderPaid', severity: 'info', result: :success)
    #   E11y::SelfMonitoring::PerformanceMonitor.track_adapter_latency('E11y::Adapters::Loki', 42)
    module PerformanceMonitor
      # Track Event.track() pipeline latency (from entry to exit).
      #
      # @param duration_ms [Numeric] Duration in milliseconds
      # @param event_class [String] Event class name (e.g. 'Events::OrderPaid')
      # @param severity [String] Severity (e.g. 'info', 'error')
      # @param result [Symbol] :success or :dropped
      # @return [void]
      def self.track_latency(duration_ms, event_class:, severity:, result:)
        E11y::Metrics.histogram(
          :e11y_track_duration_seconds,
          duration_ms / 1000.0,
          { event_class: event_class, severity: severity, result: result.to_s },
          buckets: [0.0001, 0.0005, 0.001, 0.005, 0.01, 0.05, 0.1] # 0.1ms to 100ms
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
    end
  end
end

# frozen_string_literal: true

require "e11y/metrics"

module E11y
  module SelfMonitoring
    # Performance monitoring for E11y internal operations.
    #
    # Tracks adapter send latency (used by Base adapter).
    #
    # @see ADR-016 §3.1 (Performance Metrics)
    # @example
    #   E11y::SelfMonitoring::PerformanceMonitor.track_adapter_latency('E11y::Adapters::Loki', 42)
    module PerformanceMonitor
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

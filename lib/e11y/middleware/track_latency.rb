# frozen_string_literal: true

module E11y
  module Middleware
    # Measures Event.track() latency from pipeline entry to exit.
    #
    # Must be the FIRST middleware so it wraps the entire pipeline.
    # Records duration for both success and dropped events.
    #
    # @see ADR-016 §3.1 (Performance Metrics)
    # @example Add first in pipeline
    #   config.pipeline.use E11y::Middleware::TrackLatency
    #   config.pipeline.use E11y::Middleware::TraceContext
    #   # ...
    class TrackLatency < Base
      middleware_zone :pre_processing

      def call(event_data)
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = @app.call(event_data)
        duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000

        E11y::SelfMonitoring::PerformanceMonitor.track_latency(
          duration_ms,
          event_class: event_data[:event_name].to_s,
          severity: event_data[:severity].to_s,
          result: result.nil? ? :dropped : :success
        )

        result
      end
    end
  end
end

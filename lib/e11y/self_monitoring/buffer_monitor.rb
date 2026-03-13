# frozen_string_literal: true

require "e11y/metrics"

module E11y
  module SelfMonitoring
    # NOTE: Not wired to buffer components. Methods are API for future use.
    #
    # Buffer monitoring for E11y internal operations.
    #
    # Tracks buffer metrics:
    # - Buffer size (current utilization)
    # - Buffer overflows
    # - Buffer flushes
    #
    # @see ADR-016 §3.3 (Buffer Metrics)
    # @example
    #   E11y::SelfMonitoring::BufferMonitor.track_buffer_size(42, buffer_type: 'ring')
    module BufferMonitor
      # Track current buffer size.
      #
      # @param size [Integer] Current number of events in buffer
      # @param buffer_type [String] Buffer type (e.g., 'ring', 'request_scoped')
      # @return [void]
      def self.track_buffer_size(size, buffer_type:)
        E11y::Metrics.gauge(
          :e11y_buffer_size,
          size,
          { buffer_type: buffer_type }
        )
      end

      # Track buffer overflow (event dropped due to full buffer).
      #
      # @param buffer_type [String] Buffer type
      # @return [void]
      def self.track_buffer_overflow(buffer_type:)
        E11y::Metrics.increment(
          :e11y_buffer_overflows_total,
          { buffer_type: buffer_type }
        )
      end

      # Track buffer flush operation.
      #
      # @param buffer_type [String] Buffer type
      # @param event_count [Integer] Number of events flushed
      # @param trigger [String] Flush trigger (e.g., 'size', 'timeout', 'explicit')
      # @return [void]
      def self.track_buffer_flush(buffer_type:, event_count:, trigger:)
        E11y::Metrics.increment(
          :e11y_buffer_flushes_total,
          {
            buffer_type: buffer_type,
            trigger: trigger
          }
        )

        E11y::Metrics.histogram(
          :e11y_buffer_flush_events_count,
          event_count,
          { buffer_type: buffer_type },
          buckets: [1, 10, 50, 100, 500, 1000, 5000]
        )
      end

      # Track buffer utilization (percentage).
      #
      # @param utilization_percent [Numeric] Buffer utilization percentage (0-100)
      # @param buffer_type [String] Buffer type
      # @return [void]
      def self.track_buffer_utilization(utilization_percent, buffer_type:)
        E11y::Metrics.gauge(
          :e11y_buffer_utilization_percent,
          utilization_percent,
          { buffer_type: buffer_type }
        )
      end
    end
  end
end

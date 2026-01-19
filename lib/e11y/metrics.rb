# frozen_string_literal: true

require "e11y/metrics/registry"
require "e11y/metrics/cardinality_protection"

module E11y
  # Public API for tracking metrics.
  #
  # This is a facade that delegates to the configured metrics backend (e.g., Yabeda).
  # If no backend is configured, metrics are silently discarded (noop).
  #
  # @example Track a counter
  #   E11y::Metrics.increment(:http_requests_total, { method: 'GET', status: 200 })
  #
  # @example Track a histogram
  #   E11y::Metrics.histogram(:http_request_duration_seconds, 0.042, { method: 'GET' })
  #
  # @example Track a gauge
  #   E11y::Metrics.gauge(:active_connections, 42, { server: 'web-01' })
  #
  # @see ADR-002 §3 (Metrics Integration)
  # @see ADR-016 §3 (Self-Monitoring Metrics)
  module Metrics
    class << self
      # Track a counter metric (monotonically increasing value).
      #
      # @param name [Symbol] Metric name (e.g., :http_requests_total)
      # @param labels [Hash] Metric labels (e.g., { method: 'GET', status: 200 })
      # @param value [Integer] Increment value (default: 1)
      # @return [void]
      #
      # @example
      #   E11y::Metrics.increment(:e11y_events_tracked, { event_type: 'order.created' })
      def increment(name, labels = {}, value: 1)
        backend&.increment(name, labels, value: value)
      end

      # Track a histogram metric (distribution of values).
      #
      # @param name [Symbol] Metric name (e.g., :http_request_duration_seconds)
      # @param value [Numeric] Observed value (e.g., 0.042 for 42ms)
      # @param labels [Hash] Metric labels (e.g., { method: 'GET' })
      # @param buckets [Array<Numeric>, nil] Optional histogram buckets (for backend config)
      # @return [void]
      #
      # @example
      #   E11y::Metrics.histogram(:e11y_track_duration_seconds, 0.0005, { event_type: 'order.created' })
      def histogram(name, value, labels = {}, buckets: nil)
        backend&.histogram(name, value, labels, buckets: buckets)
      end

      # Track a gauge metric (current value that can go up or down).
      #
      # @param name [Symbol] Metric name (e.g., :active_connections)
      # @param value [Numeric] Current value (e.g., 42)
      # @param labels [Hash] Metric labels (e.g., { server: 'web-01' })
      # @return [void]
      #
      # @example
      #   E11y::Metrics.gauge(:e11y_buffer_size, 128, { buffer_type: 'ring' })
      def gauge(name, value, labels = {})
        backend&.gauge(name, value, labels)
      end

      # Get the configured metrics backend.
      #
      # The backend is determined by checking for configured adapters:
      # - If Yabeda adapter is configured, use it
      # - Otherwise, return nil (noop)
      #
      # @return [Object, nil] Metrics backend or nil
      # @api private
      def backend
        return @backend if defined?(@backend)

        @backend = detect_backend
      end

      # Reset the backend (useful for testing).
      #
      # @api private
      def reset_backend!
        remove_instance_variable(:@backend) if defined?(@backend)
      end

      private

      # Detect the metrics backend from configured adapters.
      #
      # @return [Object, nil] Metrics backend or nil
      def detect_backend
        # Check if Yabeda adapter is configured
        # Use class name string to avoid LoadError if Yabeda gem not installed
        yabeda_adapter = E11y.config.adapters.values.find { |adapter| adapter.class.name == "E11y::Adapters::Yabeda" }
        return yabeda_adapter if yabeda_adapter

        # No backend configured → noop
        nil
      end
    end
  end
end

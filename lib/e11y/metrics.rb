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
    # No-op metrics backend used when no real backend (e.g. Yabeda) is configured.
    # Accepts all metric calls and silently discards them so callers never
    # need to guard against a nil backend.
    class NullBackend
      def increment(_name, _labels = {}, value: 1); end
      def histogram(_name, _value, _labels = {}, buckets: nil); end
      def gauge(_name, _value, _labels = {}); end
    end

    class << self
      # Track a counter metric (monotonically increasing value).
      #
      # Accepts dotted names (e.g., "e11y.ephemeral_buffer.flushed") and normalizes to
      # underscores. DLQ metrics get _total suffix. Labels[:events] is used as value if present.
      # Safe: no-op when backend unavailable, rescues errors.
      #
      # @param name [Symbol, String] Metric name (e.g., :http_requests_total or "e11y.ephemeral_buffer.flushed")
      # @param labels [Hash] Metric labels (e.g., { method: 'GET', status: 200 })
      # @param value [Integer] Increment value (default: 1, overridden by labels[:events] if present)
      # @return [void]
      #
      # @example
      #   E11y::Metrics.increment(:e11y_events_tracked, event_type: 'order.created')
      #   E11y::Metrics.increment("e11y.ephemeral_buffer.flushed_on_error", value: 5)
      def increment(name, labels = {}, value: 1, **labels_kw)
        return unless backend

        labels = labels.merge(labels_kw) unless labels_kw.empty?
        value = labels.delete(:events) if labels.key?(:events)
        value ||= 1

        normalized = normalized_metric_name(name)
        backend.increment(normalized, labels, value: value)
      rescue StandardError => e
        E11y.logger&.debug("E11y metrics: #{e.message}")
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
      #   E11y::Metrics.histogram(:e11y_track_duration_seconds, 0.0005, event_type: 'order.created')
      def histogram(name, value, labels = {}, buckets: nil, **labels_kw)
        return unless backend

        labels = labels.merge(labels_kw) unless labels_kw.empty?
        normalized = normalized_metric_name(name)
        backend.histogram(normalized, value, labels, buckets: buckets)
      rescue StandardError => e
        E11y.logger&.debug("E11y metrics: #{e.message}")
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
        @name_cache = nil if defined?(@name_cache)
      end

      private

      # Normalize metric name: dots to underscores, DLQ metrics get _total suffix.
      # Cached to avoid repeated string allocations for hot-path metrics.
      #
      # @param name [Symbol, String] Raw metric name
      # @return [Symbol] Normalized name for Prometheus (e.g., e11y_ephemeral_buffer_flushed_on_error)
      def normalized_metric_name(name)
        @name_cache ||= {}
        @name_cache[name] ||= compute_normalized_name(name)
      end

      def compute_normalized_name(name)
        s = name.to_s.tr(".", "_")
        s = "#{s}_total" if s.include?("e11y_dlq_") && !s.end_with?("_total")
        s.to_sym
      end

      # Detect the metrics backend from configured adapters.
      #
      # @return [Object, nil] Metrics backend or nil
      def detect_backend
        # Check if Yabeda adapter is configured
        # Use class name string to avoid LoadError if Yabeda gem not installed
        # rubocop:disable Style/ClassEqualityComparison
        # Reason: instance_of?(::E11y::Adapters::Yabeda) would trigger LoadError when gem not installed
        yabeda_adapter = E11y.config.adapters.values.find do |adapter|
          adapter.class.name == "E11y::Adapters::Yabeda"
        end
        # rubocop:enable Style/ClassEqualityComparison
        return yabeda_adapter if yabeda_adapter

        # No Yabeda adapter configured — fall back to NullBackend
        NullBackend.new
      end
    end
  end
end

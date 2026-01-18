# frozen_string_literal: true

module E11y
  module Metrics
    # Cardinality protection for metrics labels.
    #
    # Implements 3-layer defense system to prevent cardinality explosions:
    # 1. Universal Denylist - Block high-cardinality fields (user_id, order_id, etc.)
    # 2. Per-Metric Limits - Track unique values per metric, drop if exceeded
    # 3. Dynamic Monitoring - Alert when approaching limits
    #
    # @example Basic usage
    #   protection = E11y::Metrics::CardinalityProtection.new
    #   labels = { user_id: '123', status: 'paid', currency: 'USD' }
    #   safe_labels = protection.filter(labels, 'orders.total')
    #   # => { status: 'paid', currency: 'USD' } (user_id dropped)
    #
    # @see ADR-002 §4 (Cardinality Protection)
    # @see UC-013 (High Cardinality Protection)
    class CardinalityProtection
      # Universal denylist - high-cardinality fields that should NEVER be labels
      UNIVERSAL_DENYLIST = %i[
        id
        user_id
        order_id
        session_id
        request_id
        trace_id
        span_id
        email
        phone
        ip_address
        token
        api_key
        password
        uuid
        guid
        timestamp
        created_at
        updated_at
      ].freeze

      # Default per-metric cardinality limit
      DEFAULT_CARDINALITY_LIMIT = 1000

      # Initialize cardinality protection
      # @param config [Hash] Configuration options
      # @option config [Integer] :cardinality_limit (1000) Max unique label combinations per metric
      # @option config [Array<Symbol>] :additional_denylist Additional fields to deny
      # @option config [Boolean] :enabled (true) Enable/disable protection
      def initialize(config = {})
        @cardinality_limit = config.fetch(:cardinality_limit, DEFAULT_CARDINALITY_LIMIT)
        @enabled = config.fetch(:enabled, true)
        @denylist = Set.new(UNIVERSAL_DENYLIST + (config[:additional_denylist] || []))
        @cardinality_tracker = Hash.new { |h, k| h[k] = Set.new }
        @mutex = Mutex.new
      end

      # Filter labels to prevent cardinality explosions
      # @param labels [Hash] Raw labels from event
      # @param metric_name [String] Metric name for tracking
      # @return [Hash] Filtered safe labels
      def filter(labels, metric_name)
        return labels unless @enabled

        safe_labels = {}

        labels.each do |key, value|
          # Layer 1: Denylist - drop high-cardinality fields
          next if should_deny?(key)

          # Layer 2: Per-Metric Cardinality Limit
          if within_cardinality_limit?(metric_name, key, value)
            safe_labels[key] = value
          else
            # Layer 3: Alert when limit exceeded
            warn_cardinality_exceeded(metric_name, key)
          end
        end

        safe_labels
      end

      # Check if cardinality limit is exceeded for a metric
      # @param metric_name [String] Metric name
      # @return [Boolean] True if limit exceeded
      def cardinality_exceeded?(metric_name)
        @mutex.synchronize do
          @cardinality_tracker[metric_name].size >= @cardinality_limit
        end
      end

      # Get current cardinality for a metric
      # @param metric_name [String] Metric name
      # @return [Integer] Number of unique label combinations
      def cardinality(metric_name)
        @mutex.synchronize do
          @cardinality_tracker[metric_name].size
        end
      end

      # Get all metrics with their cardinalities
      # @return [Hash<String, Integer>] Metric name => cardinality
      def cardinalities
        @mutex.synchronize do
          @cardinality_tracker.each_with_object({}) do |(key, values), result|
            result[key] = values.size if values.any?
          end
        end
      end

      # Reset cardinality tracking (for testing)
      # @return [void]
      def reset!
        @mutex.synchronize do
          @cardinality_tracker = Hash.new { |h, k| h[k] = Set.new }
        end
      end

      private

      # Check if label should be denied (Layer 1: Denylist)
      # @param key [Symbol] Label key
      # @return [Boolean] True if should be denied
      def should_deny?(key)
        @denylist.include?(key)
      end

      # Check if adding this label value would exceed cardinality limit (Layer 2)
      # @param metric_name [String] Metric name
      # @param key [Symbol] Label key
      # @param value [String] Label value
      # @return [Boolean] True if within limit
      def within_cardinality_limit?(metric_name, key, value)
        @mutex.synchronize do
          tracker_key = "#{metric_name}:#{key}"
          current_values = @cardinality_tracker[tracker_key]

          # If value already exists, it's safe
          return true if current_values.include?(value)

          # If adding would exceed limit, deny
          return false if current_values.size >= @cardinality_limit

          # Track new value
          current_values.add(value)
          true
        end
      end

      # Warn about cardinality limit exceeded (Layer 3: Monitoring)
      # @param metric_name [String] Metric name
      # @param key [Symbol] Label key
      def warn_cardinality_exceeded(metric_name, key)
        warn "E11y Metrics: Cardinality limit exceeded for #{metric_name}:#{key} (limit: #{@cardinality_limit})"
      end
    end
  end
end

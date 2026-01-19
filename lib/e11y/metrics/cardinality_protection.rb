# frozen_string_literal: true

require_relative "cardinality_tracker"
require_relative "relabeling"

module E11y
  module Metrics
    # Cardinality protection for metrics labels.
    #
    # Implements 3-layer defense system to prevent cardinality explosions:
    # 1. Universal Denylist - Block high-cardinality fields (user_id, order_id, etc.)
    # 2. Per-Metric Limits - Track unique values per metric, drop if exceeded
    # 3. Dynamic Monitoring - Alert when approaching limits
    #
    # Now supports optional relabeling to reduce cardinality while preserving signal.
    #
    # @example Basic usage
    #   protection = E11y::Metrics::CardinalityProtection.new
    #   labels = { user_id: '123', status: 'paid', currency: 'USD' }
    #   safe_labels = protection.filter(labels, 'orders.total')
    #   # => { status: 'paid', currency: 'USD' } (user_id dropped)
    #
    # @example With relabeling
    #   protection = E11y::Metrics::CardinalityProtection.new
    #   protection.relabel(:http_status) { |v| "#{v.to_i / 100}xx" }
    #   labels = { http_status: 200, path: '/api/users' }
    #   safe_labels = protection.filter(labels, 'http.requests')
    #   # => { http_status: '2xx', path: '/api/users' }
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

      attr_reader :tracker, :relabeler

      # Initialize cardinality protection
      # @param config [Hash] Configuration options
      # @option config [Integer] :cardinality_limit (1000) Max unique label combinations per metric
      # @option config [Array<Symbol>] :additional_denylist Additional fields to deny
      # @option config [Boolean] :enabled (true) Enable/disable protection
      # @option config [Boolean] :relabeling_enabled (true) Enable/disable relabeling
      def initialize(config = {})
        @cardinality_limit = config.fetch(:cardinality_limit, DEFAULT_CARDINALITY_LIMIT)
        @enabled = config.fetch(:enabled, true)
        @relabeling_enabled = config.fetch(:relabeling_enabled, true)
        @denylist = Set.new(UNIVERSAL_DENYLIST + (config[:additional_denylist] || []))

        # Use extracted components
        @tracker = CardinalityTracker.new(limit: @cardinality_limit)
        @relabeler = Relabeling.new
      end

      # Define relabeling rule for a label
      #
      # @param label_key [Symbol, String] Label key to relabel
      # @yield [value] Block that transforms label value
      # @return [void]
      #
      # @example HTTP status to class
      #   protection.relabel(:http_status) { |v| "#{v.to_i / 100}xx" }
      #
      # @example Path normalization
      #   protection.relabel(:path) { |v| v.gsub(/\/\d+/, '/:id') }
      def relabel(label_key, &)
        @relabeler.define(label_key, &)
      end

      # Filter labels to prevent cardinality explosions
      #
      # Applies 3-layer defense + optional relabeling:
      # 1. Relabel high-cardinality values (if enabled)
      # 2. Drop denylisted fields
      # 3. Track and limit per-metric cardinality
      # 4. Alert on limit exceeded
      #
      # @param labels [Hash] Raw labels from event
      # @param metric_name [String] Metric name for tracking
      # @return [Hash] Filtered safe labels
      def filter(labels, metric_name)
        return labels unless @enabled

        safe_labels = {}

        labels.each do |key, value|
          # Step 1: Relabel if rule exists (reduces cardinality)
          relabeled_value = @relabeling_enabled ? @relabeler.apply(key, value) : value

          # Step 2: Denylist - drop high-cardinality fields
          next if should_deny?(key)

          # Step 3: Per-Metric Cardinality Limit
          if @tracker.track(metric_name, key, relabeled_value)
            safe_labels[key] = relabeled_value
          else
            # Step 4: Alert when limit exceeded
            warn_cardinality_exceeded(metric_name, key)
          end
        end

        safe_labels
      end

      # Check if cardinality limit is exceeded for a metric
      # @param metric_name [String] Metric name
      # @return [Boolean] True if ANY label exceeded limit
      def cardinality_exceeded?(metric_name)
        # Check if any label has exceeded limit
        @tracker.cardinalities(metric_name).values.any? { |count| count >= @cardinality_limit }
      end

      # Get current cardinality for a metric (all labels)
      # @param metric_name [String] Metric name
      # @return [Hash{Symbol => Integer}] Label key => cardinality
      def cardinality(metric_name)
        @tracker.cardinalities(metric_name)
      end

      # Get all metrics with their cardinalities
      # @return [Hash{String => Hash{Symbol => Integer}}] Metric => Label => cardinality
      def cardinalities
        @tracker.all_cardinalities
      end

      # Reset cardinality tracking (for testing)
      # @return [void]
      def reset!
        @tracker.reset_all!
        @relabeler.reset!
      end

      private

      # Check if label should be denied (Layer 1: Denylist)
      # @param key [Symbol] Label key
      # @return [Boolean] True if should be denied
      def should_deny?(key)
        @denylist.include?(key)
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

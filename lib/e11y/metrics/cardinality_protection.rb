# frozen_string_literal: true

require_relative "cardinality_tracker"
require_relative "relabeling"

module E11y
  module Metrics
    # Cardinality protection for metrics labels.
    #
    # Implements 4-layer defense system to prevent cardinality explosions:
    # 1. Universal Denylist - Block high-cardinality fields (user_id, order_id, etc.)
    # 2. Per-Metric Limits - Track unique values per metric, drop if exceeded
    # 3. Dynamic Monitoring - Alert when approaching limits
    # 4. Dynamic Actions - Auto-relabeling, alerting, or dropping on overflow
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
    # @example With overflow strategy
    #   protection = E11y::Metrics::CardinalityProtection.new(
    #     overflow_strategy: :alert,
    #     alert_threshold: 0.8
    #   )
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

      # Overflow strategies (Layer 4: Dynamic Actions)
      OVERFLOW_STRATEGIES = %i[drop alert relabel].freeze

      # Default overflow strategy
      DEFAULT_OVERFLOW_STRATEGY = :drop

      # Default alert threshold (80% of limit)
      DEFAULT_ALERT_THRESHOLD = 0.8

      attr_reader :tracker, :relabeler, :overflow_strategy, :alert_threshold

      # Initialize cardinality protection
      # @param config [Hash] Configuration options
      # @option config [Integer] :cardinality_limit (1000) Max unique label combinations per metric
      # @option config [Array<Symbol>] :additional_denylist Additional fields to deny
      # @option config [Boolean] :enabled (true) Enable/disable protection
      # @option config [Boolean] :relabeling_enabled (true) Enable/disable relabeling
      # @option config [Symbol] :overflow_strategy (:drop) Strategy when limit exceeded (:drop, :alert, :relabel)
      # @option config [Float] :alert_threshold (0.8) Alert when cardinality reaches this ratio
      # @option config [Proc] :alert_callback Optional callback when alert triggered
      # @option config [Boolean] :auto_relabel (false) Auto-relabel to [OTHER] on overflow
      def initialize(config = {})
        @cardinality_limit = config.fetch(:cardinality_limit, DEFAULT_CARDINALITY_LIMIT)
        @enabled = config.fetch(:enabled, true)
        @relabeling_enabled = config.fetch(:relabeling_enabled, true)
        @denylist = Set.new(UNIVERSAL_DENYLIST + (config[:additional_denylist] || []))

        # Layer 4: Dynamic Actions configuration
        @overflow_strategy = config.fetch(:overflow_strategy, DEFAULT_OVERFLOW_STRATEGY)
        @alert_threshold = config.fetch(:alert_threshold, DEFAULT_ALERT_THRESHOLD)
        @alert_callback = config[:alert_callback]
        @auto_relabel = config.fetch(:auto_relabel, false)

        validate_config!

        # Use extracted components
        @tracker = CardinalityTracker.new(limit: @cardinality_limit)
        @relabeler = Relabeling.new

        # Track overflow metrics
        @overflow_counts = Hash.new(0)
        @overflow_mutex = Mutex.new
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
      # Applies 4-layer defense + optional relabeling:
      # 1. Relabel high-cardinality values (if enabled)
      # 2. Drop denylisted fields
      # 3. Track and limit per-metric cardinality
      # 4. Dynamic Actions on overflow (drop/alert/relabel)
      #
      # @param labels [Hash] Raw labels from event
      # @param metric_name [String] Metric name for tracking
      # @return [Hash] Filtered safe labels
      def filter(labels, metric_name)
        return labels unless @enabled

        safe_labels = {}

        labels.each do |key, value|
          # Layer 1: Relabel if rule exists (reduces cardinality)
          relabeled_value = @relabeling_enabled ? @relabeler.apply(key, value) : value

          # Layer 2: Denylist - drop high-cardinality fields
          next if should_deny?(key)

          # Layer 3: Per-Metric Cardinality Limit
          if @tracker.track(metric_name, key, relabeled_value)
            safe_labels[key] = relabeled_value
          else
            # Layer 4: Dynamic Actions on overflow
            handle_overflow(metric_name, key, relabeled_value, safe_labels)
          end
        end

        # Check if approaching alert threshold (after tracking new values)
        check_alert_threshold(metric_name)

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
        @overflow_mutex.synchronize do
          @overflow_counts.clear
        end
      end

      private

      # Validate configuration
      # @raise [ArgumentError] If configuration is invalid
      def validate_config!
        unless OVERFLOW_STRATEGIES.include?(@overflow_strategy)
          raise ArgumentError,
                "Invalid overflow_strategy: #{@overflow_strategy}. " \
                "Must be one of: #{OVERFLOW_STRATEGIES.join(', ')}"
        end

        unless @alert_threshold.is_a?(Numeric) && @alert_threshold.positive? && @alert_threshold <= 1.0
          raise ArgumentError,
                "Invalid alert_threshold: #{@alert_threshold}. " \
                "Must be a number between 0 and 1.0"
        end
      end

      # Check if label should be denied (Layer 1: Denylist)
      # @param key [Symbol] Label key
      # @return [Boolean] True if should be denied
      def should_deny?(key)
        @denylist.include?(key)
      end

      # Check if approaching alert threshold (Layer 3: Monitoring)
      # @param metric_name [String] Metric name
      def check_alert_threshold(metric_name)
        return unless @alert_threshold

        current_cardinality = @tracker.cardinalities(metric_name).values.sum
        ratio = current_cardinality.to_f / @cardinality_limit

        return unless ratio >= @alert_threshold

        # Only alert once per threshold crossing
        alert_key = "#{metric_name}:#{@alert_threshold}"
        return if @overflow_counts[alert_key].positive?

        @overflow_mutex.synchronize do
          @overflow_counts[alert_key] += 1
        end

        send_alert(
          metric_name: metric_name,
          message: "Cardinality approaching limit",
          current: current_cardinality,
          limit: @cardinality_limit,
          ratio: ratio,
          severity: :warn
        )

        # Track metric
        track_cardinality_metric(metric_name, :threshold_exceeded, current_cardinality)
      end

      # Handle overflow when cardinality limit exceeded (Layer 4: Dynamic Actions)
      # @param metric_name [String] Metric name
      # @param key [Symbol] Label key
      # @param value [Object] Label value
      # @param safe_labels [Hash] Current safe labels hash (may be modified)
      def handle_overflow(metric_name, key, value, safe_labels)
        # Increment overflow counter
        overflow_key = "#{metric_name}:#{key}"
        @overflow_mutex.synchronize do
          @overflow_counts[overflow_key] += 1
        end

        case @overflow_strategy
        when :drop
          handle_drop(metric_name, key, value)
        when :alert
          handle_alert(metric_name, key, value)
        when :relabel
          handle_relabel(metric_name, key, value, safe_labels)
        end

        # Track overflow metric
        track_cardinality_metric(metric_name, @overflow_strategy, @overflow_counts[overflow_key])
      end

      # Handle drop strategy - silently drop label
      # @param metric_name [String] Metric name
      # @param key [Symbol] Label key
      # @param value [Object] Label value
      def handle_drop(metric_name, key, value)
        # Silent drop (most efficient)
        # Optionally log at debug level
        if defined?(Rails) && Rails.logger.debug?
          Rails.logger.debug(
            "[E11y] Cardinality limit exceeded: #{metric_name}:#{key}=#{value} (dropped)"
          )
        end
      end

      # Handle alert strategy - alert ops team and drop
      # @param metric_name [String] Metric name
      # @param key [Symbol] Label key
      # @param value [Object] Label value
      def handle_alert(metric_name, key, value)
        current_cardinality = @tracker.cardinalities(metric_name)[key] || 0

        send_alert(
          metric_name: metric_name,
          label_key: key,
          label_value: value,
          message: "Cardinality limit exceeded",
          current: current_cardinality,
          limit: @cardinality_limit,
          overflow_count: @overflow_counts["#{metric_name}:#{key}"],
          severity: :error
        )

        # Also log warning
        warn "E11y Metrics: Cardinality limit exceeded for #{metric_name}:#{key} " \
             "(limit: #{@cardinality_limit}, current: #{current_cardinality})"
      end

      # Handle relabel strategy - relabel to [OTHER]
      # @param metric_name [String] Metric name
      # @param key [Symbol] Label key
      # @param value [Object] Label value
      # @param safe_labels [Hash] Current safe labels hash (modified in place)
      def handle_relabel(metric_name, key, value, safe_labels)
        # Relabel to [OTHER] to preserve some signal
        other_value = "[OTHER]"

        # Force-track [OTHER] as a special aggregate value
        # This bypasses limit checks since [OTHER] represents multiple overflow values
        @tracker.force_track(metric_name, key, other_value)

        # Add [OTHER] to safe_labels
        safe_labels[key] = other_value

        if defined?(Rails) && Rails.logger.debug?
          Rails.logger.debug(
            "[E11y] Cardinality limit exceeded: #{metric_name}:#{key}=#{value} " \
            "(relabeled to [OTHER])"
          )
        end
      end

      # Send alert to configured destinations
      # @param data [Hash] Alert data
      def send_alert(data)
        # Call custom callback if provided
        @alert_callback&.call(data)

        # Send to Sentry if available
        send_sentry_alert(data) if sentry_available?
      end

      # Send alert to Sentry
      # @param data [Hash] Alert data
      def send_sentry_alert(data)
        require "sentry-ruby" if defined?(Sentry)

        ::Sentry.with_scope do |scope|
          scope.set_tags(
            metric_name: data[:metric_name].to_s,
            label_key: data[:label_key].to_s,
            overflow_strategy: @overflow_strategy.to_s
          )

          scope.set_extras(data)

          level = data[:severity] == :error ? :error : :warning

          ::Sentry.capture_message(
            "[E11y] #{data[:message]}: #{data[:metric_name]}",
            level: level
          )
        end
      rescue LoadError, NameError
        # Sentry not available, skip
      end

      # Check if Sentry is available
      # @return [Boolean]
      def sentry_available?
        defined?(::Sentry) && ::Sentry.initialized?
      end

      # Track cardinality metric via Yabeda
      # @param metric_name [String] Metric name
      # @param action [Symbol] Action type (:threshold_exceeded, :drop, :alert, :relabel)
      # @param value [Integer] Metric value
      def track_cardinality_metric(metric_name, action, value)
        return unless defined?(E11y::Metrics)

        # Track overflow actions
        E11y::Metrics.increment(
          :e11y_cardinality_overflow_total,
          {
            metric: metric_name,
            action: action.to_s,
            strategy: @overflow_strategy.to_s
          }
        )

        # Track current cardinality
        E11y::Metrics.gauge(
          :e11y_cardinality_current,
          value,
          { metric: metric_name }
        )
      rescue StandardError => e
        # Don't fail on metrics tracking errors
        warn "E11y: Failed to track cardinality metric: #{e.message}"
      end
    end
  end
end

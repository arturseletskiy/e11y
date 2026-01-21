# frozen_string_literal: true

module E11y
  module Metrics
    # Thread-safe cardinality tracker for metrics labels.
    #
    # Tracks unique label value combinations per metric to detect
    # cardinality explosions. Separated from CardinalityProtection
    # for single responsibility and easier testing.
    #
    # @example Track label values
    #   tracker = CardinalityTracker.new(limit: 100)
    #   tracker.track('orders.total', :status, 'paid')
    #   tracker.track('orders.total', :status, 'failed')
    #   tracker.cardinality('orders.total', :status) # => 2
    #
    # @see CardinalityProtection
    class CardinalityTracker
      # @return [Integer] Default cardinality limit per metric
      DEFAULT_LIMIT = 1000

      # Initialize tracker
      #
      # @param limit [Integer] Maximum unique values per metric+label
      def initialize(limit: DEFAULT_LIMIT)
        @limit = limit
        @tracker = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = Set.new } }
        @mutex = Mutex.new
      end

      # Track a label value for a metric
      #
      # Records unique label values per metric+label combination.
      # Thread-safe operation.
      #
      # @param metric_name [String] Metric name
      # @param label_key [Symbol, String] Label key
      # @param label_value [Object] Label value to track
      # @return [Boolean] true if within limit, false if limit exceeded
      def track(metric_name, label_key, label_value)
        @mutex.synchronize do
          value_set = @tracker[metric_name][label_key]

          # Allow if already tracked (existing value)
          return true if value_set.include?(label_value)

          # Check if adding new value would exceed limit
          if value_set.size >= @limit
            false
          else
            value_set.add(label_value)
            true
          end
        end
      end

      # Force-track a label value, bypassing limit checks
      #
      # Used for special aggregate values like "[OTHER]" that need to be tracked
      # even when limit is exceeded.
      # Thread-safe operation.
      #
      # @param metric_name [String] Metric name
      # @param label_key [Symbol, String] Label key
      # @param label_value [Object] Label value to track
      # @return [void]
      def force_track(metric_name, label_key, label_value)
        @mutex.synchronize do
          value_set = @tracker[metric_name][label_key]
          value_set.add(label_value) unless value_set.include?(label_value)
        end
      end

      # Check if metric+label has exceeded cardinality limit
      #
      # @param metric_name [String] Metric name
      # @param label_key [Symbol, String] Label key
      # @return [Boolean] true if at or above limit
      def exceeded?(metric_name, label_key)
        @mutex.synchronize do
          @tracker.dig(metric_name, label_key)&.size.to_i >= @limit
        end
      end

      # Get current cardinality for metric+label
      #
      # @param metric_name [String] Metric name
      # @param label_key [Symbol, String] Label key
      # @return [Integer] Number of unique values tracked
      def cardinality(metric_name, label_key)
        @mutex.synchronize do
          @tracker.dig(metric_name, label_key)&.size || 0
        end
      end

      # Get cardinalities for all labels of a metric
      #
      # @param metric_name [String] Metric name
      # @return [Hash{Symbol => Integer}] Label key => cardinality
      def cardinalities(metric_name)
        @mutex.synchronize do
          metric_data = @tracker[metric_name]
          metric_data.transform_values(&:size)
        end
      end

      # Get all tracked cardinalities across all metrics
      #
      # @return [Hash{String => Hash{Symbol => Integer}}] Nested hash of metric => label => cardinality
      def all_cardinalities
        @mutex.synchronize do
          result = {}
          @tracker.each do |metric_name, labels|
            label_cardinalities = labels.transform_values(&:size)
            # Only include metrics with non-zero cardinalities
            result[metric_name] = label_cardinalities if label_cardinalities.values.any?(&:positive?)
          end
          result
        end
      end

      # Reset tracking for specific metric
      #
      # @param metric_name [String] Metric name to reset
      # @return [void]
      def reset_metric!(metric_name)
        @mutex.synchronize do
          @tracker.delete(metric_name)
        end
      end

      # Reset all tracking data
      #
      # @return [void]
      def reset_all!
        @mutex.synchronize do
          @tracker.clear
        end
      end

      # Get total number of tracked metrics
      #
      # @return [Integer] Number of unique metrics being tracked
      def metrics_count
        @mutex.synchronize do
          @tracker.size
        end
      end
    end
  end
end

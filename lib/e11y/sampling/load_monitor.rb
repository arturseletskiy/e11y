# frozen_string_literal: true

module E11y
  module Sampling
    # Load Monitor for Adaptive Sampling (FEAT-4842.1)
    #
    # Monitors system load and event volume to enable load-based adaptive sampling.
    # Implements load-based sampling strategy from ADR-009 §3.3.
    #
    # Features:
    # - Event volume tracking (events/second)
    # - Tiered load levels (normal, high, overload)
    # - Sliding window for rate calculation
    # - Thread-safe concurrent access
    #
    # @example Configuration
    #   monitor = E11y::Sampling::LoadMonitor.new(
    #     window: 60,                    # 60 seconds sliding window
    #     thresholds: {
    #       normal: 1_000,               # 0-1k events/sec → 100% sampling
    #       high: 10_000,                # 1k-10k events/sec → 50% sampling
    #       very_high: 50_000,           # 10k-50k events/sec → 10% sampling
    #       overload: 100_000            # >50k events/sec → 1% sampling
    #     }
    #   )
    #
    # @example Usage
    #   monitor.record_event
    #
    #   sample_rate = case monitor.load_level
    #                 when :normal then 1.0
    #                 when :high then 0.5
    #                 when :very_high then 0.1
    #                 when :overload then 0.01
    #                 end
    class LoadMonitor
      # Default configuration
      DEFAULT_WINDOW = 60              # 60 seconds sliding window
      DEFAULT_THRESHOLDS = {
        normal: 1_000,                 # 0-1k events/sec → 100% sampling
        high: 10_000,                  # 1k-10k events/sec → 50% sampling
        very_high: 50_000,             # 10k-50k events/sec → 10% sampling
        overload: 100_000              # >100k events/sec → 1% sampling
      }.freeze

      attr_reader :window, :thresholds

      # Initialize load monitor
      #
      # @param config [Hash] Configuration options
      # @option config [Integer] :window (60) Sliding window in seconds
      # @option config [Hash] :thresholds ({}) Load thresholds (events/sec)
      def initialize(config = {})
        @window = config.fetch(:window, DEFAULT_WINDOW)
        @thresholds = DEFAULT_THRESHOLDS.merge(config.fetch(:thresholds, {}))

        # Event tracking
        @events = [] # Timestamps of tracked events
        @mutex = Mutex.new
      end

      # Record an event for load tracking
      def record_event
        @mutex.synchronize do
          now = Time.now
          @events << now

          # Cleanup old events periodically (every 100 events) instead of on every event
          # This reduces O(n²) overhead significantly while keeping memory bounded
          cleanup_old_events(now) if (@events.size % 100).zero?
        end
      end

      # Get current event rate (events per second)
      #
      # @return [Float] Events per second
      def current_rate
        @mutex.synchronize do
          now = Time.now
          cutoff = now - @window

          # Count events within window without cleanup
          # Cleanup is handled periodically in record_event
          count = @events.count { |ts| ts >= cutoff }
          count.to_f / @window
        end
      end

      # Get current load level
      #
      # @return [Symbol] Load level (:normal, :high, :very_high, :overload)
      def load_level
        rate = current_rate

        # Check thresholds in descending order
        # rubocop:disable Lint/DuplicateBranch
        # Values between normal and high thresholds intentionally mapped to :high
        if rate >= @thresholds[:overload]
          :overload
        elsif rate >= @thresholds[:very_high]
          :very_high
        elsif rate >= @thresholds[:high]
          :high
        elsif rate > @thresholds[:normal]
          :high # Between normal and high threshold
        else
          :normal
        end
        # rubocop:enable Lint/DuplicateBranch
      end

      # Get recommended sample rate for current load
      #
      # @return [Float] Sample rate (0.0-1.0)
      # rubocop:disable Style/HashLikeCase
      # Case/when more readable for load level mapping with inline comments
      def recommended_sample_rate
        case load_level
        when :normal
          1.0   # 100% sampling
        when :high
          0.5   # 50% sampling
        when :very_high
          0.1   # 10% sampling
        when :overload
          0.01  # 1% sampling
        end
      end
      # rubocop:enable Style/HashLikeCase

      # Check if system is overloaded
      #
      # @return [Boolean] true if overload level reached
      def overloaded?
        load_level == :overload
      end

      # Reset monitor state (useful for testing)
      def reset!
        @mutex.synchronize do
          @events.clear
        end
      end

      # Get load statistics
      #
      # @return [Hash] Statistics (rate, level, sample_rate, event_count)
      def stats
        # Don't wrap in mutex - methods already handle locking
        {
          rate: current_rate,
          level: load_level,
          sample_rate: recommended_sample_rate,
          event_count: @mutex.synchronize { @events.size },
          window: @window
        }
      end

      private

      # Cleanup events outside the sliding window
      #
      # @param now [Time] Current timestamp
      def cleanup_old_events(now)
        cutoff = now - @window
        @events.reject! { |ts| ts < cutoff }
      end
    end
  end
end

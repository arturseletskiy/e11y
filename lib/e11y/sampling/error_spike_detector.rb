# frozen_string_literal: true

module E11y
  module Sampling
    # Error Spike Detector for Adaptive Sampling (FEAT-4838.1)
    #
    # Detects sudden increases in error rates and adjusts sampling accordingly.
    # Implements error-based adaptive sampling strategy from ADR-009 §3.2.
    #
    # Features:
    # - Sliding window for error rate calculation
    # - Absolute threshold (errors/minute)
    # - Relative threshold (ratio to baseline)
    # - Per-event and global error tracking
    #
    # @example Configuration
    #   detector = E11y::Sampling::ErrorSpikeDetector.new(
    #     window: 60,                    # 60 seconds sliding window
    #     absolute_threshold: 100,       # 100 errors/min triggers spike
    #     relative_threshold: 3.0,       # 3x normal rate triggers spike
    #     spike_duration: 300            # Keep 100% sampling for 5 minutes
    #   )
    #
    # @example Usage
    #   if detector.error_spike?
    #     sample_rate = 1.0  # 100% sampling during spike
    #   else
    #     sample_rate = 0.1  # 10% normal sampling
    #   end
    #
    #   detector.record_event(event_name: "payment.processed", severity: :error)
    class ErrorSpikeDetector
      # Default configuration
      DEFAULT_WINDOW = 60              # 60 seconds sliding window
      DEFAULT_ABSOLUTE_THRESHOLD = 100 # 100 errors/min triggers spike
      DEFAULT_RELATIVE_THRESHOLD = 3.0 # 3x normal rate triggers spike
      DEFAULT_SPIKE_DURATION = 300     # Keep elevated sampling for 5 minutes

      attr_reader :window, :absolute_threshold, :relative_threshold, :spike_duration

      # Initialize error spike detector
      #
      # @param config [Hash] Configuration options
      # @option config [Integer] :window (60) Sliding window in seconds
      # @option config [Integer] :absolute_threshold (100) Errors/min to trigger spike
      # @option config [Float] :relative_threshold (3.0) Multiplier vs baseline to trigger spike
      # @option config [Integer] :spike_duration (300) Seconds to keep elevated sampling
      def initialize(config = {})
        @window = config.fetch(:window, DEFAULT_WINDOW)
        @absolute_threshold = config.fetch(:absolute_threshold, DEFAULT_ABSOLUTE_THRESHOLD)
        @relative_threshold = config.fetch(:relative_threshold, DEFAULT_RELATIVE_THRESHOLD)
        @spike_duration = config.fetch(:spike_duration, DEFAULT_SPIKE_DURATION)

        # Event tracking (per event name)
        @error_events = Hash.new { |h, k| h[k] = [] }  # event_name => [timestamp, ...]
        @all_errors = []                               # All errors (global)
        @baseline_rates = Hash.new(0.0)                # event_name => baseline error rate

        # Spike state
        @spike_started_at = nil
        @mutex = Mutex.new
      end

      # Check if currently in error spike state
      #
      # @return [Boolean] true if error spike detected
      def error_spike?
        @mutex.synchronize do
          # Check if spike is still active (within spike_duration)
          if @spike_started_at
            elapsed = Time.now - @spike_started_at
            return true if elapsed < @spike_duration

            # Spike expired - check if it should continue
            if spike_detected?
              @spike_started_at = Time.now # Extend spike
              return true
            else
              @spike_started_at = nil # End spike
              return false
            end
          end

          # Check for new spike
          if spike_detected?
            @spike_started_at = Time.now
            return true
          end

          false
        end
      end

      # Record an event for error rate tracking
      #
      # @param event_data [Hash] Event payload
      # @option event_data [String] :event_name Event name
      # @option event_data [Symbol] :severity Event severity
      def record_event(event_data)
        return unless error_severity?(event_data[:severity])

        @mutex.synchronize do
          now = Time.now
          event_name = event_data[:event_name]

          # Record error
          @error_events[event_name] << now
          @all_errors << now

          # Cleanup old events (outside window)
          cleanup_old_events(now)

          # Update baseline (if not in spike)
          update_baseline(event_name) unless @spike_started_at
        end
      end

      # Get current error rate (errors per minute)
      #
      # @param event_name [String, nil] Event name, or nil for global rate
      # @return [Float] Errors per minute
      def current_error_rate(event_name = nil)
        @mutex.synchronize do
          now = Time.now
          cleanup_old_events(now)

          events = event_name ? @error_events[event_name] : @all_errors
          count = events.count { |ts| (now - ts) <= @window }

          # Convert to per-minute rate
          (count.to_f / @window) * 60
        end
      end

      # Get baseline error rate
      #
      # @param event_name [String] Event name
      # @return [Float] Baseline errors per minute
      def baseline_error_rate(event_name)
        @mutex.synchronize { @baseline_rates[event_name] }
      end

      # Reset detector state (useful for testing)
      def reset!
        @mutex.synchronize do
          @error_events.clear
          @all_errors.clear
          @baseline_rates.clear
          @spike_started_at = nil
        end
      end

      private

      # Check if severity is an error
      #
      # @param severity [Symbol, nil] Severity level
      # @return [Boolean] true if error or fatal
      def error_severity?(severity)
        %i[error fatal].include?(severity)
      end

      # Detect if spike conditions are met
      #
      # @return [Boolean] true if spike detected
      def spike_detected?
        # Check absolute threshold (global)
        global_rate = current_error_rate_unsafe
        return true if global_rate > @absolute_threshold

        # Check relative threshold (per event name)
        @error_events.each_key do |event_name|
          current_rate = current_error_rate_unsafe(event_name)
          baseline = @baseline_rates[event_name]

          # Only check relative if we have a baseline
          return true if baseline.positive? && current_rate > (baseline * @relative_threshold)
        end

        false
      end

      # Get current error rate (unsafe - must be called within mutex)
      #
      # @param event_name [String, nil] Event name, or nil for global
      # @return [Float] Errors per minute
      def current_error_rate_unsafe(event_name = nil)
        now = Time.now
        events = event_name ? @error_events[event_name] : @all_errors
        count = events.count { |ts| (now - ts) <= @window }
        (count.to_f / @window) * 60
      end

      # Update baseline error rate (unsafe - must be called within mutex)
      #
      # @param event_name [String] Event name
      def update_baseline(event_name)
        # Exponential moving average (EMA) with alpha = 0.1
        current_rate = current_error_rate_unsafe(event_name)
        old_baseline = @baseline_rates[event_name]

        @baseline_rates[event_name] = if old_baseline.zero?
                                        current_rate
                                      else
                                        (0.1 * current_rate) + (0.9 * old_baseline)
                                      end
      end

      # Cleanup events outside the sliding window
      #
      # @param now [Time] Current timestamp
      def cleanup_old_events(now)
        cutoff = now - @window

        # Cleanup per-event errors
        @error_events.each_value do |events|
          events.reject! { |ts| ts < cutoff }
        end

        # Cleanup global errors
        @all_errors.reject! { |ts| ts < cutoff }
      end
    end
  end
end

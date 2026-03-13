# frozen_string_literal: true

module E11y
  module Reliability
    # Retry Rate Limiter prevents thundering herd on adapter recovery.
    #
    # Implements staged batching with jitter to smooth retry load.
    # Prevents retry storms when adapters recover from failures.
    #
    # @example Usage
    #   limiter = RetryRateLimiter.new(limit: 50, window: 1.0)
    #
    #   limiter.allow?(adapter_name, event_data)  # => true/false
    #
    # @see ADR-013 §3.5 (C06 Resolution: Retry Rate Limiting)
    # @see UC-021 §5 (Retry Storm Prevention)
    class RetryRateLimiter
      # @param limit [Integer] Max retries per window (default: 50 retries/sec)
      # @param window [Float] Window size in seconds (default: 1.0)
      # @param on_limit_exceeded [Symbol] Action when limit exceeded (:delay or :dlq, default: :delay)
      # @param jitter_range [Float] Jitter factor (0.0-1.0, default: 0.2 = ±20%)
      def initialize(limit: 50, window: 1.0, on_limit_exceeded: :delay, jitter_range: 0.2)
        @limit = limit
        @window = window
        @on_limit_exceeded = on_limit_exceeded
        @jitter_range = jitter_range

        # Track retry counts per adapter per window
        @retry_counts = Hash.new { |h, k| h[k] = [] }
        @mutex = Mutex.new
      end

      # Check if retry is allowed for adapter.
      #
      # @param adapter_name [String] Adapter name
      # @param event_data [Hash] Event data (optional, for metrics)
      # @return [Boolean] true if retry allowed
      def allow?(adapter_name, event_data = {})
        @mutex.synchronize do
          cleanup_old_entries(adapter_name)

          current_count = @retry_counts[adapter_name].size

          if current_count >= @limit
            on_limit_exceeded(adapter_name, event_data)
            false
          else
            @retry_counts[adapter_name] << Time.now
            true
          end
        end
      end

      # Get current retry rate for adapter.
      #
      # @param adapter_name [String] Adapter name
      # @return [Hash] Current stats (count, limit, window)
      def stats(adapter_name)
        @mutex.synchronize do
          cleanup_old_entries(adapter_name)

          {
            adapter: adapter_name,
            current_count: @retry_counts[adapter_name].size,
            limit: @limit,
            window: @window,
            utilization: (@retry_counts[adapter_name].size.to_f / @limit * 100).round(2)
          }
        end
      end

      # Reset retry counts for adapter (for testing).
      #
      # @param adapter_name [String] Adapter name
      def reset!(adapter_name = nil)
        @mutex.synchronize do
          if adapter_name
            @retry_counts.delete(adapter_name)
          else
            @retry_counts.clear
          end
        end
      end

      private

      # Remove retry entries outside current window.
      def cleanup_old_entries(adapter_name)
        cutoff_time = Time.now - @window
        @retry_counts[adapter_name].reject! { |timestamp| timestamp < cutoff_time }
      end

      # Handle limit exceeded based on configured strategy.
      def on_limit_exceeded(adapter_name, _event_data)
        E11y::Metrics.increment(:e11y_retry_rate_limiter_total, adapter: adapter_name, event: "exceeded", delay_sec: "")

        case @on_limit_exceeded
        when :delay
          # Calculate delay with jitter
          delay_sec = @window + rand((-@jitter_range * @window)..(@jitter_range * @window))
          E11y::Metrics.increment(:e11y_retry_rate_limiter_total, adapter: adapter_name, event: "delayed", delay_sec: delay_sec.round(1).to_s)
          # Caller should sleep(delay_sec) before retry
        when :dlq
          E11y::Metrics.increment(:e11y_retry_rate_limiter_total, adapter: adapter_name, event: "dlq", delay_sec: "")
        end
      end

    end
  end
end

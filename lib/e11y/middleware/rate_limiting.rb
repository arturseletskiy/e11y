# frozen_string_literal: true

module E11y
  module Middleware
    # Rate Limiting Middleware (UC-011, C02 Resolution)
    #
    # Protects adapters from event floods using token bucket algorithm.
    # Critical events bypass rate limiting and go to DLQ (C02 Resolution).
    #
    # **Features:**
    # - Global rate limit (e.g., 10K events/sec)
    # - Per-event type rate limit (e.g., 1K payment.retry/sec)
    # - In-memory token bucket (no Redis dependency)
    # - Critical events bypass (C02 Resolution)
    # - DLQ integration for rate-limited critical events
    #
    # **ADR References:**
    # - ADR-013 §4.6 (C02 Resolution - Rate Limiting × DLQ Filter)
    # - ADR-015 §3 (Middleware Order - RateLimiting in :routing zone)
    #
    # **Use Case:** UC-011 (Rate Limiting - DoS Protection)
    #
    # @example Configuration
    #   E11y.configure do |config|
    #     config.pipeline.use E11y::Middleware::RateLimiting,
    #       global_limit: 10_000,        # Max 10K events/sec globally
    #       per_event_limit: 1_000,      # Max 1K events/sec per event type
    #       window: 1.0                  # 1 second window
    #   end
    #
    # @example Critical Event Bypass (C02)
    #   # Payment events bypass rate limiting → DLQ if limited
    #   config.dlq_filter.should_save?(event_data) # Event DSL: use_dlq
    #
    #   # Result: Rate-limited payment events go to DLQ, not dropped
    #
    # @see ADR-013 §4.6 for C02 Resolution details
    # @see UC-011 for rate limiting use cases
    class RateLimiting < Base
      # Initialize rate limiting middleware
      #
      # @param app [Object] Next middleware in pipeline
      # @param global_limit [Integer] Max events/sec globally (default: from E11y.config)
      # @param per_event_limit [Integer] Max events/sec per event type (default: from E11y.config)
      # @param window [Float] Time window in seconds (default: from E11y.config)
      def initialize(app, global_limit: nil, per_event_limit: nil, window: nil)
        super(app)
        config = E11y.config
        # When explicit limits are passed (e.g. from pipeline options), enable for this instance
        explicit_opts = global_limit || per_event_limit || window
        @enabled = explicit_opts ? true : config.rate_limiting_enabled
        @global_limit = global_limit || config.rate_limiting_global_limit
        @global_window = window || config.rate_limiting_global_window
        @window = @global_window # Alias for spec compatibility
        @per_event_limit = per_event_limit || config.rate_limiting_per_event_limit
        @explicit_per_event = per_event_limit && window

        # Token buckets for rate limiting
        @global_bucket = TokenBucket.new(
          capacity: @global_limit,
          refill_rate: @global_limit,
          window: @global_window
        )
        @per_event_buckets = Hash.new do |hash, event_name|
          limit_cfg = @explicit_per_event ? { limit: @per_event_limit, window: @window } : config.rate_limit_for(event_name)
          hash[event_name] = TokenBucket.new(
            capacity: limit_cfg[:limit],
            refill_rate: limit_cfg[:limit],
            window: limit_cfg[:window]
          )
        end

        @mutex = Mutex.new
      end

      # Process event through rate limiting
      #
      # @param event_data [Hash] Event payload
      # @return [Hash, nil] Event data if allowed, nil if rate limited
      def call(event_data)
        return @app.call(event_data) unless @enabled

        event_name = event_data[:event_name]

        # Check global rate limit
        unless @global_bucket.allow?
          handle_rate_limited(event_data, :global)
          return nil
        end

        # Check per-event rate limit
        per_event_bucket = @mutex.synchronize { @per_event_buckets[event_name] }
        unless per_event_bucket.allow?
          handle_rate_limited(event_data, :per_event)
          return nil
        end

        # Rate limit not exceeded - continue pipeline
        @app.call(event_data)
      end

      private

      # Handle rate-limited event (C02 Resolution)
      #
      # Critical events are saved to DLQ, non-critical events are dropped.
      #
      # @param event_data [Hash] Event payload
      # @param limit_type [Symbol] :global or :per_event
      def handle_rate_limited(event_data, limit_type)
        event_name = event_data[:event_name]

        # Log rate limiting (via E11y.logger so it respects Rails.logger in test env)
        E11y.logger&.warn("[E11y] Rate limit exceeded (#{limit_type}) for event: #{event_name}")

        # C02 Resolution: Check if event should be saved to DLQ
        if should_save_to_dlq?(event_data)
          record_dropped_metric(event_data, "rate_limited_#{limit_type}_dlq")
          save_to_dlq(event_data, limit_type)
        else
          record_dropped_metric(event_data, "rate_limited_#{limit_type}")
        end
      end

      # Record e11y_events_dropped_total metric (non-fatal, safe when Metrics unavailable)
      #
      # @param event_data [Hash] Event payload
      # @param reason [String] Drop reason (e.g., sampled_out, rate_limited_global)
      def record_dropped_metric(event_data, reason)
        return unless defined?(E11y::Metrics) && E11y::Metrics.respond_to?(:increment)

        E11y::Metrics.increment(:e11y_events_dropped_total, {
                                  reason: reason,
                                  event_type: event_data[:event_name].to_s
                                })
      rescue StandardError
        # non-fatal
      end

      # Check if rate-limited event should be saved to DLQ (C02 Resolution)
      #
      # @param event_data [Hash] Event payload
      # @return [Boolean] true if event should be saved to DLQ
      def should_save_to_dlq?(event_data)
        return false unless E11y.config.respond_to?(:dlq_filter)

        # Use DLQ filter to determine if event is critical
        dlq_filter = E11y.config.dlq_filter
        return false unless dlq_filter

        # Use DLQ filter (Event DSL: use_dlq, severity, default)
        dlq_filter.should_save?(event_data)
      end

      # Save rate-limited critical event to DLQ (C02 Resolution)
      #
      # @param event_data [Hash] Event payload
      # @param limit_type [Symbol] :global or :per_event
      def save_to_dlq(event_data, limit_type)
        return unless E11y.config.respond_to?(:dlq_storage)

        dlq_storage = E11y.config.dlq_storage
        return unless dlq_storage

        per_event_limit = limit_type == :per_event ? E11y.config.rate_limit_for(event_data[:event_name])[:limit] : @per_event_limit
        dlq_storage.save(event_data, metadata: {
                           reason: "rate_limited_#{limit_type}",
                           limit_type: limit_type,
                           global_limit: @global_limit,
                           per_event_limit: per_event_limit,
                           timestamp: Time.now.utc.iso8601
                         })

        E11y.logger&.warn("[E11y] Rate-limited critical event saved to DLQ: #{event_data[:event_name]}")
      rescue StandardError => e
        # Don't fail if DLQ save fails (C18 Resolution)
        E11y.logger&.warn("[E11y] Failed to save rate-limited event to DLQ: #{e.message}")
      end

      # Token Bucket implementation for rate limiting
      #
      # Thread-safe token bucket algorithm for rate limiting.
      #
      # @see https://en.wikipedia.org/wiki/Token_bucket
      class TokenBucket
        # Initialize token bucket
        #
        # @param capacity [Integer] Maximum tokens in bucket
        # @param refill_rate [Float] Tokens added per second
        # @param window [Float] Time window in seconds
        def initialize(capacity:, refill_rate:, window:)
          @capacity = capacity
          @refill_rate = refill_rate
          @window = window
          @tokens = capacity.to_f
          @last_refill = Time.now
          @mutex = Mutex.new
        end

        # Check if request is allowed (consumes 1 token if available)
        #
        # @return [Boolean] true if request allowed
        def allow?
          @mutex.synchronize do
            refill_tokens
            if @tokens >= 1.0
              @tokens -= 1.0
              true
            else
              false
            end
          end
        end

        # Current token count (for debugging)
        #
        # @return [Float] Current tokens available
        def tokens
          @mutex.synchronize do
            refill_tokens
            @tokens
          end
        end

        private

        # Refill tokens based on elapsed time
        def refill_tokens
          now = Time.now
          elapsed = now - @last_refill
          return if elapsed <= 0

          # Calculate tokens to add (refill_rate tokens per second)
          tokens_to_add = elapsed * @refill_rate
          @tokens = [@tokens + tokens_to_add, @capacity].min
          @last_refill = now
        end
      end
    end
  end
end

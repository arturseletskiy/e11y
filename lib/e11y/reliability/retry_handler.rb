# frozen_string_literal: true

require "securerandom"
require "timeout"

module E11y
  module Reliability
    # Retry handler with exponential backoff and jitter.
    #
    # Automatically retries transient failures with increasing delays.
    # Integrates with CircuitBreaker and DLQ for comprehensive error handling.
    #
    # @example Usage
    #   retry_handler = RetryHandler.new(config: config)
    #
    #   retry_handler.with_retry(adapter: adapter, event: event_data) do
    #     adapter.send(event_data)
    #   end
    #
    # @see ADR-013 §3 (Retry Policy)
    # @see UC-021 §2 (Exponential Backoff with Jitter)
    class RetryHandler
      # Retry exhausted error (all retries failed)
      class RetryExhaustedError < StandardError
        attr_reader :original_error, :retry_count

        def initialize(original_error, retry_count:)
          @original_error = original_error
          @retry_count = retry_count
          super("Retry exhausted after #{retry_count} attempts: #{original_error.message}")
        end
      end

      # Transient errors that should be retried
      TRANSIENT_ERRORS = [
        Timeout::Error,
        Errno::ECONNREFUSED,
        Errno::ECONNRESET,
        Errno::ETIMEDOUT,
        Errno::EHOSTUNREACH,
        Errno::ENETUNREACH
      ].freeze

      # HTTP status codes that should be retried (5xx server errors)
      RETRIABLE_HTTP_STATUS_CODES = (500..599)

      # @param config [Hash] Configuration options
      # @option config [Integer] :max_attempts Maximum retry attempts (default: 3)
      # @option config [Float] :base_delay_ms Initial delay in milliseconds (default: 100)
      # @option config [Float] :max_delay_ms Maximum delay in milliseconds (default: 5000)
      # @option config [Float] :jitter_factor Jitter factor (0.0-1.0, default: 0.1)
      # @option config [Boolean] :fail_on_error Raise error after max retries (default: true)
      # @param rate_limiter [RetryRateLimiter, nil] Optional rate limiter for thundering herd prevention (C06)
      def initialize(config: {}, rate_limiter: nil)
        @max_attempts = config[:max_attempts] || 3
        @base_delay_ms = config[:base_delay_ms] || 100.0
        @max_delay_ms = config[:max_delay_ms] || 5000.0
        @jitter_factor = config[:jitter_factor] || 0.1
        @fail_on_error = config.fetch(:fail_on_error, true)
        @rate_limiter = rate_limiter
      end

      # Execute block with retry logic.
      #
      # @param adapter [E11y::Adapters::Base] Adapter instance
      # @param event [Hash] Event data
      # @yield Block to execute (adapter send)
      # @return [Object] Result of block execution
      # @raise [RetryExhaustedError] if all retries fail and fail_on_error is true
      # rubocop:disable Metrics/MethodLength
      # Retry logic requires error handling, retriability check, backoff calculation, and callbacks
      def with_retry(adapter:, event:)
        attempt = 0

        loop do
          attempt += 1

          begin
            result = yield
            on_success(adapter, event, attempt)
            return result # Return actual result, not true
          rescue StandardError => e
            # Check if error is retriable
            unless retriable_error?(e)
              on_permanent_failure(adapter, event, e, attempt)
              raise RetryExhaustedError.new(e, retry_count: attempt) if @fail_on_error

              return nil
            end

            # Check if max attempts reached
            if attempt >= @max_attempts
              on_max_retries_exhausted(adapter, event, e, attempt)
              raise RetryExhaustedError.new(e, retry_count: attempt) if @fail_on_error

              return nil
            end

            # Calculate backoff delay
            delay_ms = calculate_backoff_delay(attempt)
            on_retry_attempt(adapter, event, e, attempt, delay_ms)

            # C06: Thundering herd prevention — check rate limiter before sleeping
            if @rate_limiter && !@rate_limiter.allow?(adapter.class.name, event)
              # Rate limit exceeded: use the configured action
              case @rate_limiter.instance_variable_get(:@on_limit_exceeded)
              when :dlq
                # Abort retry, let caller save to DLQ
                raise RetryExhaustedError.new(e, retry_count: attempt) if @fail_on_error

                return nil
              else
                # :delay — sleep for the full window + jitter before retrying
                jitter = rand(0..(delay_ms * 0.2))
                sleep((@rate_limiter.instance_variable_get(:@window) * 1000 + jitter) / 1000.0)
              end
            end

            # Sleep with backoff
            sleep(delay_ms / 1000.0)
          end
        end
      end
      # rubocop:enable Metrics/MethodLength

      private

      # Check if error should be retried.
      #
      # @param error [StandardError] The error that occurred
      # @return [Boolean] true if error is retriable
      def retriable_error?(error)
        # Check if error class is in transient errors list
        return true if TRANSIENT_ERRORS.any? { |klass| error.is_a?(klass) }

        # Check HTTP status codes (if error has response)
        if error.respond_to?(:response) && error.response.respond_to?(:code)
          status_code = error.response.code.to_i
          return true if RETRIABLE_HTTP_STATUS_CODES.cover?(status_code)
        end

        false
      end

      # Calculate exponential backoff delay with jitter.
      #
      # Formula: base_delay * (2 ^ attempt) + jitter
      # Jitter: random value between [-jitter_factor * delay, +jitter_factor * delay]
      #
      # @param attempt [Integer] Current attempt number (1-indexed)
      # @return [Float] Delay in milliseconds
      def calculate_backoff_delay(attempt)
        # Exponential backoff: base * 2^(attempt-1)
        exponential_delay = @base_delay_ms * (2**(attempt - 1))

        # Cap at max_delay
        exponential_delay = [@max_delay_ms, exponential_delay].min

        # Add jitter: +/- jitter_factor * delay
        jitter_range = exponential_delay * @jitter_factor
        jitter = rand(-jitter_range..jitter_range)

        exponential_delay + jitter
      end

      # Handle successful execution.
      def on_success(adapter, _event, attempt)
        increment_metric("e11y.retry.success", adapter: adapter.class.name, attempts: attempt)

        # Log if retry was needed
        return unless attempt > 1

        increment_metric("e11y.retry.recovered", adapter: adapter.class.name, attempts: attempt)
      end

      # Handle permanent failure (non-retriable error).
      def on_permanent_failure(adapter, _event, error, attempt)
        increment_metric(
          "e11y.retry.permanent_failure",
          adapter: adapter.class.name,
          error: error.class.name,
          attempt: attempt
        )
      end

      # Handle max retries exhausted (all attempts failed).
      def on_max_retries_exhausted(adapter, _event, error, attempt)
        increment_metric(
          "e11y.retry.exhausted",
          adapter: adapter.class.name,
          error: error.class.name,
          attempts: attempt
        )
      end

      # Handle retry attempt.
      def on_retry_attempt(adapter, _event, error, attempt, delay_ms)
        increment_metric(
          "e11y.retry.attempt",
          adapter: adapter.class.name,
          error: error.class.name,
          attempt: attempt
        )

        # Track backoff delay histogram
        track_histogram("e11y.retry.backoff_delay_ms", delay_ms, adapter: adapter.class.name)
      end

      # Increment retry metric.
      #
      # @param metric_name [String] Metric name
      # @param tags [Hash] Additional tags
      def increment_metric(metric_name, tags = {})
        # TODO: Integrate with Yabeda metrics
        # E11y::Metrics.increment(metric_name, tags)
      end

      # Track histogram metric.
      #
      # @param metric_name [String] Metric name
      # @param value [Numeric] Value to track
      # @param tags [Hash] Additional tags
      def track_histogram(metric_name, value, tags = {})
        # TODO: Integrate with Yabeda metrics
        # E11y::Metrics.histogram(metric_name, value, tags)
      end
    end
  end
end

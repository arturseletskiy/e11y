# frozen_string_literal: true

require_relative "../reliability/retry_handler"
require_relative "../reliability/retry_rate_limiter"
require_relative "../reliability/circuit_breaker"

module E11y
  module Adapters
    # Base class for all E11y adapters
    #
    # Provides standard interface for event destinations following ADR-004.
    # All adapters must implement {#write} method, optionally override {#write_batch}
    # for performance optimization.
    #
    # @abstract Subclass and implement {#write}, optionally {#write_batch}
    #
    # @example Define custom adapter
    #   class CustomAdapter < E11y::Adapters::Base
    #     def initialize(config = {})
    #       super
    #       @url = config.fetch(:url)
    #       validate_config!
    #     end
    #
    #     def write(event_data)
    #       # Send single event to external system
    #       send_to_api(event_data)
    #       true
    #     rescue => e
    #       warn "Adapter error: #{e.message}"
    #       false
    #     end
    #
    #     def capabilities
    #       {
    #         batching: false,
    #         compression: false,
    #         async: false,
    #         streaming: false
    #       }
    #     end
    #
    #     private
    #
    #     def validate_config!
    #       raise ArgumentError, "url is required" unless @url
    #     end
    #   end
    #
    # @see ADR-004 Section 3.1 (Base Adapter Contract)
    # rubocop:disable Metrics/ClassLength
    # Base adapter is a foundational class with core adapter functionality
    class Base
      attr_reader :config

      # Initialize adapter with config
      #
      # @param config [Hash] Adapter-specific configuration
      # @option config [Hash] :reliability Reliability settings (retry, circuit_breaker, dlq)
      def initialize(config = {})
        @config = config
        @reliability_enabled = config.fetch(:reliability, {}).fetch(:enabled, true)

        setup_reliability_layer if @reliability_enabled

        validate_config!
      end

      # Write a single event (synchronous)
      #
      # Subclasses must implement this method to send events to external systems.
      # This method is called for each event when batching is not used.
      #
      # @param event_data [Hash] Event payload with keys:
      #   - :event_name [String] Event name (e.g., "order.paid")
      #   - :severity [Symbol] Severity level (:debug, :info, :success, :warn, :error, :fatal)
      #   - :timestamp [Time] Event timestamp
      #   - :payload [Hash] Event-specific data
      #   - :trace_id [String, nil] Trace ID (if tracing enabled)
      #   - :span_id [String, nil] Span ID (if tracing enabled)
      #
      # @return [Boolean] true on success, false on failure (failures should be logged)
      # @raise [NotImplementedError] if not overridden in subclass
      #
      # @example
      #   def write(event_data)
      #     send_to_api(event_data)
      #     true
      #   rescue => e
      #     warn "Adapter error: #{e.message}"
      #     false
      #   end
      def write(_event_data)
        raise NotImplementedError, "#{self.class}#write must be implemented"
      end

      # Write event with reliability layer (retry, circuit breaker, DLQ).
      #
      # This is the recommended public API for sending events.
      # Automatically handles failures, retries, and DLQ.
      #
      # Respects `E11y.config.error_handling.fail_on_error` setting (C18 Resolution):
      # - `true`: Raises exceptions (fast feedback for web requests)
      # - `false`: Swallows exceptions, saves to DLQ (don't fail background jobs)
      #
      # @param event_data [Hash] Event payload
      # @return [Boolean] true on success
      # @raise [RetryExhaustedError, CircuitOpenError] if fail_on_error=true
      # Core reliability logic with retry and circuit breaker - should stay as cohesive unit
      def write_with_reliability(event_data)
        return write(event_data) unless @reliability_enabled

        start_time = Time.now
        begin
          @retry_handler.with_retry(adapter: self, event: event_data) do
            @circuit_breaker.call do
              write(event_data)
            end
          end

          # Track successful write
          track_adapter_success(event_data, start_time)
          true
        rescue E11y::Reliability::RetryHandler::RetryExhaustedError => e
          track_adapter_failure(event_data, e, start_time)
          handle_reliability_error(event_data, e, :retry_exhausted)
        rescue E11y::Reliability::CircuitBreaker::CircuitOpenError => e
          track_adapter_failure(event_data, e, start_time)
          handle_reliability_error(event_data, e, :circuit_open)
        end
      end

      # Write a batch of events (preferred for performance)
      #
      # Default implementation calls {#write} for each event.
      # Subclasses should override for better batch performance.
      #
      # @param events [Array<Hash>] Array of event payloads (same format as {#write})
      # @return [Boolean] true if all events written successfully, false otherwise
      #
      # @example Override for batch API
      #   def write_batch(events)
      #     send_batch_to_api(events)
      #     true
      #   rescue => e
      #     warn "Batch error: #{e.message}"
      #     false
      #   end
      def write_batch(events)
        # Default: call write for each event
        events.all? { |event| write(event) }
      end

      # Check if adapter is healthy
      #
      # Subclasses can override to implement health checks (e.g., ping destination).
      # Called periodically to determine if adapter can accept events.
      #
      # @return [Boolean] Health status (true = healthy, false = unhealthy)
      #
      # @example
      #   def healthy?
      #     ping_api
      #     true
      #   rescue
      #     false
      #   end
      def healthy?
        true
      end

      # Close connections, flush buffers
      #
      # Called during graceful shutdown. Subclasses should override to:
      # - Close HTTP connections
      # - Flush internal buffers
      # - Release resources
      #
      # @return [void]
      #
      # @example
      #   def close
      #     @buffer.flush! if @buffer.any?
      #     @connection.close
      #   end
      def close
        # Default: no-op
      end

      # Adapter capabilities
      #
      # Returns hash of capability flags. Subclasses should override to declare
      # supported features.
      #
      # @return [Hash] Capability flags with keys:
      #   - :batching [Boolean] Supports efficient batch writes
      #   - :compression [Boolean] Supports compression
      #   - :async [Boolean] Non-blocking writes
      #   - :streaming [Boolean] Supports streaming
      #
      # @example
      #   def capabilities
      #     {
      #       batching: true,
      #       compression: true,
      #       async: false,
      #       streaming: false
      #     }
      #   end
      def capabilities
        {
          batching: false,
          compression: false,
          async: false,
          streaming: false
        }
      end

      private

      # Validate adapter config
      #
      # Subclasses should override to validate configuration during initialization.
      # Raise ArgumentError for invalid config.
      #
      # @raise [ArgumentError] if configuration is invalid
      #
      # @example
      #   def validate_config!
      #     raise ArgumentError, "url is required" unless @config[:url]
      #   end
      def validate_config!
        # Default: no validation
      end

      # Format event for this adapter
      #
      # Subclasses can override to transform event_data to adapter-specific format.
      #
      # @param event_data [Hash] Event payload
      # @return [Hash, String] Formatted event
      #
      # @example
      #   def format_event(event_data)
      #     {
      #       timestamp: event_data[:timestamp].iso8601,
      #       message: event_data[:event_name],
      #       level: event_data[:severity]
      #     }
      #   end
      def format_event(event_data)
        event_data
      end

      # Execute block with retry logic for transient errors
      #
      # Implements exponential backoff with jitter for network/transient errors.
      # Use this helper in adapter write methods to handle temporary failures.
      #
      # @param max_attempts [Integer] Maximum retry attempts (default: 3)
      # @param base_delay [Float] Initial retry delay in seconds (default: 1.0)
      # @param max_delay [Float] Maximum retry delay in seconds (default: 16.0)
      # @param jitter [Float] Jitter factor (0.0-1.0, default: 0.2 for ±20%)
      # @yield Block to execute with retry
      # @return [Object] Block result
      # @raise Last exception if all retries exhausted
      #
      # @example Retry HTTP request
      #   def write(event_data)
      #     with_retry(max_attempts: 5) do
      #       http_client.post(event_data)
      #     end
      #     true
      #   rescue => e
      #     warn "Failed after retries: #{e.message}"
      #     false
      #   end
      #
      # @see ADR-004 Section 7.1 (Retry Policy)
      def with_retry(max_attempts: 3, base_delay: 1.0, max_delay: 16.0, jitter: 0.2)
        attempt = 0

        begin
          attempt += 1
          yield
        rescue StandardError => e
          raise unless retriable_error?(e) && attempt < max_attempts

          delay = calculate_backoff_delay(attempt, base_delay, max_delay, jitter)
          E11y.logger&.warn("[E11y] #{self.class.name} retry #{attempt}/#{max_attempts} after #{delay.round(2)}s: #{e.message}")
          sleep(delay)
          retry
        end
      end

      # Check if error is retriable (network/transient errors)
      #
      # Override in subclasses to customize retriable error detection.
      # Default implementation handles common network errors.
      #
      # @param error [Exception] Error to check
      # @return [Boolean] true if error is retriable
      #
      # @example Add custom retriable errors
      #   def retriable_error?(error)
      #     super || error.is_a?(CustomTransientError)
      #   end
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      # This method checks many different error types for retryability - splitting would reduce clarity
      def retriable_error?(error)
        # Network timeout errors
        return true if error.is_a?(Timeout::Error)
        return true if defined?(Net::ReadTimeout) && error.is_a?(Net::ReadTimeout)
        return true if defined?(Net::OpenTimeout) && error.is_a?(Net::OpenTimeout)

        # Connection errors
        return true if defined?(Errno::ECONNREFUSED) && error.is_a?(Errno::ECONNREFUSED)
        return true if defined?(Errno::ECONNRESET) && error.is_a?(Errno::ECONNRESET)
        return true if defined?(Errno::ETIMEDOUT) && error.is_a?(Errno::ETIMEDOUT)
        return true if defined?(Errno::EHOSTUNREACH) && error.is_a?(Errno::EHOSTUNREACH)

        # HTTP client errors (Faraday)
        if defined?(Faraday::TimeoutError)
          return true if error.is_a?(Faraday::TimeoutError)
          return true if error.is_a?(Faraday::ConnectionFailed)
        end

        # HTTP 5xx errors (server errors are retriable)
        if error.respond_to?(:response) && error.response.is_a?(Hash)
          status = error.response[:status]
          return true if status && status >= 500 && status < 600
        end

        false
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # Calculate exponential backoff delay with jitter
      #
      # @param attempt [Integer] Current attempt number (1-based)
      # @param base_delay [Float] Base delay in seconds
      # @param max_delay [Float] Maximum delay in seconds
      # @param jitter [Float] Jitter factor (0.0-1.0)
      # @return [Float] Delay in seconds
      #
      # @api private
      def calculate_backoff_delay(attempt, base_delay, max_delay, jitter)
        # Exponential: 1s, 2s, 4s, 8s, 16s...
        exponential_delay = base_delay * (2**(attempt - 1))
        delay = [exponential_delay, max_delay].min

        # Add jitter: ±20% by default
        jitter_amount = delay * jitter * ((rand * 2) - 1) # Random between -jitter and +jitter
        delay + jitter_amount
      end

      # Execute block with circuit breaker pattern
      #
      # Prevents cascading failures by opening circuit after threshold failures.
      # Use this helper to wrap write operations that may fail.
      #
      # Note: This is a simplified circuit breaker for single adapter instance.
      # For distributed systems, use external circuit breaker (e.g., semian gem).
      #
      # @param failure_threshold [Integer] Failures before opening circuit (default: 5)
      # @param timeout [Integer] Seconds before testing half-open (default: 60)
      # @yield Block to execute
      # @return [Object] Block result
      # @raise [CircuitOpenError] if circuit is open
      #
      # @example Wrap HTTP calls
      #   def write(event_data)
      #     with_circuit_breaker do
      #       http_client.post(event_data)
      #     end
      #     true
      #   rescue CircuitOpenError => e
      #     warn "Circuit open: #{e.message}"
      #     false
      #   end
      #
      # @see ADR-004 Section 7.2 (Circuit Breaker)
      # Circuit breaker state machine logic should stay as cohesive unit
      def with_circuit_breaker(failure_threshold: 5, timeout: 60)
        init_circuit_breaker! unless @circuit_state

        @circuit_mutex.synchronize do
          if @circuit_state == :open
            raise CircuitOpenError, "Circuit breaker open for #{self.class.name}" unless circuit_timeout_expired?(timeout)

            @circuit_state = :half_open
            @circuit_success_count = 0

          end
        end

        begin
          result = yield
          on_circuit_success
          result
        rescue StandardError
          on_circuit_failure(failure_threshold)
          raise
        end
      end

      # Initialize circuit breaker state
      #
      # @api private
      def init_circuit_breaker!
        @circuit_mutex = Mutex.new
        @circuit_state = :closed
        @circuit_failure_count = 0
        @circuit_success_count = 0
        @circuit_last_failure_time = nil
      end

      # Handle successful circuit execution
      #
      # @api private
      def on_circuit_success
        @circuit_mutex.synchronize do
          @circuit_failure_count = 0

          if @circuit_state == :half_open
            @circuit_success_count += 1
            if @circuit_success_count >= 2 # 2 successes → close
              @circuit_state = :closed
              E11y.logger&.warn("[E11y] #{self.class.name} circuit breaker closed (recovered)")
            end
          end
        end
      end

      # Handle failed circuit execution
      #
      # @param threshold [Integer] Failure threshold
      # @api private
      def on_circuit_failure(threshold)
        @circuit_mutex.synchronize do
          @circuit_failure_count += 1
          @circuit_success_count = 0
          @circuit_last_failure_time = Time.now

          if @circuit_failure_count >= threshold && @circuit_state == :closed
            @circuit_state = :open
            E11y.logger&.warn("[E11y] #{self.class.name} circuit breaker opened (#{@circuit_failure_count} failures)")
          end
        end
      end

      # Check if circuit timeout has expired
      #
      # @param timeout [Integer] Timeout in seconds
      # @return [Boolean]
      # @api private
      def circuit_timeout_expired?(timeout)
        @circuit_last_failure_time && (Time.now - @circuit_last_failure_time) >= timeout
      end

      # Setup reliability layer (Retry + CircuitBreaker + DLQ).
      #
      # @api private
      def setup_reliability_layer
        reliability_config = @config.fetch(:reliability, {})

        # Setup RetryHandler (C06: wire RetryRateLimiter for thundering herd prevention)
        retry_config = reliability_config.fetch(:retry, {})
        rate_limiter = reliability_config[:retry_rate_limiter] ||
                       E11y::Reliability::RetryRateLimiter.new
        @retry_handler = E11y::Reliability::RetryHandler.new(
          config: retry_config,
          rate_limiter: rate_limiter
        )

        # Setup CircuitBreaker
        circuit_breaker_config = reliability_config.fetch(:circuit_breaker, {})
        @circuit_breaker = E11y::Reliability::CircuitBreaker.new(
          adapter_name: self.class.name,
          config: circuit_breaker_config
        )
      end

      # Handle reliability error (retry exhausted / circuit breaker open).
      #
      # Behavior depends on `E11y.config.error_handling.fail_on_error` (C18 Resolution):
      # - `true`: Re-raises exception (fast feedback for web requests)
      # - `false`: Swallows exception, saves to DLQ (don't fail background jobs)
      #
      # @param event_data [Hash] Event payload
      # @param error [StandardError] Error that occurred
      # @param reason [Symbol] Error reason (:retry_exhausted, :circuit_open)
      # @return [Boolean] false (event failed)
      # @raise [StandardError] Re-raises if fail_on_error=true
      #
      # @api private
      # rubocop:disable Naming/PredicateMethod
      # This is an action method (handle error), not a predicate (is error handled?)
      def handle_reliability_error(event_data, error, reason)
        # Save to DLQ if filter allows
        save_to_dlq_if_needed(event_data, error, reason)

        # Log warning
        E11y.logger&.warn("[E11y] #{self.class.name} #{reason} for event #{event_data[:event_name]}: #{error.message}")

        # Check fail_on_error setting (C18 Resolution)
        raise error if E11y.config.error_handling.fail_on_error

        # Web request context: RAISE (fast feedback)

        # Background job context: SWALLOW (don't fail business logic)
        # TODO: Track metric e11y.event.tracking_failed_silent
        false
      end
      # rubocop:enable Naming/PredicateMethod

      # Save event to DLQ if filter allows.
      # Uses E11y.config.dlq_filter and E11y.config.dlq_storage (F3 — wired from config).
      #
      # @api private
      def save_to_dlq_if_needed(event_data, error, reason)
        dlq_filter = E11y.config.respond_to?(:dlq_filter) ? E11y.config.dlq_filter : nil
        dlq_storage = E11y.config.respond_to?(:dlq_storage) ? E11y.config.dlq_storage : nil
        return unless dlq_filter&.should_save?(event_data, error)
        return unless dlq_storage

        dlq_storage.save(event_data, metadata: {
                           error: error,
                           error_class: error.class.name,
                           reason: reason,
                           adapter: self.class.name,
                           timestamp: Time.now.utc.iso8601
                         })
      rescue StandardError => e
        # C18: Don't fail if DLQ save fails
        E11y.logger&.warn("[E11y] Failed to save event to DLQ: #{e.message}")
      end

      # Track successful adapter write (self-monitoring).
      #
      # @api private
      def track_adapter_success(_event_data, start_time)
        duration_ms = ((Time.now - start_time) * 1000).round(2)

        require "e11y/self_monitoring/performance_monitor"
        require "e11y/self_monitoring/reliability_monitor"

        # Use class name or "AnonymousAdapter" for anonymous classes
        adapter_name = self.class.name || "AnonymousAdapter"

        E11y::SelfMonitoring::PerformanceMonitor.track_adapter_latency(
          adapter_name,
          duration_ms
        )

        E11y::SelfMonitoring::ReliabilityMonitor.track_adapter_success(
          adapter_name: adapter_name
        )
      rescue StandardError => e
        # Don't fail if monitoring fails
        E11y.logger&.warn("[E11y] Self-monitoring error: #{e.message}")
      end

      # Track failed adapter write (self-monitoring).
      #
      # @api private
      def track_adapter_failure(_event_data, error, start_time)
        duration_ms = ((Time.now - start_time) * 1000).round(2)

        require "e11y/self_monitoring/performance_monitor"
        require "e11y/self_monitoring/reliability_monitor"

        # Use class name or "AnonymousAdapter" for anonymous classes
        adapter_name = self.class.name || "AnonymousAdapter"

        E11y::SelfMonitoring::PerformanceMonitor.track_adapter_latency(
          adapter_name,
          duration_ms
        )

        E11y::SelfMonitoring::ReliabilityMonitor.track_adapter_failure(
          adapter_name: adapter_name,
          error_class: error.class.name
        )
      rescue StandardError => e
        # Don't fail if monitoring fails
        warn "[E11y] Self-monitoring error: #{e.message}"
      end
    end
    # rubocop:enable Metrics/ClassLength

    # Circuit breaker open error
    class CircuitOpenError < Error; end
  end
end

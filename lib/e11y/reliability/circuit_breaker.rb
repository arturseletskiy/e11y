# frozen_string_literal: true

module E11y
  module Reliability
    # Circuit Breaker pattern implementation for adapter reliability.
    #
    # Prevents cascading failures by opening circuit when adapter fails repeatedly.
    # Three states: CLOSED (healthy), OPEN (failing), HALF_OPEN (testing recovery).
    #
    # @example Usage in adapter
    #   circuit_breaker = CircuitBreaker.new(adapter_name: "loki", config: config)
    #
    #   circuit_breaker.call do
    #     # Send event to adapter
    #     adapter.send(event)
    #   end
    #
    # @see ADR-013 §5 (Circuit Breaker)
    # @see UC-021 §4 (Circuit Breaker for Adapters)
    # rubocop:disable Metrics/ClassLength
    # Circuit breaker is a cohesive state machine with complex state transitions and recovery logic
    class CircuitBreaker
      # Circuit is closed (healthy) - all requests pass through
      STATE_CLOSED = :closed

      # Circuit is open (failing) - all requests fail fast
      STATE_OPEN = :open

      # Circuit is half-open (testing recovery) - limited requests allowed
      STATE_HALF_OPEN = :half_open

      # Circuit breaker opened error (fast fail)
      class CircuitOpenError < StandardError; end

      # @param adapter_name [String] Name of the adapter (for metrics)
      # @param config [Hash] Configuration options
      # @option config [Integer] :failure_threshold Number of failures before opening circuit (default: 5)
      # @option config [Integer] :timeout_seconds Seconds before transitioning to half-open (default: 60)
      # @option config [Integer] :half_open_attempts Success attempts needed in half-open to close (default: 2)
      def initialize(adapter_name:, config: {})
        @adapter_name = adapter_name
        @failure_threshold = config[:failure_threshold] || 5
        @timeout_seconds = config[:timeout_seconds] || 60
        @half_open_attempts = config[:half_open_attempts] || 2

        @state = STATE_CLOSED
        @failure_count = 0
        @success_count = 0
        @last_failure_time = nil
        @opened_at = nil
        @mutex = Mutex.new
      end

      # Execute block with circuit breaker protection.
      #
      # @yield Block to execute (adapter send)
      # @return [Object] Result of block execution
      # @raise [CircuitOpenError] if circuit is open
      # @raise [StandardError] if block raises and circuit transitions to open
      def call(&)
        check_state_transition

        case @state
        when STATE_CLOSED
          execute_with_closed_circuit(&)
        when STATE_OPEN
          handle_open_circuit
        when STATE_HALF_OPEN
          execute_with_half_open_circuit(&)
        end
      end

      # Check if circuit is healthy (closed state).
      #
      # @return [Boolean] true if circuit is closed
      def healthy?
        @state == STATE_CLOSED
      end

      # Get current circuit breaker statistics.
      #
      # @return [Hash] Statistics hash
      def stats
        {
          adapter: @adapter_name,
          state: @state,
          failure_count: @failure_count,
          success_count: @success_count,
          last_failure: @last_failure_time,
          opened_at: @opened_at
        }
      end

      private

      # Execute block in CLOSED state (normal operation).
      def execute_with_closed_circuit
        result = yield
        on_success
        result
      rescue StandardError => e
        on_failure(e)
        raise
      end

      # Execute block in HALF_OPEN state (testing recovery).
      def execute_with_half_open_circuit
        result = yield
        on_half_open_success
        result
      rescue StandardError => e
        on_half_open_failure(e)
        raise
      end

      # Handle OPEN state (fast fail).
      def handle_open_circuit
        increment_metric("e11y.circuit_breaker.rejected")

        raise CircuitOpenError, "Circuit breaker open for #{@adapter_name} " \
                                "(opened at #{@opened_at}, timeout: #{@timeout_seconds}s)"
      end

      # Check if circuit should transition states.
      def check_state_transition
        return unless @state == STATE_OPEN

        @mutex.synchronize do
          # Transition OPEN → HALF_OPEN after timeout
          transition_to_half_open if Time.now - @opened_at >= @timeout_seconds
        end
      end

      # Handle successful execution in CLOSED state.
      def on_success
        @mutex.synchronize do
          @failure_count = 0
          @success_count += 1
        end
      end

      # Handle failed execution in CLOSED state.
      def on_failure(error)
        @mutex.synchronize do
          @failure_count += 1
          @last_failure_time = Time.now

          # Transition CLOSED → OPEN if threshold exceeded
          transition_to_open if @failure_count >= @failure_threshold
        end
      end

      # Handle successful execution in HALF_OPEN state.
      def on_half_open_success
        @mutex.synchronize do
          @success_count += 1

          # Transition HALF_OPEN → CLOSED after enough successes
          transition_to_closed if @success_count >= @half_open_attempts
        end
      end

      # Handle failed execution in HALF_OPEN state.
      def on_half_open_failure(_error)
        @mutex.synchronize do
          # Single failure in HALF_OPEN → back to OPEN
          transition_to_open
        end
      end

      # Transition to OPEN state.
      def transition_to_open
        @state = STATE_OPEN
        @opened_at = Time.now
        @failure_count = 0 # Reset for next cycle
        @success_count = 0

        increment_metric("e11y.circuit_breaker.opened")
        track_circuit_state_gauge
      end

      # Transition to HALF_OPEN state.
      def transition_to_half_open
        @state = STATE_HALF_OPEN
        @success_count = 0 # Reset success counter for testing

        increment_metric("e11y.circuit_breaker.half_opened")
        track_circuit_state_gauge
      end

      # Transition to CLOSED state.
      def transition_to_closed
        @state = STATE_CLOSED
        @failure_count = 0
        @success_count = 0
        @opened_at = nil
        @last_failure_time = nil

        increment_metric("e11y.circuit_breaker.closed")
        track_circuit_state_gauge
      end

      # Increment circuit breaker metric.
      #
      # @param metric_name [String] Metric name
      # @param tags [Hash] Additional tags
      def increment_metric(metric_name, tags = {})
        return unless defined?(E11y::Metrics) && E11y::Metrics.respond_to?(:increment)

        name = "e11y_circuit_breaker_#{metric_name.to_s.split('.').last}".to_sym
        E11y::Metrics.increment(name, tags.merge(adapter: @adapter_name))
      rescue StandardError => e
        E11y.logger&.warn("E11y CircuitBreaker metric error: #{e.message}")
      end

      # Track circuit breaker state gauge via ReliabilityMonitor.
      def track_circuit_state_gauge
        return unless defined?(E11y::SelfMonitoring::ReliabilityMonitor)

        E11y::SelfMonitoring::ReliabilityMonitor.track_circuit_state(
          adapter_name: @adapter_name,
          state: @state.to_s
        )
      rescue StandardError => e
        E11y.logger&.warn("E11y CircuitBreaker gauge error: #{e.message}")
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end

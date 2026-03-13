# frozen_string_literal: true

require "e11y/metrics"

module E11y
  module SelfMonitoring
    # Reliability monitoring for E11y internal operations.
    #
    # Tracks success/failure rates for adapter writes and circuit breaker state.
    #
    # @see ADR-016 §3.2 (Reliability Metrics)
    # @example
    #   E11y::SelfMonitoring::ReliabilityMonitor.track_adapter_success(adapter_name: 'E11y::Adapters::Loki')
    module ReliabilityMonitor
      # Track adapter write success.
      #
      # @param adapter_name [String] Adapter class name
      # @return [void]
      def self.track_adapter_success(adapter_name:)
        E11y::Metrics.increment(
          :e11y_adapter_writes_total,
          {
            adapter: adapter_name,
            status: "success"
          }
        )
      end

      # Track adapter write failure.
      #
      # @param adapter_name [String] Adapter class name
      # @param error_class [String] Error class name
      # @return [void]
      def self.track_adapter_failure(adapter_name:, error_class:)
        E11y::Metrics.increment(
          :e11y_adapter_writes_total,
          {
            adapter: adapter_name,
            status: "failure",
            error_class: error_class
          }
        )
      end

      # Track circuit breaker state change.
      #
      # @param adapter_name [String] Adapter class name
      # @param state [String] New circuit state ('open', 'half_open', 'closed')
      # @return [void]
      def self.track_circuit_state(adapter_name:, state:)
        E11y::Metrics.gauge(
          :e11y_circuit_breaker_state,
          state_to_value(state),
          { adapter: adapter_name }
        )
      end

      # Convert circuit state to numeric value for gauge.
      #
      # @param state [String] Circuit state
      # @return [Integer] Numeric representation (0=closed, 1=half_open, 2=open)
      # @api private
      # rubocop:disable Lint/DuplicateBranch
      # Unknown states intentionally fallback to closed (0), same as "closed"
      def self.state_to_value(state)
        case state
        when "closed" then 0
        when "half_open" then 1
        when "open" then 2
        else 0
        end
      end
      # rubocop:enable Lint/DuplicateBranch

      private_class_method :state_to_value
    end
  end
end

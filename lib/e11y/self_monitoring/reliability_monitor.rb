# frozen_string_literal: true

require "e11y/metrics"

module E11y
  module SelfMonitoring
    # Reliability monitoring for E11y internal operations.
    #
    # Tracks success/failure rates for:
    # - Event tracking
    # - Adapter writes
    # - Buffer operations
    # - DLQ saves
    #
    # @see ADR-016 §3.2 (Reliability Metrics)
    # @example
    #   E11y::SelfMonitoring::ReliabilityMonitor.track_event_success(event_type: 'order.created')
    module ReliabilityMonitor
      # Track successful event tracking.
      #
      # @param event_type [String] Event type/name
      # @return [void]
      def self.track_event_success(event_type:)
        E11y::Metrics.increment(
          :e11y_events_tracked_total,
          {
            event_type: event_type,
            status: "success"
          }
        )
      end

      # Track failed event tracking.
      #
      # @param event_type [String] Event type/name
      # @param reason [String] Failure reason (e.g., 'validation_error', 'adapter_error')
      # @return [void]
      def self.track_event_failure(event_type:, reason:)
        E11y::Metrics.increment(
          :e11y_events_tracked_total,
          {
            event_type: event_type,
            status: "failure",
            reason: reason
          }
        )
      end

      # Track dropped event (rate limited, sampled out, etc).
      #
      # @param event_type [String] Event type/name
      # @param reason [String] Drop reason (e.g., 'rate_limited', 'sampled_out')
      # @return [void]
      def self.track_event_dropped(event_type:, reason:)
        E11y::Metrics.increment(
          :e11y_events_dropped_total,
          {
            event_type: event_type,
            reason: reason
          }
        )
      end

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

      # Track DLQ save operation.
      #
      # @param reason [String] Reason for DLQ save (e.g., 'adapter_error', 'rate_limited')
      # @return [void]
      def self.track_dlq_save(reason:)
        E11y::Metrics.increment(
          :e11y_dlq_saves_total,
          { reason: reason }
        )
      end

      # Track DLQ replay operation.
      #
      # @param status [String] Replay status ('success' or 'failure')
      # @return [void]
      def self.track_dlq_replay(status:)
        E11y::Metrics.increment(
          :e11y_dlq_replays_total,
          { status: status }
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
      def self.state_to_value(state)
        case state
        when "closed" then 0
        when "half_open" then 1
        when "open" then 2
        else 0
        end
      end

      private_class_method :state_to_value
    end
  end
end

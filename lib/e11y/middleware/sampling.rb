# frozen_string_literal: true

require "e11y/middleware/base"

module E11y
  module Middleware
    # Sampling Middleware
    #
    # Filters events based on sampling configuration to reduce volume and costs.
    # Supports:
    # - Per-event sample rates (from Event::Base)
    # - Severity-based sampling (errors always sampled)
    # - Pattern-based sampling (e.g., "debug.*" → 1%)
    # - Trace-aware sampling (C05 - all events in trace sampled or none)
    #
    # @example Basic usage
    #   E11y.configure do |config|
    #     config.middleware.use E11y::Middleware::Sampling, zone: :routing
    #   end
    #
    # @example Event-level sampling
    #   class Events::DebugQuery < E11y::Event::Base
    #     sample_rate 0.01  # 1% sampling
    #   end
    class Sampling < Base
      middleware_zone :routing

      # Initialize sampling middleware
      #
      # @param config [Hash] Configuration options
      # @option config [Float] :default_sample_rate (1.0) Default sample rate for events without explicit config
      # @option config [Boolean] :trace_aware (true) Enable trace-aware sampling (C05)
      # @option config [Hash] :severity_rates ({}) Override sample rates by severity
      def initialize(config = {})
        # Extract config before calling super (which sets @config)
        config ||= {}
        @default_sample_rate = config.fetch(:default_sample_rate, 1.0)
        @trace_aware = config.fetch(:trace_aware, true)
        @severity_rates = config.fetch(:severity_rates, {})
        @trace_decisions = {} # Cache for trace-level sampling decisions
        @trace_decisions_mutex = Mutex.new

        # Call super to set @config and other base middleware state
        super
      end

      # Process event through sampling filter
      #
      # @param event_data [Hash] The event payload
      # @return [Hash, nil] The event payload if sampled, nil if dropped
      def call(event_data)
        event_class = event_data[:event_class]

        # Determine if event should be sampled
        # Drop event if not sampled
        return nil unless should_sample?(event_data, event_class)

        # Mark as sampled for downstream middleware
        event_data[:sampled] = true
        event_data[:sample_rate] = determine_sample_rate(event_class)

        # Pass to next middleware
        @app.call(event_data)
      end

      # Returns capabilities of this middleware
      #
      # @return [Hash] Capabilities
      def capabilities
        {
          filters_events: true,
          trace_aware: @trace_aware,
          severity_aware: true
        }
      end

      private

      # Determine if event should be sampled
      #
      # @param event_data [Hash] The event payload
      # @param event_class [Class] The event class
      # @return [Boolean] true if event should be sampled
      def should_sample?(event_data, event_class)
        # 1. Check if audit event (never sample audit events!)
        return true if event_class.respond_to?(:audit_event?) && event_class.audit_event?

        # 2. Check trace-aware sampling (C05)
        return trace_sampling_decision(event_data[:trace_id], event_class) if @trace_aware && event_data[:trace_id]

        # 3. Get sample rate for this event
        sample_rate = determine_sample_rate(event_class)

        # 4. Random sampling decision
        rand < sample_rate
      end

      # Determine sample rate for event
      #
      # Priority (highest to lowest):
      # 1. Severity-based override from config (@severity_rates)
      # 2. Event-level config (event_class.resolve_sample_rate)
      # 3. Default sample rate (@default_sample_rate)
      #
      # @param event_class [Class] The event class
      # @return [Float] Sample rate (0.0-1.0)
      def determine_sample_rate(event_class)
        # 1. Severity-based override from middleware config (highest priority)
        if event_class.respond_to?(:severity)
          severity = event_class.severity
          return @severity_rates[severity] if @severity_rates.key?(severity)
        end

        # 2. Event-level config (from Event::Base)
        return event_class.resolve_sample_rate if event_class.respond_to?(:resolve_sample_rate)

        # 3. Default from middleware config
        @default_sample_rate
      end

      # Trace-aware sampling decision (C05 Resolution)
      #
      # All events in a trace share the same sampling decision.
      # This prevents incomplete traces in distributed systems.
      #
      # @param trace_id [String] The trace ID
      # @param event_class [Class] The event class
      # @return [Boolean] true if trace should be sampled
      def trace_sampling_decision(trace_id, event_class)
        @trace_decisions_mutex.synchronize do
          # Check if decision already made for this trace
          return @trace_decisions[trace_id] if @trace_decisions.key?(trace_id)

          # Make new sampling decision
          sample_rate = determine_sample_rate(event_class)
          decision = rand < sample_rate

          # Cache decision (TTL handled by periodic cleanup)
          @trace_decisions[trace_id] = decision

          # Cleanup old decisions periodically (every 1000 traces)
          cleanup_trace_decisions if @trace_decisions.size > 1000

          decision
        end
      end

      # Cleanup old trace decisions to prevent memory leaks
      #
      # Removes random 50% of cached decisions when cache grows too large.
      # This is a simple heuristic - traces typically complete in <10 seconds,
      # so old decisions are likely stale.
      def cleanup_trace_decisions
        # Remove random 50% of decisions
        keys_to_remove = @trace_decisions.keys.sample(@trace_decisions.size / 2)
        keys_to_remove.each { |key| @trace_decisions.delete(key) }
      end
    end
  end
end

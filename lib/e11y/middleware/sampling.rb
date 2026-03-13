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
    # - Error-based adaptive sampling (FEAT-4838 - 100% during error spikes)
    # - Load-based adaptive sampling (FEAT-4842 - tiered sampling based on event volume)
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
    #
    # @example Error-based adaptive sampling
    #   E11y.configure do |config|
    #     config.middleware.use E11y::Middleware::Sampling,
    #       error_based_adaptive: true,
    #       error_spike_config: {
    #         window: 60,
    #         absolute_threshold: 100,
    #         relative_threshold: 3.0,
    #         spike_duration: 300
    #       }
    #   end
    #
    # @example Load-based adaptive sampling
    #   E11y.configure do |config|
    #     config.middleware.use E11y::Middleware::Sampling,
    #       load_based_adaptive: true,
    #       load_monitor_config: {
    #         window: 60,
    #         thresholds: {
    #           normal: 1_000,    # 0-1k events/sec → 100% sampling
    #           high: 10_000,     # 1k-10k → 50%
    #           very_high: 50_000,# 10k-50k → 10%
    #           overload: 100_000 # >100k → 1%
    #         }
    #       }
    #   end
    # rubocop:disable Metrics/ClassLength
    # Class has 6 adaptive sampling strategies each requiring dedicated setup + private methods
    class Sampling < Base
      middleware_zone :routing

      # Initialize sampling middleware
      #
      # @param config [Hash] Configuration options
      # @option config [Float] :default_sample_rate (1.0) Default sample rate for events without explicit config
      # @option config [Boolean] :trace_aware (true) Enable trace-aware sampling (C05)
      # @option config [Hash] :severity_rates ({}) Override sample rates by severity
      # @option config [Boolean] :error_based_adaptive (false) Enable error-based adaptive sampling (FEAT-4838)
      # @option config [Hash] :error_spike_config ({}) Configuration for ErrorSpikeDetector
      # @option config [Boolean] :load_based_adaptive (false) Enable load-based adaptive sampling (FEAT-4842)
      # @option config [Hash] :load_monitor_config ({}) Configuration for LoadMonitor
      def initialize(app = nil, **config)
        # Call parent only if app provided (for production usage)
        super(app) if app
        @app = app

        setup_basic_config(config)
        setup_error_based_sampling(config)
        setup_load_based_sampling(config)
      end

      # Process event through sampling filter
      #
      # @param event_data [Hash] The event payload
      # @return [Hash, nil] The event payload if sampled, nil if dropped
      def call(event_data)
        # Handle nil from upstream middleware (e.g., rate limiting)
        return nil unless event_data

        event_class = event_data[:event_class]

        # Track errors for error-based adaptive sampling (FEAT-4838)
        @error_spike_detector.record_event(event_data) if @error_based_adaptive && @error_spike_detector

        # Track events for load-based adaptive sampling (FEAT-4842)
        @load_monitor&.record_event

        # Determine if event should be sampled
        # Drop event if not sampled
        unless should_sample?(event_data, event_class)
          begin
            if defined?(E11y::Metrics) && E11y::Metrics.respond_to?(:increment)
              E11y::Metrics.increment(:e11y_events_dropped_total, {
                                        reason: "sampled_out",
                event_type: event_data[:event_name].to_s
                                      })
            end
          rescue StandardError
            # non-fatal
          end
          return nil
        end

        # Mark as sampled for downstream middleware
        event_data[:sampled] = true
        event_data[:sample_rate] = determine_sample_rate(event_class, event_data)

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
          severity_aware: true,
          error_based_adaptive: @error_based_adaptive,  # FEAT-4838
          load_based_adaptive: @load_based_adaptive     # FEAT-4842
        }
      end

      private

      # Setup basic sampling configuration
      #
      # @param config [Hash] Configuration options
      def setup_basic_config(config)
        @default_sample_rate = config.fetch(:default_sample_rate, 1.0)
        @trace_aware = config.fetch(:trace_aware, true)
        @severity_rates = config.fetch(:severity_rates, {})
        @pattern_rates = config.fetch(:pattern_rates, []) # [[Regexp, Float], ...]
        @trace_decisions = {} # Cache for trace-level sampling decisions
        @trace_decisions_mutex = Mutex.new
      end

      # Setup error-based adaptive sampling (FEAT-4838)
      #
      # @param config [Hash] Configuration options
      def setup_error_based_sampling(config)
        @error_based_adaptive = config.fetch(:error_based_adaptive, false)
        return unless @error_based_adaptive

        require "e11y/sampling/error_spike_detector"
        error_spike_config = config.fetch(:error_spike_config, {})
        @error_spike_detector = E11y::Sampling::ErrorSpikeDetector.new(error_spike_config)
      end

      # Setup load-based adaptive sampling (FEAT-4842)
      #
      # @param config [Hash] Configuration options
      def setup_load_based_sampling(config)
        @load_based_adaptive = config.fetch(:load_based_adaptive, false)
        return unless @load_based_adaptive

        require "e11y/sampling/load_monitor"
        load_monitor_config = config.fetch(:load_monitor_config, {})
        @load_monitor = E11y::Sampling::LoadMonitor.new(load_monitor_config)
      end

      # Determine if event should be sampled
      #
      # @param event_data [Hash] The event payload
      # @param event_class [Class] The event class
      # @return [Boolean] true if event should be sampled
      def should_sample?(event_data, event_class)
        # 1. Check if audit event (never sample audit events!)
        return true if event_class.respond_to?(:audit_event?) && event_class.audit_event?

        # 2. Check trace-aware sampling (C05)
        return trace_sampling_decision(event_data[:trace_id], event_class, event_data) if @trace_aware && event_data[:trace_id]

        # 3. Get sample rate for this event
        sample_rate = determine_sample_rate(event_class, event_data)

        # 4. Random sampling decision
        rand < sample_rate
      end

      # Determine sample rate for event
      #
      # Priority (highest to lowest):
      # 0. Error spike override (100% during spike) - FEAT-4838
      # 1. Value-based sampling (high-value events) - FEAT-4849
      # 2. Load-based adaptive (tiered rates) - FEAT-4842
      # 3. Severity-based override from config (@severity_rates)
      # 4. Event-level config (event_class.resolve_sample_rate)
      # 5. Default sample rate (@default_sample_rate)
      #
      # @param event_class [Class] The event class
      # @param event_data [Hash] Event payload (for value-based sampling)
      # @return [Float] Sample rate (0.0-1.0)
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      # Sample rate determination follows a 6-step priority chain:
      # error spike (0) → pattern-based (0.5) → value-based (1) →
      # load-based (2) → severity (3) → event-level (4) → default (5)
      def determine_sample_rate(event_class, event_data = nil)
        # 0. Error-based adaptive sampling (FEAT-4838) - highest priority!
        if @error_based_adaptive && @error_spike_detector&.error_spike?
          return 1.0 # 100% sampling during error spike
        end

        # 0.5. Pattern-based sampling (by event_name) - overrides event-level config
        if event_data && !@pattern_rates.empty?
          event_name = event_data[:event_name].to_s
          @pattern_rates.each do |pattern, rate|
            return rate if pattern.match?(event_name)
          end
        end

        # 1. Value-based sampling (FEAT-4849) - high-value events always sampled
        if event_data && event_class.respond_to?(:value_sampling_configs)
          configs = event_class.value_sampling_configs
          unless configs.empty?
            require "e11y/sampling/value_extractor"
            extractor = E11y::Sampling::ValueExtractor.new
            payload = event_data[:payload] || event_data
            if configs.any? { |config| config.matches?(payload, extractor) }
              return 1.0 # 100% sampling for high-value events
            end
          end
        end

        # 2. Load-based adaptive sampling (FEAT-4842)
        # Apply load-based rate if enabled, but can be overridden by higher priority rules below
        base_rate = if @load_based_adaptive && @load_monitor
                      @load_monitor.recommended_sample_rate
                    else
                      @default_sample_rate
                    end

        # 2. Severity-based override from middleware config
        if event_class.respond_to?(:severity)
          severity = event_class.severity
          return @severity_rates[severity] if @severity_rates.key?(severity)
        end

        # 3. Event-level config (from Event::Base)
        # If event has explicit sample_rate, use min(event_rate, load_rate)
        if event_class.respond_to?(:resolve_sample_rate)
          event_rate = event_class.resolve_sample_rate
          return [event_rate, base_rate].min # Take the more restrictive rate
        end

        # 4. Default/load-based rate
        base_rate
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # Trace-aware sampling decision (C05 Resolution)
      #
      # All events in a trace share the same sampling decision.
      # This prevents incomplete traces in distributed systems.
      #
      # @param trace_id [String] The trace ID
      # @param event_class [Class] The event class
      # @param event_data [Hash] Event payload (for value-based sampling)
      # @return [Boolean] true if trace should be sampled
      def trace_sampling_decision(trace_id, event_class, event_data = nil)
        @trace_decisions_mutex.synchronize do
          # Check if decision already made for this trace
          return @trace_decisions[trace_id] if @trace_decisions.key?(trace_id)

          # Make new sampling decision
          sample_rate = determine_sample_rate(event_class, event_data)
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
    # rubocop:enable Metrics/ClassLength
  end
end

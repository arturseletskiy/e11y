# frozen_string_literal: true

module E11y
  module Adapters
    # Null Adapter — discards all events immediately.
    #
    # Useful for:
    #   - Memory and allocation profiling: no event storage means MemoryProfiler
    #     reports only pipeline costs, not adapter-side retention.
    #   - Benchmarking the pipeline in isolation.
    #   - Disabling telemetry in specific environments without removing event calls.
    #
    # Zero-retention guarantee: write() is a no-op returning true.
    # Reliability layer disabled by default to avoid Time.now and retry
    # allocations that would pollute allocation measurements.
    #
    # @example Configure for memory profiling
    #   E11y.configure do |config|
    #     config.adapters[:null] = E11y::Adapters::Null.new
    #     config.fallback_adapters = [:null]
    #   end
    class Null < Base
      def initialize(config = {})
        # Disable the reliability layer (retry + circuit breaker) so that
        # write_with_reliability bypasses Time.now and handler allocations.
        super(config.merge(reliability: { enabled: false }))
      end

      def write(_event_data) # rubocop:disable Naming/PredicateMethod
        true
      end

      def write_batch(_events) # rubocop:disable Naming/PredicateMethod
        true
      end

      def healthy?
        true
      end

      def capabilities
        { batching: true, compression: false, async: false, streaming: false, null: true }
      end
    end
  end
end

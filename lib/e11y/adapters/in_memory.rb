# frozen_string_literal: true

module E11y
  module Adapters
    # InMemory Adapter - Test adapter for specs and debugging
    #
    # Stores events in memory for testing and inspection.
    # Not for production use - events are lost on restart.
    #
    # **⚠️ Memory Safety:**
    # - Default limit: 1000 events (prevents unbounded growth)
    # - Auto-drops oldest events when limit reached (FIFO)
    # - Configure limit based on test needs
    #
    # **Features:**
    # - Thread-safe event storage
    # - Batch tracking
    # - Query methods for tests
    # - Manual clear support
    # - Automatic memory limit enforcement
    #
    # @example Usage in tests
    #   let(:test_adapter) { E11y::Adapters::InMemory.new }
    #
    #   before { E11y.register_adapter :test, test_adapter }
    #   after { test_adapter.clear! }
    #
    #   it "tracks events" do
    #     Events::OrderPaid.track(order_id: '123')
    #     expect(test_adapter.events.size).to eq(1)
    #     expect(test_adapter.events.first[:event_name]).to eq('order.paid')
    #   end
    #
    # @example Custom limit
    #   # For tests with many events
    #   test_adapter = E11y::Adapters::InMemory.new(max_events: 10_000)
    #
    #   # Unlimited (use with caution!)
    #   test_adapter = E11y::Adapters::InMemory.new(max_events: nil)
    #
    # @see ADR-004 §9.1 (In-Memory Test Adapter)
    class InMemory < Base
      # Default maximum number of events to store
      DEFAULT_MAX_EVENTS = 1000

      # All events written to adapter
      #
      # @return [Array<Hash>] Array of event payloads
      attr_reader :events

      # All batches written to adapter
      #
      # @return [Array<Array<Hash>>] Array of event batches
      attr_reader :batches

      # Maximum number of events to store
      #
      # @return [Integer, nil] Max events or nil for unlimited
      attr_reader :max_events

      # Number of events dropped due to limit
      #
      # @return [Integer] Dropped event count
      attr_reader :dropped_count

      # Initialize adapter
      #
      # @param config [Hash] Configuration options
      # @option config [Integer, nil] :max_events (1000) Maximum events to store (nil = unlimited)
      def initialize(config = {})
        super
        @max_events = config.fetch(:max_events, DEFAULT_MAX_EVENTS)
        @events = []
        @batches = []
        @dropped_count = 0
        @mutex = Mutex.new
      end

      # Write event to memory
      #
      # @param event_data [Hash] Event payload
      # @return [Boolean] true on success
      # rubocop:disable Naming/PredicateMethod
      # This is an action method (write event), not a predicate (is written?)
      def write(event_data)
        @mutex.synchronize do
          @events << event_data
          enforce_limit!
        end
        true
      end
      # rubocop:enable Naming/PredicateMethod

      # Write batch of events to memory
      #
      # @param events [Array<Hash>] Array of event payloads
      # @return [Boolean] true on success
      # rubocop:disable Naming/PredicateMethod
      # This is an action method (write batch), not a predicate (is written?)
      def write_batch(events)
        @mutex.synchronize do
          @events.concat(events)
          @batches << events
          enforce_limit!
        end
        true
      end
      # rubocop:enable Naming/PredicateMethod

      # Clear all stored events and batches
      #
      # @return [void]
      def clear!
        @mutex.synchronize do
          @events.clear
          @batches.clear
          @dropped_count = 0
        end
      end

      alias clear clear!

      # Find events matching pattern
      #
      # @param pattern [String, Regexp, Class] Event name pattern or event class
      # @return [Array<Hash>] Matching events
      #
      # @example
      #   adapter.find_events(/order/)  # All order.* events
      #   adapter.find_events("order.paid")  # Exact match
      #   adapter.find_events(Events::OrderPaid)  # By event class
      def find_events(pattern)
        pattern = event_pattern_for(pattern)
        @events.select { |event| event_matches?(event, pattern) }
      end

      # Find first event matching pattern
      #
      # @param pattern [String, Regexp, Class] Event name pattern or event class
      # @return [Hash, nil] First matching event or nil
      def find_event(pattern)
        find_events(pattern).first
      end

      # Count events by name
      #
      # @param event_name [String, nil] Event name to count, or nil for total
      # @return [Integer] Event count
      #
      # @example
      #   adapter.event_count  # Total events
      #   adapter.event_count("order.paid")  # Specific event count (positional)
      #   adapter.event_count(event_name: "order.paid")  # Specific event count (keyword)
      def event_count(event_name = nil, **kwargs)
        event_name ||= kwargs[:event_name]
        if event_name
          @events.count { |event| event[:event_name] == event_name }
        else
          @events.size
        end
      end

      # Get the most recently written event.
      #
      # @return [Hash, nil] The last event, or nil if none
      #
      # @example
      #   adapter.last_event  # Most recently written event
      def last_event
        events.last
      end

      # Get last N events
      #
      # @param count [Integer] Number of events to return
      # @return [Array<Hash>] Last N events
      #
      # @example
      #   adapter.last_events(5)  # Last 5 events
      def last_events(count = 10)
        @events.last(count)
      end

      # Get first N events
      #
      # @param count [Integer] Number of events to return
      # @return [Array<Hash>] First N events
      #
      # @example
      #   adapter.first_events(5)  # First 5 events
      def first_events(count = 10)
        @events.first(count)
      end

      # Find events by severity
      #
      # @param severity [Symbol] Severity level to filter by
      # @return [Array<Hash>] Events with matching severity
      #
      # @example
      #   adapter.events_by_severity(:error)  # All error events
      def events_by_severity(severity)
        @events.select { |event| event[:severity] == severity }
      end

      # Check if any events match pattern
      #
      # @param pattern [String, Regexp] Pattern to match
      # @return [Boolean] true if any events match
      #
      # @example
      #   adapter.any_event?(/order/)  # Any order.* events?
      def any_event?(pattern)
        find_events(pattern).any?
      end

      # Adapter capabilities
      #
      # @return [Hash] Capability flags
      def capabilities
        {
          batching: true,
          compression: false,
          async: false,
          streaming: false
        }
      end

      private

      def event_pattern_for(pattern)
        case pattern
        when Class
          pattern
        when String
          Regexp.new(Regexp.escape(pattern))
        when Regexp
          pattern
        else
          raise ArgumentError, "Pattern must be Class, String, or Regexp, got #{pattern.class}"
        end
      end

      def event_matches?(event, pattern)
        return event[:event_name].to_s.match?(pattern) if pattern.is_a?(Regexp)

        return false unless pattern.is_a?(Class)

        event[:event_class] == pattern ||
          event[:event_class]&.name == pattern.name ||
          event[:event_name].to_s == (pattern.respond_to?(:event_name) ? pattern.event_name : pattern.name) ||
          event[:event_name].to_s.include?(pattern.name)
      end

      # Enforce max_events limit by dropping oldest events (FIFO)
      #
      # @return [void]
      def enforce_limit!
        return if max_events.nil? # Unlimited

        return unless @events.size > max_events

        excess = @events.size - max_events
        @events.shift(excess)
        @dropped_count += excess
      end
    end
  end
end

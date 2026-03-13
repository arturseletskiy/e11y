# frozen_string_literal: true

require "concurrent"

module E11y
  module Buffers
    # Lock-free SPSC (Single-Producer, Single-Consumer) ring buffer
    #
    # Thread-safe ring buffer using atomic operations for high-throughput event buffering.
    # Designed for 100K+ events/sec with minimal contention.
    #
    # Architecture:
    # - Fixed capacity (default: 100,000 events)
    # - Atomic read/write pointers (Concurrent::AtomicFixnum)
    # - Backpressure strategies: :drop_oldest (default), :drop_newest, :block
    # - Zero-copy flush operations
    #
    # Performance:
    # - Target: 100K events/sec throughput
    # - Latency: <10μs per push/pop operation (p99)
    # - Memory: Fixed allocation (capacity * avg_event_size)
    #
    # References:
    # - ADR-001 §3.3.1 (Ring Buffer Specification)
    # - UC-001 (Request-Scoped Debug Buffering)
    #
    # @example Basic usage
    #   buffer = E11y::Buffers::RingBuffer.new(capacity: 1000)
    #   buffer.push(event_hash)
    #   events = buffer.pop(100) # Batch pop
    #
    # @example With backpressure
    #   buffer = E11y::Buffers::RingBuffer.new(
    #     capacity: 1000,
    #     overflow_strategy: :drop_oldest
    #   )
    #   buffer.push(event) # Drops oldest if full
    #
    # @see ADR-001 §3.3.1
    class RingBuffer
      # Default buffer capacity (100K events)
      DEFAULT_CAPACITY = 100_000

      # Available overflow strategies
      OVERFLOW_STRATEGIES = %i[drop_oldest drop_newest block].freeze

      # Default overflow strategy
      DEFAULT_OVERFLOW_STRATEGY = :drop_oldest

      # Maximum block time for :block strategy (milliseconds)
      DEFAULT_MAX_BLOCK_TIME_MS = 1000

      attr_reader :capacity, :overflow_strategy

      # Initialize a new ring buffer
      #
      # @param capacity [Integer] Maximum number of events (default: 100,000)
      # @param overflow_strategy [Symbol] Strategy when buffer is full
      #   - :drop_oldest - Drop oldest event, keep newest (default)
      #   - :drop_newest - Drop new event, keep existing
      #   - :block - Wait until space available (up to max_block_time)
      # @param max_block_time_ms [Integer] Max wait time for :block strategy (default: 1000ms)
      #
      # @raise [ArgumentError] if capacity <= 0 or invalid overflow_strategy
      #
      # @example
      #   buffer = RingBuffer.new(capacity: 10_000, overflow_strategy: :drop_oldest)
      def initialize(capacity: DEFAULT_CAPACITY, overflow_strategy: DEFAULT_OVERFLOW_STRATEGY,
                     max_block_time_ms: DEFAULT_MAX_BLOCK_TIME_MS)
        raise ArgumentError, "capacity must be > 0" if capacity <= 0

        unless OVERFLOW_STRATEGIES.include?(overflow_strategy)
          raise ArgumentError,
                "overflow_strategy must be one of #{OVERFLOW_STRATEGIES.inspect}"
        end

        @capacity = capacity
        @overflow_strategy = overflow_strategy
        @max_block_time_ms = max_block_time_ms

        # Fixed-size array for storage
        @buffer = Array.new(capacity)

        # Atomic pointers (SPSC pattern)
        @write_index = Concurrent::AtomicFixnum.new(0) # Producer writes here
        @read_index = Concurrent::AtomicFixnum.new(0)  # Consumer reads here
        @size = Concurrent::AtomicFixnum.new(0)        # Current occupancy
      end

      # Push an event into the buffer (Producer)
      #
      # This is a single-producer operation - only ONE thread should call push().
      # Uses atomic operations to ensure thread-safety with pop() (consumer).
      #
      # Behavior on overflow:
      # - :drop_oldest - Removes oldest event, adds new one (always succeeds)
      # - :drop_newest - Discards new event, keeps buffer unchanged
      # - :block - Waits up to max_block_time for space, then drops
      #
      # @param event [Hash] Event hash to buffer
      # @return [Boolean] true if event was added, false if dropped
      #
      # @example
      #   success = buffer.push({ event_name: "test", payload: {} })
      #   # => true (or false if dropped)
      def push(event)
        current_size = @size.value

        if current_size >= @capacity
          # Buffer full - handle backpressure
          return handle_overflow(event)
        end

        # Write to buffer
        write_pos = @write_index.value % @capacity
        @buffer[write_pos] = event

        # Increment pointers atomically
        @write_index.increment
        @size.increment

        true
      end

      # Pop events from buffer (Consumer)
      #
      # This is a single-consumer operation - only ONE thread should call pop().
      # Returns up to batch_size events in FIFO order.
      #
      # @param batch_size [Integer] Maximum events to pop (default: 100)
      # @return [Array<Hash>] Array of events (may be empty)
      #
      # @example
      #   events = buffer.pop(50)
      #   # => [{ event_name: "test", ... }, ...]
      def pop(batch_size = 100)
        events = []
        current_size = @size.value

        # Limit batch size to available events
        actual_batch_size = [batch_size, current_size].min

        actual_batch_size.times do
          read_pos = @read_index.value % @capacity
          event = @buffer[read_pos]

          events << event if event

          # Clear slot to allow GC
          @buffer[read_pos] = nil

          # Increment pointers atomically
          @read_index.increment
          @size.decrement
        end

        events
      end

      # Flush all events from buffer
      #
      # Empties the buffer and returns all events in FIFO order.
      # This is equivalent to pop(size), but more explicit.
      #
      # @return [Array<Hash>] All buffered events
      #
      # @example
      #   all_events = buffer.flush_all
      #   # => [event1, event2, ...]
      def flush_all
        pop(@size.value)
      end

      # Current number of events in buffer
      #
      # @return [Integer] Number of buffered events
      def size
        @size.value
      end

      # Check if buffer is empty
      #
      # @return [Boolean] true if no events buffered
      def empty?
        @size.value.zero?
      end

      # Check if buffer is full
      #
      # @return [Boolean] true if buffer is at capacity
      def full?
        @size.value >= @capacity
      end

      # Calculate buffer utilization percentage
      #
      # @return [Float] Utilization (0.0 to 1.0)
      #
      # @example
      #   buffer.utilization # => 0.75 (75% full)
      def utilization
        @size.value.to_f / @capacity
      end

      private

      # Handle buffer overflow according to strategy
      #
      # @param event [Hash] Event that caused overflow
      # @return [Boolean] true if event was eventually added, false if dropped
      # rubocop:disable Metrics/MethodLength
      def handle_overflow(event)
        case @overflow_strategy
        when :drop_oldest
          # Drop oldest event, add new one
          pop(1) # Remove one old event
          push(event) # Retry push (recursive, but will succeed)
        when :drop_newest
          # Drop new event, keep buffer unchanged
          increment_metric("e11y.buffer.overflow.drop_newest")
          false
        when :block
          # Wait for space, with timeout
          wait_for_space
          if full?
            # Timeout reached, drop event
            increment_metric("e11y.buffer.overflow.block_timeout")
            false
          else
            push(event) # Retry after space freed
          end
        end
      end
      # rubocop:enable Metrics/MethodLength

      # Wait for buffer space (with timeout)
      #
      # Sleeps briefly until space is available or timeout reached.
      # Used by :block overflow strategy.
      #
      # @return [void]
      def wait_for_space
        start_time = Time.now.to_f
        timeout_seconds = @max_block_time_ms / 1000.0

        while full?
          elapsed = Time.now.to_f - start_time
          break if elapsed >= timeout_seconds

          # Brief sleep to avoid busy-wait
          sleep 0.001 # 1ms
        end
      end

      # Increment overflow metric via E11y::Metrics
      #
      # @param metric_name [String] Metric to increment (e.g. "e11y.buffer.overflow.drop_newest")
      # @return [void]
      def increment_metric(metric_name)
        return unless defined?(E11y::Metrics) && E11y::Metrics.respond_to?(:increment)

        name = metric_name.to_s.tr(".", "_").to_sym
        E11y::Metrics.increment(name, {})
      rescue StandardError => e
        E11y.logger&.debug("E11y RingBuffer metric error: #{e.message}")
      end
    end
  end
end

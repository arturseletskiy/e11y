# frozen_string_literal: true

require "concurrent"

module E11y
  module Buffers
    # Adaptive buffer with global memory tracking and backpressure
    #
    # Key features:
    # - Global memory limit (100MB default)
    # - Per-adapter buffering (Hash-based)
    # - Event size estimation (±10% accuracy)
    # - Early flush at 80% threshold
    # - Backpressure strategies (:block, :drop)
    # - Thread-safe flush operations
    #
    # Architecture (C20 Resolution):
    # - Tracks memory usage across ALL buffers globally
    # - Enforces strict memory limits to prevent OOM
    # - Adaptive behavior: flush early when approaching limit
    # - Backpressure: block or drop events when limit exceeded
    #
    # References:
    # - ADR-001 §3.3.2 (Adaptive Buffer with Memory Limits)
    # - UC-001 (Request-Scoped Debug Buffering)
    # - UC-014 (Adaptive Sampling)
    #
    # @example Basic usage
    #   buffer = E11y::Buffers::AdaptiveBuffer.new
    #   buffer.add_event({ event_name: "test", payload: {...}, adapters: [:logs] })
    #   events = buffer.flush # Returns all events
    #
    # @example With memory limit
    #   buffer = E11y::Buffers::AdaptiveBuffer.new(memory_limit_mb: 50)
    #   buffer.add_event(event) # May trigger backpressure if limit exceeded
    #
    # @see ADR-001 §3.3.2
    # rubocop:disable Metrics/ClassLength
    class AdaptiveBuffer
      # Default memory limit (100 MB)
      DEFAULT_MEMORY_LIMIT_MB = 100

      # Early flush threshold (80%)
      EARLY_FLUSH_THRESHOLD = 0.8

      # Available backpressure strategies
      BACKPRESSURE_STRATEGIES = %i[block drop].freeze

      # Default backpressure strategy
      DEFAULT_BACKPRESSURE_STRATEGY = :drop

      # Maximum block time for :block strategy (seconds)
      DEFAULT_MAX_BLOCK_TIME = 1.0

      attr_reader :memory_limit_bytes

      # Initialize adaptive buffer
      #
      # @param memory_limit_mb [Integer] Memory limit in megabytes (default: 100)
      # @param backpressure_strategy [Symbol] Strategy when limit exceeded (:block, :drop)
      # @param max_block_time [Float] Max wait time for :block strategy (seconds)
      #
      # @raise [ArgumentError] if memory_limit_mb <= 0 or invalid strategy
      #
      # @example
      #   buffer = AdaptiveBuffer.new(memory_limit_mb: 50, backpressure_strategy: :block)
      def initialize(memory_limit_mb: DEFAULT_MEMORY_LIMIT_MB,
                     backpressure_strategy: DEFAULT_BACKPRESSURE_STRATEGY,
                     max_block_time: DEFAULT_MAX_BLOCK_TIME)
        raise ArgumentError, "memory_limit_mb must be > 0" if memory_limit_mb <= 0

        unless BACKPRESSURE_STRATEGIES.include?(backpressure_strategy)
          raise ArgumentError,
                "backpressure_strategy must be one of #{BACKPRESSURE_STRATEGIES.inspect}"
        end

        @memory_limit_bytes = memory_limit_mb * 1024 * 1024
        @memory_warning_threshold = (@memory_limit_bytes * EARLY_FLUSH_THRESHOLD).to_i
        @backpressure_strategy = backpressure_strategy
        @max_block_time = max_block_time

        # Per-adapter buffers (Hash: adapter_key => Array<event_hash>)
        @buffers = {}

        # Global memory tracking (atomic for thread-safety)
        @total_memory_bytes = Concurrent::AtomicFixnum.new(0)

        # Flush mutex (synchronize flush operations)
        @flush_mutex = Mutex.new

        # Early flush callback (optional, for integration with flush worker)
        @early_flush_callback = nil
      end

      # Add event to buffer with memory tracking
      #
      # This is the main entry point for buffering events.
      # Tracks memory usage, enforces limits, triggers early flush if needed.
      #
      # Behavior on memory limit exceeded:
      # - :block - Waits up to max_block_time for space, then drops
      # - :drop - Immediately drops event
      #
      # @param event_data [Hash] Event hash to buffer
      #   - Required keys: :event_name, :payload, :adapters (Array<Symbol>)
      # @return [Boolean] true if event was added, false if dropped
      #
      # @example
      #   success = buffer.add_event({
      #     event_name: "UserSignup",
      #     payload: { user_id: 123 },
      #     adapters: [:logs, :errors_tracker]
      #   })
      #   # => true (or false if dropped due to memory limit)
      def add_event(event_data)
        event_size = estimate_size(event_data)
        current_memory = @total_memory_bytes.value

        # Check memory limit
        return handle_memory_exhaustion(event_data, event_size) if current_memory + event_size > @memory_limit_bytes

        # Add to appropriate adapter buffers
        adapters = event_data[:adapters] || [:default]
        adapters.each do |adapter_key|
          @buffers[adapter_key] ||= []
          @buffers[adapter_key] << event_data
        end

        # Update memory tracking atomically
        @total_memory_bytes.update { |v| v + event_size }

        # Warning threshold - trigger early flush (AFTER adding event to get accurate memory)
        trigger_early_flush if @total_memory_bytes.value > @memory_warning_threshold

        true
      end

      # Flush all buffers and return events
      #
      # Thread-safe operation (uses Mutex).
      # Returns events grouped by adapter, updates memory tracking.
      #
      # @return [Hash] Events grouped by adapter key
      #   - Format: { adapter_key => [event1, event2, ...] }
      #
      # @example
      #   events = buffer.flush
      #   # => { logs: [...], errors_tracker: [...] }
      def flush
        @flush_mutex.synchronize do
          events_by_adapter = {}
          memory_freed = 0

          @buffers.each do |adapter_key, events|
            events_by_adapter[adapter_key] = events.dup

            # Calculate memory freed
            events.each { |event| memory_freed += estimate_size(event) }

            # Clear buffer
            events.clear
          end

          # Update memory tracking atomically
          @total_memory_bytes.update { |v| [v - memory_freed, 0].max }

          events_by_adapter
        end
      end

      # Estimate memory size of event (C20 requirement: ±10% accuracy)
      #
      # Estimates memory footprint including:
      # - Payload JSON size
      # - Ruby object overhead (~200 bytes per Hash)
      # - String overhead (~40 bytes per String key)
      #
      # @param event_data [Hash] Event hash
      # @return [Integer] Estimated size in bytes
      #
      # @example
      #   size = buffer.estimate_size({ event_name: "test", payload: { id: 1 } })
      #   # => ~250 bytes (payload + overhead)
      def estimate_size(event_data)
        # Payload size (deep inspection of strings)
        payload_size = calculate_payload_size(event_data[:payload])

        # Ruby object overhead
        base_overhead = 200 # Hash object (~200 bytes)
        string_overhead = event_data.keys.size * 40 # String keys (~40 bytes each)

        payload_size + base_overhead + string_overhead
      end

      # Get memory statistics for monitoring
      #
      # @return [Hash] Memory stats
      #   - :current_bytes - Current memory usage
      #   - :limit_bytes - Memory limit
      #   - :utilization - Percentage (0-100)
      #   - :buffer_counts - Events per adapter
      #
      # @example
      #   stats = buffer.memory_stats
      #   # => { current_bytes: 1024000, limit_bytes: 104857600, utilization: 0.98, ... }
      def memory_stats
        {
          current_bytes: @total_memory_bytes.value,
          limit_bytes: @memory_limit_bytes,
          utilization: (@total_memory_bytes.value.to_f / @memory_limit_bytes * 100).round(2),
          buffer_counts: @buffers.transform_values(&:size),
          warning_threshold: @memory_warning_threshold
        }
      end

      # Check if buffer is empty
      #
      # @return [Boolean] true if no events buffered
      def empty?
        @buffers.values.all?(&:empty?)
      end

      # Get total number of buffered events
      #
      # @return [Integer] Total events across all adapters
      def size
        @buffers.values.sum(&:size)
      end

      # Register early flush callback
      #
      # Called when buffer reaches 80% memory threshold.
      # Used for integration with background flush worker.
      #
      # @param block [Proc] Callback to invoke on early flush
      # @return [void]
      #
      # @example
      #   buffer.on_early_flush { FlushWorker.trigger_immediate_flush }
      def on_early_flush(&block)
        @early_flush_callback = block
      end

      private

      # Calculate payload size recursively
      #
      # @param obj [Object] Payload object
      # @return [Integer] Size in bytes
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength
      def calculate_payload_size(obj)
        case obj
        when String
          obj.bytesize + 40 # String content + overhead
        when Hash
          obj.sum do |k, v|
            k.to_s.bytesize + 40 + calculate_payload_size(v)
          end
        when Array
          obj.sum { |v| calculate_payload_size(v) } + 40
        when Numeric
          8 # Numbers are typically 8 bytes
        else
          100 # Default for unknown types
        end
      rescue StandardError
        500 # Fallback for errors
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/MethodLength

      # Handle memory exhaustion according to strategy
      #
      # @param event_data [Hash] Event that caused exhaustion
      # @param event_size [Integer] Size of event
      # @return [Boolean] true if event was eventually added, false if dropped
      # rubocop:disable Metrics/MethodLength
      def handle_memory_exhaustion(event_data, event_size)
        case @backpressure_strategy
        when :block
          # Block event ingestion until space available
          wait_start = Time.now

          loop do
            # Check if space available after flush
            current_memory = @total_memory_bytes.value
            break if current_memory + event_size <= @memory_limit_bytes

            # Check timeout
            if Time.now - wait_start > @max_block_time
              # Timeout exceeded - drop event
              increment_metric("e11y.buffer.memory_exhaustion.dropped")
              return false
            end

            # Brief sleep to avoid busy-wait
            sleep 0.01 # 10ms
          end

          # Space available - retry add
          increment_metric("e11y.buffer.memory_exhaustion.blocked")
          add_event(event_data)

        when :drop
          # Drop new event
          increment_metric("e11y.buffer.memory_exhaustion.dropped")
          false
        end
      end
      # rubocop:enable Metrics/MethodLength

      # Trigger early flush (80% threshold reached)
      #
      # Invokes registered callback if available.
      # Used to notify flush worker to flush immediately.
      #
      # @return [void]
      def trigger_early_flush
        return unless @early_flush_callback

        @early_flush_callback.call
      rescue StandardError => e
        # Silently ignore callback errors (don't break event tracking)
        warn "E11y: Early flush callback failed: #{e.message}"
      end

      # Increment metric (placeholder for Phase 3: Metrics)
      #
      # TODO Phase 3: Replace with actual Yabeda metrics
      #
      # @param metric_name [String] Metric to increment
      # @return [void]
      def increment_metric(metric_name)
        # Placeholder - will be implemented in Phase 3
        # Yabeda.e11y.buffer_memory_exhaustion.increment(strategy: @backpressure_strategy)
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end

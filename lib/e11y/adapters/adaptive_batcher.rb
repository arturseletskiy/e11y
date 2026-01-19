# frozen_string_literal: true

module E11y
  module Adapters
    # Adaptive batching helper for adapters
    #
    # Provides efficient event batching with automatic flushing based on:
    # - Batch size threshold (max_size)
    # - Time threshold (timeout)
    # - Minimum batch size (min_size) for latency optimization
    #
    # Thread-safe implementation with mutex-protected buffer.
    #
    # @example Use in adapter
    #   class MyAdapter < E11y::Adapters::Base
    #     def initialize(config = {})
    #       super
    #       @batcher = AdaptiveBatcher.new(
    #         max_size: 500,
    #         timeout: 5.0,
    #         flush_callback: method(:send_batch)
    #       )
    #     end
    #
    #     def write(event_data)
    #       @batcher.add(event_data)
    #     end
    #
    #     def write_batch(events)
    #       @batcher.flush!
    #       super
    #     end
    #
    #     def close
    #       @batcher.close
    #       super
    #     end
    #
    #     private
    #
    #     def send_batch(events)
    #       # Send events to external system
    #       http_client.post(events)
    #     end
    #   end
    #
    # @see ADR-004 Section 8.1 (Adaptive Batching)
    class AdaptiveBatcher
      # Initialize adaptive batcher
      #
      # @param min_size [Integer] Minimum batch size before timeout flush (default: 10)
      # @param max_size [Integer] Maximum batch size (triggers immediate flush, default: 500)
      # @param timeout [Float] Timeout in seconds for automatic flush (default: 5.0)
      # @param flush_callback [Proc, Method] Callback to invoke on flush with events array
      def initialize(flush_callback:, min_size: 10, max_size: 500, timeout: 5.0)
        @min_size = min_size
        @max_size = max_size
        @timeout = timeout
        @flush_callback = flush_callback

        @buffer = []
        @mutex = Mutex.new
        @last_flush = Time.now
        @closed = false
        @timer_thread = nil

        start_timer_thread!
      end

      # Add event to buffer
      #
      # Automatically flushes if max_size reached.
      # Thread-safe operation.
      #
      # @param event_data [Hash] Event to add to buffer
      # @return [Boolean] true if added successfully
      def add(event_data)
        return false if @closed

        @mutex.synchronize do
          @buffer << event_data

          flush_unlocked! if should_flush_immediately?
        end

        true
      end

      # Flush buffer immediately
      #
      # Sends all buffered events to flush_callback.
      # Thread-safe operation.
      #
      # @return [Boolean] true if flushed, false if buffer empty
      def flush!
        @mutex.synchronize { flush_unlocked! }
      end

      # Get current buffer size
      #
      # @return [Integer] Number of events in buffer
      def buffer_size
        @mutex.synchronize { @buffer.size }
      end

      # Check if buffer is empty
      #
      # @return [Boolean] true if buffer is empty
      def empty?
        @mutex.synchronize { @buffer.empty? }
      end

      # Close batcher and flush remaining events
      #
      # Stops timer thread and flushes any remaining events.
      # Safe to call multiple times.
      #
      # @return [void]
      def close
        return if @closed

        @closed = true
        @timer_thread&.kill
        @timer_thread = nil

        flush!
      end

      private

      # Start background timer thread for automatic flushing
      #
      # Timer thread checks periodically if timeout has expired
      # and flushes buffer if min_size threshold is met.
      #
      # Check interval is min(timeout/2, 1 second) for responsiveness.
      #
      # @api private
      def start_timer_thread!
        check_interval = [@timeout / 2.0, 1.0].min

        @timer_thread = Thread.new do
          loop do
            sleep check_interval

            break if @closed

            @mutex.synchronize do
              flush_unlocked! if should_flush_timeout?
            rescue StandardError => e
              warn "[E11y] AdaptiveBatcher timer error: #{e.message}"
            end
          end
        end

        @timer_thread.name = "e11y-adaptive-batcher-timer"
      end

      # Flush buffer (unlocked - must be called within mutex.synchronize)
      #
      # @return [Boolean] true if flushed, false if buffer empty
      # @api private
      def flush_unlocked!
        return false if @buffer.empty?

        events = @buffer.dup
        @buffer.clear
        @last_flush = Time.now

        # Release mutex before I/O operation
        @mutex.unlock
        begin
          @flush_callback.call(events)
          true
        ensure
          @mutex.lock
        end
      end

      # Check if should flush immediately (max_size reached)
      #
      # @return [Boolean]
      # @api private
      def should_flush_immediately?
        @buffer.size >= @max_size
      end

      # Check if should flush on timeout
      #
      # @return [Boolean]
      # @api private
      def should_flush_timeout?
        return false if @buffer.empty?

        timeout_expired? && @buffer.size >= @min_size
      end

      # Check if timeout has expired since last flush
      #
      # @return [Boolean]
      # @api private
      def timeout_expired?
        (Time.now - @last_flush) >= @timeout
      end
    end
  end
end

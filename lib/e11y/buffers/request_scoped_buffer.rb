# frozen_string_literal: true

module E11y
  module Buffers
    # Request-scoped buffer using thread-local storage for debug event buffering.
    #
    # This buffer stores debug events in thread-local storage during request processing.
    # Events are flushed only when an error occurs, keeping logs clean during successful requests.
    #
    # Uses Thread.current for thread-local storage (compatible with any Ruby app, not just Rails).
    # In Rails apps, this works seamlessly with Rack middleware thread model.
    #
    # @example Basic usage
    #   # In Rails middleware
    #   RequestScopedBuffer.initialize!
    #
    #   # Track debug events (buffered)
    #   RequestScopedBuffer.add_event({ event_name: "debug", severity: :debug })
    #
    #   # On error - flush all buffered events
    #   RequestScopedBuffer.flush_on_error
    #
    #   # On success - discard buffered events
    #   RequestScopedBuffer.discard
    #
    # @see UC-001 Request-Scoped Debug Buffering
    class RequestScopedBuffer
      # Thread-local storage keys
      THREAD_KEY_BUFFER = :e11y_request_buffer
      THREAD_KEY_REQUEST_ID = :e11y_request_id
      THREAD_KEY_ERROR_OCCURRED = :e11y_error_occurred
      THREAD_KEY_BUFFER_LIMIT = :e11y_buffer_limit

      # Default buffer limit per request
      DEFAULT_BUFFER_LIMIT = 100

      class << self
        # Initialize request-scoped buffer
        #
        # @param request_id [String, nil] Optional request ID
        # @param buffer_limit [Integer] Max events to buffer (default: 100)
        # @return [void]
        #
        # @example
        #   RequestScopedBuffer.initialize!(request_id: "req-123", buffer_limit: 200)
        def initialize!(request_id: nil, buffer_limit: DEFAULT_BUFFER_LIMIT)
          Thread.current[THREAD_KEY_BUFFER] = []
          Thread.current[THREAD_KEY_REQUEST_ID] = request_id || generate_request_id
          Thread.current[THREAD_KEY_ERROR_OCCURRED] = false
          Thread.current[THREAD_KEY_BUFFER_LIMIT] = buffer_limit
        end

        # Add event to request-scoped buffer
        #
        # Only buffers :debug severity events. Other severities return false.
        # Triggers auto-flush if error severity detected.
        #
        # @param event_data [Hash] Event hash with :severity, :event_name, :payload
        # @return [Boolean] true if buffered, false if not buffered
        #
        # @example
        #   # Debug event - buffered
        #   RequestScopedBuffer.add_event({ event_name: "test", severity: :debug })
        #   # => true
        #
        #   # Error event - not buffered, triggers flush
        #   RequestScopedBuffer.add_event({ event_name: "error", severity: :error })
        #   # => false (and flushes buffer)
        # rubocop:disable Metrics/MethodLength, Naming/PredicateMethod
        def add_event(event_data)
          return false unless active? # Not in request scope

          severity = event_data[:severity]

          # Trigger flush on error severity
          if error_severity?(severity)
            Thread.current[THREAD_KEY_ERROR_OCCURRED] = true
            flush_on_error
            return false # Error events not buffered
          end

          # Only buffer debug events
          return false unless severity == :debug

          current_buffer = buffer
          return false if current_buffer.nil?

          # Check buffer limit
          if current_buffer.size >= buffer_limit
            increment_metric("e11y.request_buffer.overflow")
            return false # Buffer full, drop event
          end

          current_buffer << event_data
          increment_metric("e11y.request_buffer.events_buffered")
          true
        end
        # rubocop:enable Metrics/MethodLength, Naming/PredicateMethod

        # Flush buffered events on error
        #
        # Sends all buffered debug events to the main buffer/adapters.
        # Events keep their original :debug severity.
        #
        # @param target [Symbol, nil] Optional target adapter
        # @return [Integer] Number of events flushed
        #
        # @example
        #   # In rescue block
        #   rescue StandardError => e
        #     RequestScopedBuffer.flush_on_error
        #     raise
        #   end
        def flush_on_error(target: nil)
          current_buffer = buffer
          return 0 if current_buffer.nil? || current_buffer.empty?

          flushed_count = current_buffer.size

          # Flush events to main buffer/adapters
          current_buffer.each do |event_data|
            # TODO: Send to E11y::Collector.collect(event_data) when available
            # For now, placeholder
            flush_event(event_data, target: target)
          end

          current_buffer.clear
          increment_metric("e11y.request_buffer.flushed_on_error", tags: { events: flushed_count })
          flushed_count
        end

        # Discard buffered events (on successful request)
        #
        # @return [Integer] Number of events discarded
        #
        # @example
        #   # In middleware ensure block (success path)
        #   unless RequestScopedBuffer.error_occurred?
        #     RequestScopedBuffer.discard
        #   end
        def discard
          current_buffer = buffer
          return 0 if current_buffer.nil? || current_buffer.empty?

          discarded_count = current_buffer.size
          current_buffer.clear
          increment_metric("e11y.request_buffer.discarded", tags: { events: discarded_count })
          discarded_count
        end

        # Check if request scope is active
        #
        # @return [Boolean] true if buffer initialized
        def active?
          !buffer.nil?
        end

        # Check if error occurred during request
        #
        # @return [Boolean] true if error severity detected
        def error_occurred?
          Thread.current[THREAD_KEY_ERROR_OCCURRED] == true
        end

        # Get current buffer size
        #
        # @return [Integer] Number of buffered events
        def size
          buffer&.size || 0
        end

        # Get current buffer
        #
        # @return [Array, nil] Buffer array or nil if not initialized
        def buffer
          Thread.current[THREAD_KEY_BUFFER]
        end

        # Get current request ID
        #
        # @return [String, nil] Request ID or nil if not initialized
        def request_id
          Thread.current[THREAD_KEY_REQUEST_ID]
        end

        # Reset request scope (cleanup)
        #
        # @return [void]
        def reset_all
          Thread.current[THREAD_KEY_BUFFER] = nil
          Thread.current[THREAD_KEY_REQUEST_ID] = nil
          Thread.current[THREAD_KEY_ERROR_OCCURRED] = nil
          Thread.current[THREAD_KEY_BUFFER_LIMIT] = nil
        end

        private

        # Get buffer limit (with fallback)
        #
        # @return [Integer] Buffer limit
        def buffer_limit
          Thread.current[THREAD_KEY_BUFFER_LIMIT] || DEFAULT_BUFFER_LIMIT
        end

        # Check if severity is error-level
        #
        # @param severity [Symbol] Event severity
        # @return [Boolean] true if :error or :fatal
        def error_severity?(severity)
          %i[error fatal].include?(severity)
        end

        # Generate unique request ID
        #
        # @return [String] UUID request ID
        def generate_request_id
          require "securerandom"
          SecureRandom.uuid
        end

        # Flush single event to adapters
        #
        # Writes event_data directly to each fallback adapter (bypassing the pipeline
        # since events were already validated/filtered on the way in).
        #
        # @param event_data [Hash] Event to flush
        # @param target [Symbol, nil] Optional specific adapter to target
        # @return [void]
        def flush_event(event_data, target: nil)
          adapter_names = if target
                            [target]
                          else
                            E11y.configuration.request_buffer.debug_adapters ||
                              E11y.configuration.fallback_adapters ||
                              [:memory]
                          end

          adapter_names.each do |adapter_name|
            adapter = E11y.configuration.adapters[adapter_name]
            adapter&.write(event_data)
          rescue StandardError => e
            warn "[E11y] Error flushing buffered event to #{adapter_name}: #{e.message}"
          end

          increment_metric("e11y.request_buffer.event_flushed")
        end

        # Increment metric (placeholder)
        #
        # @param metric_name [String] Metric name
        # @param tags [Hash] Optional tags
        # @return [void]
        def increment_metric(metric_name, tags: {})
          # Placeholder for Yabeda integration
          # Will be implemented in Phase 1 L2.4 (Metrics)
        end
      end
    end
  end
end

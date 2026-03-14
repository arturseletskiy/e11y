# frozen_string_literal: true

module E11y
  module Buffers
    # Ephemeral buffer (request/job-scoped) using thread-local storage for debug event buffering.
    #
    # This buffer stores debug events in thread-local storage during request processing.
    # Events are flushed only when an error occurs, keeping logs clean during successful requests.
    #
    # Uses Thread.current for thread-local storage (compatible with any Ruby app, not just Rails).
    # In Rails apps, this works seamlessly with Rack middleware thread model.
    #
    # @example Basic usage
    #   # In Rails middleware
    #   EphemeralBuffer.initialize!
    #
    #   # Track debug events (buffered)
    #   EphemeralBuffer.add_event({ event_name: "debug", severity: :debug })
    #
    #   # On error - flush all buffered events
    #   EphemeralBuffer.flush_on_error
    #
    #   # On success - discard buffered events
    #   EphemeralBuffer.discard
    #
    # @see UC-001 Request-Scoped Debug Buffering
    class EphemeralBuffer
      # Thread-local storage keys
      THREAD_KEY_BUFFER = :e11y_ephemeral_buffer
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
        #   EphemeralBuffer.initialize!(request_id: "req-123", buffer_limit: 200)
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
        #   EphemeralBuffer.add_event({ event_name: "test", severity: :debug })
        #   # => true
        #
        #   # Error event - not buffered, triggers flush
        #   EphemeralBuffer.add_event({ event_name: "error", severity: :error })
        #   # => false (and flushes buffer)
        def add_event(event_data)
          return false unless active?
          return handle_error_event(event_data) if error_severity?(event_data[:severity])
          return false unless event_data[:severity] == :debug

          append_to_buffer(event_data)
        end

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
        #     EphemeralBuffer.flush_on_error
        #     raise
        #   end
        def flush_on_error(target: nil)
          current_buffer = buffer
          return 0 if current_buffer.nil? || current_buffer.empty?

          flushed_count = current_buffer.size

          # Resolve flush targets once per flush (avoids N config lookups when flushing N events)
          flush_targets = resolve_flush_targets

          # Flush events to main buffer/adapters
          current_buffer.each do |event_data|
            # TODO: Send to E11y::Collector.collect(event_data) when available
            # For now, placeholder
            flush_event(event_data, target: target, flush_targets: flush_targets)
          end

          current_buffer.clear
          E11y::Metrics.increment(:e11y_ephemeral_buffer_total, event: "flushed_on_error", value: flushed_count)
          flushed_count
        end

        # Discard buffered events (on successful request)
        #
        # @return [Integer] Number of events discarded
        #
        # @example
        #   # In middleware ensure block (success path)
        #   unless EphemeralBuffer.error_occurred?
        #     EphemeralBuffer.discard
        #   end
        def discard
          current_buffer = buffer
          return 0 if current_buffer.nil? || current_buffer.empty?

          discarded_count = current_buffer.size
          current_buffer.clear
          E11y::Metrics.increment(:e11y_ephemeral_buffer_total, event: "discarded", value: discarded_count)
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

        def handle_error_event(_event_data) # rubocop:disable Naming/PredicateMethod
          Thread.current[THREAD_KEY_ERROR_OCCURRED] = true
          flush_on_error
          false
        end

        def append_to_buffer(event_data)
          current_buffer = buffer
          return false if current_buffer.nil?
          return record_buffer_overflow if current_buffer.size >= buffer_limit

          event_to_store = event_data.merge(request_id: request_id)
          current_buffer << event_to_store
          E11y::Metrics.increment(:e11y_ephemeral_buffer_total, event: "events_buffered")
          true
        end

        def record_buffer_overflow # rubocop:disable Naming/PredicateMethod
          E11y::Metrics.increment(:e11y_ephemeral_buffer_total, event: "overflow")
          false
        end

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

        # Resolve flush targets: adapter instances (when debug_adapters set) or nil (use pipeline).
        # Cached per flush to avoid repeated config lookups when flushing N events.
        #
        # @return [Array<Object>, nil] Adapter instances to write to, or nil to use pipeline
        def resolve_flush_targets
          da = E11y.config.ephemeral_buffer&.debug_adapters
          return nil unless da&.any?

          da.filter_map { |name| E11y.configuration.adapters[name] }
        end

        # Flush single event to adapters via pipeline or debug_adapters
        #
        # When config.ephemeral_buffer.debug_adapters is set, sends directly to those
        # adapters. Otherwise uses the full pipeline (fallback_adapters).
        #
        # @param event_data [Hash] Event to flush
        # @param target [Symbol, nil] Optional target adapter (not yet implemented)
        # @param flush_targets [Array<Object>, nil] Pre-resolved adapter instances (from flush_on_error)
        # @return [void]
        def flush_event(event_data, target: nil, flush_targets: nil) # rubocop:disable Lint/UnusedMethodArgument
          return unless event_data

          event_to_send = event_data.merge(from_ephemeral_buffer_flush: true)
          targets = flush_targets || resolve_flush_targets

          if targets
            targets.each { |adapter| adapter&.write(event_to_send) }
          else
            E11y.config.built_pipeline.call(event_to_send)
          end

          E11y::Metrics.increment(:e11y_ephemeral_buffer_total, event: "event_flushed")
        end
      end
    end
  end
end

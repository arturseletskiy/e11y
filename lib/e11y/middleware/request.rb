# frozen_string_literal: true

module E11y
  module Middleware
    # Rack middleware for request-scoped debug buffer management.
    #
    # This middleware integrates RequestScopedBuffer with the Rack request lifecycle:
    # - Initializes buffer at request start
    # - Flushes buffer on error (exception caught)
    # - Discards buffer on successful request
    # - Cleans up thread-local storage after request
    #
    # @example Add to Rails middleware stack
    #   # config/application.rb
    #   config.middleware.use E11y::Middleware::Request
    #
    # @example Rack app
    #   use E11y::Middleware::Request
    #
    # @see UC-001 Request-Scoped Debug Buffering
    # @see E11y::Buffers::RequestScopedBuffer
    class Request
      # Initialize middleware
      #
      # @param app [#call] Rack application
      # @param options [Hash] Configuration options
      # @option options [Integer] :buffer_limit Buffer size limit (default: 100)
      def initialize(app, options = {})
        @app = app
        @buffer_limit = options[:buffer_limit] || 100
      end

      # Handle Rack request
      #
      # @param env [Hash] Rack environment
      # @return [Array] Rack response tuple [status, headers, body]
      # rubocop:disable Metrics/MethodLength
      def call(env)
        # 1. Initialize request-scoped buffer
        request_id = extract_request_id(env)
        E11y::Buffers::RequestScopedBuffer.initialize!(
          request_id: request_id,
          buffer_limit: @buffer_limit
        )

        # 2. Call application
        status, headers, body = @app.call(env)

        # 3. Success path - discard buffer
        unless E11y::Buffers::RequestScopedBuffer.error_occurred?
          discarded_count = E11y::Buffers::RequestScopedBuffer.discard
          increment_metric("e11y.buffer.debug_events_dropped", discarded_count)
        end

        [status, headers, body]
      rescue StandardError
        # 4. Error path - flush buffer
        flushed_count = E11y::Buffers::RequestScopedBuffer.flush_on_error
        increment_metric("e11y.buffer.request_flushes", 1)
        increment_metric("e11y.buffer.debug_events_flushed", flushed_count)

        # Re-raise exception (don't swallow errors)
        raise
      ensure
        # 5. Cleanup thread-local storage
        E11y::Buffers::RequestScopedBuffer.reset_all
      end
      # rubocop:enable Metrics/MethodLength

      private

      # Extract request ID from Rack environment
      #
      # Tries multiple sources in order:
      # 1. X-Request-ID header (standard)
      # 2. ActionDispatch::RequestId (Rails)
      # 3. Generate new UUID
      #
      # @param env [Hash] Rack environment
      # @return [String] Request ID
      def extract_request_id(env)
        # Try X-Request-ID header
        request_id = env["HTTP_X_REQUEST_ID"]
        return request_id if request_id && !request_id.empty?

        # Try ActionDispatch::RequestId (Rails)
        request_id = env["action_dispatch.request_id"]
        return request_id if request_id && !request_id.empty?

        # Fallback: generate UUID
        require "securerandom"
        SecureRandom.uuid
      end

      # Increment metric (placeholder)
      #
      # @param metric_name [String] Metric name
      # @param value [Integer] Metric value
      # @return [void]
      def increment_metric(metric_name, value)
        # Placeholder for Yabeda integration
        # Will be implemented in Phase 1 L2.4 (Metrics)
        #
        # Future implementation:
        # Yabeda.e11y.send(metric_name).increment(by: value)
      end
    end
  end
end

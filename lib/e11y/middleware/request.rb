# frozen_string_literal: true

require "rack/request"
require "securerandom"

module E11y
  module Middleware
    # Request Middleware for Rails/Rack applications
    #
    # Provides request-scoped context and trace propagation:
    # - Extracts or generates trace_id
    # - Sets up request context (E11y::Current)
    # - Manages request-scoped buffer (optional)
    # - Tracks HTTP request lifecycle
    #
    # @example Basic usage
    #   # Automatically inserted by E11y::Railtie
    #   # app.middleware.insert_before(Rails::Rack::Logger, E11y::Middleware::Request)
    #
    # @example Manual usage (non-Rails)
    #   use E11y::Middleware::Request
    #
    # @see ADR-008 §8.1 (Request Middleware)
    # @see ADR-005 §3 (Trace Context Management)
    class Request
      # Initialize middleware
      # @param app [Object] Rack app
      def initialize(app)
        @app = app
      end

      # Process request
      # @param env [Hash] Rack environment
      # @return [Array] Rack response [status, headers, body]
      # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
      # Rack middleware request processing requires sequential setup of tracing, context, buffer, and SLO tracking
      def call(env)
        request = Rack::Request.new(env)

        # Extract or generate trace_id
        trace_id = extract_trace_id(request) || generate_trace_id
        span_id = generate_span_id

        # Set request context (ActiveSupport::CurrentAttributes)
        E11y::Current.trace_id = trace_id
        E11y::Current.span_id = span_id
        E11y::Current.request_id = request_id(env)
        E11y::Current.user_id = extract_user_id(env)
        E11y::Current.ip_address = request.ip
        E11y::Current.user_agent = request.user_agent
        E11y::Current.request_method = request.request_method
        E11y::Current.request_path = request.path

        # Start request-scoped buffer (for debug events)
        E11y::Buffers::RequestScopedBuffer.initialize! if E11y.config.request_buffer&.enabled

        # Track request start time for SLO
        start_time = Time.now

        # Call next middleware/app
        status, headers, body = @app.call(env)

        # Flush buffer on 5xx responses.
        # Rails' ShowExceptions middleware catches controller exceptions and
        # returns a 500 response rather than letting them propagate, so we
        # must inspect the status code here instead of relying on rescue alone.
        E11y::Buffers::RequestScopedBuffer.flush_on_error if E11y.config.request_buffer&.enabled && status.to_i >= 500

        # Track SLO metrics (if enabled)
        track_http_request_slo(env, status, start_time)

        # Add trace headers to response
        headers["X-E11y-Trace-Id"] = trace_id
        headers["X-E11y-Span-Id"] = span_id

        [status, headers, body]
      rescue StandardError
        # Fallback: flush buffer if exception propagated past ShowExceptions
        # (e.g., custom middleware ordering or non-Rails Rack apps)
        E11y::Buffers::RequestScopedBuffer.flush_on_error if E11y.config.request_buffer&.enabled

        raise # Re-raise original exception
      ensure
        if E11y.config.request_buffer&.enabled
          # Discard remaining events on success (noop if buffer already flushed/empty)
          E11y::Buffers::RequestScopedBuffer.discard unless $ERROR_INFO
          # Always reset thread-local buffer so next request starts clean
          E11y::Buffers::RequestScopedBuffer.reset_all
        end

        # Reset context
        E11y::Current.reset
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      private

      # Extract trace_id from request headers (W3C Trace Context or custom headers)
      # @param request [Rack::Request] Rack request
      # @return [String, nil] Trace ID or nil if not found
      def extract_trace_id(request)
        # W3C Trace Context (traceparent header)
        # Format: version-trace_id-span_id-flags
        # Example: 00-0af7651916cd43dd8448eb211c80319c-00f067aa0ba902b7-01
        traceparent = request.get_header("HTTP_TRACEPARENT")
        return traceparent.split("-")[1] if traceparent

        # X-Request-ID (Rails default)
        request.get_header("HTTP_X_REQUEST_ID") ||
          # X-Trace-Id (custom)
          request.get_header("HTTP_X_TRACE_ID")
      end

      # Extract request_id from Rack env
      # @param env [Hash] Rack environment
      # @return [String] Request ID
      def request_id(env)
        env["action_dispatch.request_id"] || generate_trace_id
      end

      # Generate new trace_id
      # @return [String] 32-character hex trace ID
      def generate_trace_id
        SecureRandom.hex(16)
      end

      # Generate new span_id
      # @return [String] 16-character hex span ID
      def generate_span_id
        SecureRandom.hex(8)
      end

      # Extract user_id from Rack env (Warden, Devise, or session)
      # @param env [Hash] Rack environment
      # @return [Integer, String, nil] User ID if available
      def extract_user_id(env)
        # Warden (Devise)
        return env["warden"]&.user&.id if env["warden"]

        # Rack session
        env["rack.session"]&.[]("user_id")
      end

      # Track HTTP request for SLO metrics (if enabled).
      #
      # @param env [Hash] Rack environment
      # @param status [Integer] HTTP status code
      # @param start_time [Time] Request start time
      # @return [void]
      # @api private
      # SLO tracking requires extracting controller/action, calculating duration, and error handling
      def track_http_request_slo(env, status, start_time)
        return unless E11y.config.slo_tracking&.enabled

        duration_ms = ((Time.now - start_time) * 1000).round(2)

        # Extract controller and action from Rails routing
        controller = env["action_controller.instance"]&.controller_name || "unknown"
        action = env["action_controller.instance"]&.action_name || "unknown"

        require "e11y/slo/tracker"
        E11y::SLO::Tracker.track_http_request(
          controller: controller,
          action: action,
          status: status,
          duration_ms: duration_ms
        )
      rescue StandardError => e
        # Don't fail if SLO tracking fails
        warn "[E11y] SLO tracking error: #{e.message}"
      end
    end
  end
end

# frozen_string_literal: true

require "rack/request"
require "securerandom"
require "e11y/tracing/propagator"
require "e11y/trace_context/sampler"

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

        # Extract or generate trace context (trace_id, sampled from traceparent)
        trace_ctx = extract_trace_context(request)
        trace_id = trace_ctx[:trace_id] || generate_trace_id
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
        E11y::Current.sampled = resolve_sampled(trace_ctx)

        # Start request-scoped buffer (for debug events)
        E11y::Buffers::EphemeralBuffer.initialize! if E11y.config.ephemeral_buffer_enabled

        # Track request start time for SLO
        start_time = Time.now

        # Call next middleware/app
        status, headers, body = @app.call(env)

        # Flush buffer if status matches configured flush_on_statuses (default: 5xx only)
        E11y::Buffers::EphemeralBuffer.flush_on_error if should_flush_buffer?(status)

        # Track SLO metrics (if enabled)
        track_http_request_slo(env, status, start_time)

        # Add trace headers to response
        headers["X-E11y-Trace-Id"] = trace_id
        headers["X-E11y-Span-Id"] = span_id

        [status, headers, body]
      rescue StandardError
        # Flush request buffer on error (includes debug events)
        E11y::Buffers::EphemeralBuffer.flush_on_error if E11y.config.ephemeral_buffer_enabled

        raise # Re-raise original exception
      ensure
        # Discard request buffer on success (not on error, already flushed above)
        # We need to check if we're here from normal completion or exception
        # If there was an exception, buffer was already flushed in rescue block
        E11y::Buffers::EphemeralBuffer.discard if !$ERROR_INFO && E11y.config.ephemeral_buffer_enabled # No exception occurred

        # Reset context
        E11y::Current.reset
      end
      # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

      private

      # Determine whether the request-scoped buffer should be flushed for this status code.
      #
      # Two independent conditions (either is sufficient):
      # - +flush_on_error+ (default: true) — flushes on any 5xx server error
      # - +flush_on_statuses+ (default: []) — extra status codes/ranges, e.g. [403]
      #
      # @example Default behaviour — flush on 5xx only
      #   config.ephemeral_buffer_flush_on_error   = true  # default
      #   config.ephemeral_buffer_flush_on_statuses = []   # default
      #
      # @example Flush on 403 in addition to 5xx
      #   config.ephemeral_buffer_flush_on_statuses = [403]
      #
      # @example Flush only on explicit statuses (disable 5xx default)
      #   config.ephemeral_buffer_flush_on_error    = false
      #   config.ephemeral_buffer_flush_on_statuses = [403, 422]
      #
      # @param status [Integer] HTTP response status code
      # @return [Boolean]
      def should_flush_buffer?(status)
        return false unless E11y.config.ephemeral_buffer_enabled

        # Condition 1: server error flush (5xx)
        return true if E11y.config.ephemeral_buffer_flush_on_error && status >= 500

        # Condition 2: explicit extra statuses
        extra = E11y.config.ephemeral_buffer_flush_on_statuses
        extra&.any? { |s| s === status } || false # rubocop:disable Style/CaseEquality
      end

      # Extract trace context from request headers (W3C Trace Context or custom).
      # Also extracts tracestate into E11y::Current.baggage (F-014).
      # @param request [Rack::Request] Rack request
      # @return [Hash] { trace_id:, sampled: (from traceparent, or nil if new trace) }
      def extract_trace_context(request)
        traceparent = request.get_header("HTTP_TRACEPARENT")
        tracestate = request.get_header("HTTP_TRACESTATE")

        if tracestate && E11y::Current.respond_to?(:baggage=)
          baggage = E11y::Tracing::Propagator.parse_tracestate(tracestate)
          E11y::Current.baggage = baggage if baggage.any?
        end

        if traceparent
          parsed = E11y::Tracing::Propagator.parse(traceparent)
          return { trace_id: parsed[:trace_id], sampled: parsed[:sampled] } if parsed
        end

        trace_id = request.get_header("HTTP_X_REQUEST_ID") || request.get_header("HTTP_X_TRACE_ID")
        { trace_id: trace_id, sampled: nil }
      end

      # Resolve sampling decision: from parent (traceparent) or Sampler for new trace.
      # Context for Sampler = E11y::Current.to_context (already set above).
      def resolve_sampled(trace_ctx)
        return trace_ctx[:sampled] if trace_ctx.key?(:sampled) && !trace_ctx[:sampled].nil?

        E11y::TraceContext::Sampler.should_sample?(E11y::Current.to_context)
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
        return unless E11y.config.respond_to?(:slo_tracking_enabled) && E11y.config.slo_tracking_enabled

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

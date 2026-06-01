# frozen_string_literal: true

module E11y
  module Middleware
    # Sets Thread.current[:e11y_source] = "web" during a web request.
    # Also captures HTTP method, path, status, and duration for DevLog enrichment.
    # All keys are cleared after the request completes (even on exception).
    #
    # Also propagates trace_id to Rack env for the Browser Overlay:
    # env["e11y.trace_id"] is set from Thread.current[:e11y_trace_id].
    class DevLogSource
      def initialize(app)
        @app = app
      end

      # rubocop:disable Metrics/AbcSize -- Rack call + timing + Thread locals + ensure cleanup
      def call(env)
        Thread.current[:e11y_source] = "web"
        Thread.current[:e11y_http_method] = env["REQUEST_METHOD"]
        Thread.current[:e11y_http_path]   = env["PATH_INFO"]
        env["e11y.trace_id"] ||= Thread.current[:e11y_trace_id]

        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        status, headers, body = @app.call(env)

        elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
        Thread.current[:e11y_http_status]      = status
        Thread.current[:e11y_http_duration_ms] = elapsed_ms

        [status, headers, body]
      ensure
        Thread.current[:e11y_source]           = nil
        Thread.current[:e11y_http_method]      = nil
        Thread.current[:e11y_http_path]        = nil
        Thread.current[:e11y_http_status]      = nil
        Thread.current[:e11y_http_duration_ms] = nil
      end
      # rubocop:enable Metrics/AbcSize
    end
  end
end

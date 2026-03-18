# frozen_string_literal: true

module E11y
  module Middleware
    # Sets Thread.current[:e11y_source] = "web" during a web request.
    # Cleared after the request completes (even on exception).
    #
    # Also propagates trace_id to Rack env for the Browser Overlay:
    # env["e11y.trace_id"] is set from Thread.current[:e11y_trace_id].
    class DevLogSource
      def initialize(app)
        @app = app
      end

      def call(env)
        Thread.current[:e11y_source] = "web"
        env["e11y.trace_id"] ||= Thread.current[:e11y_trace_id]
        @app.call(env)
      ensure
        Thread.current[:e11y_source] = nil
      end
    end
  end
end

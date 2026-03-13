# frozen_string_literal: true

# This file is only loaded explicitly via E11y::Tracing.install_faraday_middleware!
# (which calls require "faraday" first) and is NOT autoloaded by Zeitwerk on startup.
# Faraday is an optional dependency — see e11y.gemspec.

module E11y
  module Tracing
    # Faraday middleware that injects W3C traceparent header into outgoing requests.
    #
    # Register once via E11y::Tracing.install_faraday_middleware!, then use per connection:
    #
    #   conn = Faraday.new(url: "https://api.example.com") do |f|
    #     f.request :e11y_tracing
    #     f.adapter Faraday.default_adapter
    #   end
    #
    # @see E11y::Tracing.install_faraday_middleware!
    # @see E11y::Tracing::Propagator
    class FaradayMiddleware < ::Faraday::Middleware
      # Inject traceparent into outgoing request headers and pass to next middleware.
      #
      # @param env [Faraday::Env] Faraday request environment
      # @return [Faraday::Response]
      def call(env)
        Propagator.inject(env.request_headers)
        @app.call(env)
      end
    end
  end
end

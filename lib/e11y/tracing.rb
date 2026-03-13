# frozen_string_literal: true

module E11y
  # Outgoing HTTP trace context propagation (UC-009).
  #
  # Provides W3C Trace Context injection into outgoing HTTP requests
  # via Faraday middleware and Net::HTTP monkey-patch.
  #
  # @example Enable Net::HTTP tracing
  #   E11y::Tracing.patch_net_http!
  #
  # @example Enable Faraday tracing (register middleware, then use in connection)
  #   E11y::Tracing.install_faraday_middleware!
  #   conn = Faraday.new { |f| f.request :e11y_tracing }
  #
  # @see UC-009 Multi-Service Tracing
  # @see https://www.w3.org/TR/trace-context/
  module Tracing
    # Install Net::HTTP tracing patch (idempotent).
    #
    # Prepends E11y::Tracing::NetHTTPPatch into Net::HTTP so that every
    # outgoing request automatically carries a W3C traceparent header.
    #
    # @return [void]
    def self.patch_net_http!
      require "net/http"
      require "e11y/tracing/net_http_patch"
      return if ::Net::HTTP <= E11y::Tracing::NetHTTPPatch

      ::Net::HTTP.prepend(E11y::Tracing::NetHTTPPatch)
    end

    # Register the Faraday middleware so it can be referenced by name (idempotent).
    #
    # After calling this, add +f.request :e11y_tracing+ to any Faraday connection
    # that should propagate trace context.
    #
    # @return [void]
    def self.install_faraday_middleware!
      require "faraday"
      require "e11y/tracing/faraday_middleware"
      return if ::Faraday::Request.registered_middleware.key?(:e11y_tracing)

      ::Faraday::Request.register_middleware(e11y_tracing: E11y::Tracing::FaradayMiddleware)
    end
  end
end

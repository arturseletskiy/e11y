# frozen_string_literal: true

module E11y
  module Middleware
    # BaggageProtection middleware — blocks PII from OpenTelemetry Baggage (ADR-006 §5.5, C08).
    #
    # When enabled, prepends an interceptor to OpenTelemetry::Baggage that blocks
    # set_value calls for keys not in the allowlist. Prevents PII from propagating
    # via W3C Baggage headers to downstream services.
    #
    # @example Configuration
    #   E11y.configure do |config|
    #     config.security.baggage_protection do
    #       enabled true
    #       allowed_keys %w[trace_id span_id environment version service_name request_id]
    #       block_mode :warn  # :silent, :warn, :raise
    #     end
    #   end
    #
    # @see ADR-006 §5.5 OpenTelemetry Baggage PII Protection
    # @see CONFLICT-ANALYSIS.md C08
    class BaggageProtection < Base
      middleware_zone :security

      def initialize(app)
        super(app)
        @protected = false
      end

      def call(event_data)
        protect_baggage! if should_protect?
        @app.call(event_data)
      end

      private

      def should_protect?
        return false unless defined?(OpenTelemetry::Baggage)
        return false unless config&.enabled

        true
      end

      def config
        E11y.config&.security&.baggage_protection
      end

      def protect_baggage!
        return if @protected

        @protected = true
        allowed_keys = (config.allowed_keys || E11y::BaggageProtectionConfig::DEFAULT_ALLOWED_KEYS).map(&:to_s)
        block_mode = config.block_mode || :silent
        logger = E11y.logger

        interceptor = build_interceptor(allowed_keys, block_mode, logger)
        # Baggage uses extend self, so prepend to the module (instance methods become singleton)
        OpenTelemetry::Baggage.prepend(interceptor)
      end

      def build_interceptor(allowed_keys, block_mode, logger)
        Module.new do
          define_method(:set_value) do |key, value, metadata: nil, context: nil|
            ctx = context || (defined?(OpenTelemetry::Context) && OpenTelemetry::Context.current)
            unless allowed_keys.include?(key.to_s)
              message = "[E11y] Blocked PII from OpenTelemetry baggage: key=#{key.inspect}"
              case block_mode
              when :silent then logger&.debug(message)
              when :warn then logger&.warn(message)
              when :raise then raise E11y::BaggagePiiError, "#{message}. Only allowed keys: #{allowed_keys.join(', ')}"
              end
              return ctx
            end
            super(key, value, metadata: metadata, context: ctx)
          end
        end
      end
    end

  end
end

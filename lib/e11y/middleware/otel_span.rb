# frozen_string_literal: true

module E11y
  module Middleware
    # OtelSpan middleware — creates OpenTelemetry spans from events (ADR-007 §6, F2).
    #
    # When config.opentelemetry_span_creation_patterns is set, creates OTel spans
    # for matching events. Errors/fatal always create spans.
    #
    # @see E11y::OpenTelemetry::SpanCreator
    # @see ADR-007 §6 Traces Signal Export
    class OtelSpan < Base
      middleware_zone :adapters

      def call(event_data)
        if defined?(::OpenTelemetry::Trace) && defined?(E11y::OpenTelemetry::SpanCreator)
          E11y::OpenTelemetry::SpanCreator.create_span_from_event(event_data)
        end
        @app.call(event_data)
      end
    end
  end
end

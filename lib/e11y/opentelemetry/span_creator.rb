# frozen_string_literal: true

require "e11y/opentelemetry/semantic_conventions"

module E11y
  module OpenTelemetry
    # Creates OpenTelemetry spans from E11y events (ADR-007 §6, F2).
    #
    # When enabled via config.opentelemetry_span_creation_patterns, creates
    # OTel spans for matching events. Errors/fatal always create spans.
    # Uses SemanticConventions for attribute mapping when applicable.
    #
    # @example Configuration
    #   E11y.configure do |config|
    #     config.opentelemetry_span_creation_patterns = ["order.*", "payment.*"]
    #   end
    #
    # @see ADR-007 §6 Traces Signal Export
    # @see E11y::OpenTelemetry::SemanticConventions
    class SpanCreator
      ATTR_EVENT_NAME = "event.name"
      ATTR_SEVERITY = "event.severity"
      ATTR_E11Y_TRACE_ID = "e11y.trace_id"
      ATTR_E11Y_SPAN_ID = "e11y.span_id"

      class << self
        def create_span_from_event(event_data)
          return unless defined?(::OpenTelemetry::Trace)
          return unless should_create_span?(event_data)

          tracer = ::OpenTelemetry.tracer_provider.tracer("e11y", E11y::VERSION)
          parent_ctx = ::OpenTelemetry::Context.current
          start_ts = time_to_nano(event_data[:timestamp] || Time.now)

          span = tracer.start_span(
            span_name(event_data),
            with_parent: parent_ctx,
            kind: span_kind(event_data),
            start_timestamp: start_ts
          )

          set_attributes(span, event_data)
          set_status(span, event_data)
          record_exception(span, event_data) if event_data[:severity].in?(%i[error fatal])

          end_ts = compute_end_timestamp(event_data)
          span.finish(end_timestamp: end_ts)

          span
        end

        private

        def span_name(event_data)
          event_data[:event_name].to_s.presence || "e11y.event"
        end

        def set_attributes(span, event_data)
          span.set_attribute(ATTR_EVENT_NAME, event_data[:event_name].to_s)
          span.set_attribute(ATTR_SEVERITY, event_data[:severity].to_s)
          span.set_attribute(ATTR_E11Y_TRACE_ID, event_data[:trace_id].to_s) if event_data[:trace_id]
          span.set_attribute(ATTR_E11Y_SPAN_ID, event_data[:span_id].to_s) if event_data[:span_id]

          payload = event_data[:payload] || {}
          return if payload.empty?

          mapped = E11y::OpenTelemetry::SemanticConventions.map(event_data[:event_name].to_s, payload)
          mapped.each do |key, value|
            next if value.nil?

            span.set_attribute(key.to_s, otel_value(value))
          rescue ArgumentError, TypeError
            span.set_attribute(key.to_s, value.to_s)
          end
        end

        def otel_value(value)
          case value
          when TrueClass, FalseClass then value
          when Integer then value
          when Float then value
          when String then value
          when Symbol then value.to_s
          when Array then value.map(&:to_s)
          else value.to_s
          end
        end

        def set_status(span, event_data)
          if event_data[:severity].in?(%i[error fatal])
            msg = event_data.dig(:payload, :error_message) ||
                  event_data.dig(:payload, "error_message") || "Error"
            span.status = ::OpenTelemetry::Trace::Status.error(msg.to_s)
          else
            span.status = ::OpenTelemetry::Trace::Status.ok
          end
        end

        def record_exception(span, event_data)
          exc = event_data[:exception] || event_data.dig(:payload, :exception) || event_data.dig(:payload, "exception")
          span.record_exception(exc) if exc.is_a?(Exception)
        end

        def compute_end_timestamp(event_data)
          start = event_data[:timestamp] || Time.now
          start_ns = time_to_nano(start)
          if event_data[:duration_ms]
            start_ns + (event_data[:duration_ms].to_f * 1_000_000).to_i
          else
            time_to_nano(Time.now)
          end
        end

        def should_create_span?(event_data)
          return true if event_data[:severity].in?(%i[error fatal])

          patterns = E11y.config&.opentelemetry_span_creation_patterns || []
          event_name = event_data[:event_name].to_s
          return false if event_name.empty?

          patterns.any? { |p| File.fnmatch(p.to_s, event_name) }
        end

        def span_kind(event_data)
          kind = (event_data[:span_kind] || :internal).to_sym
          case kind
          when :server then ::OpenTelemetry::Trace::SpanKind::SERVER
          when :client then ::OpenTelemetry::Trace::SpanKind::CLIENT
          when :producer then ::OpenTelemetry::Trace::SpanKind::PRODUCER
          when :consumer then ::OpenTelemetry::Trace::SpanKind::CONSUMER
          else ::OpenTelemetry::Trace::SpanKind::INTERNAL
          end
        rescue StandardError
          ::OpenTelemetry::Trace::SpanKind::INTERNAL
        end

        def time_to_nano(time)
          return (Time.now.to_f * 1_000_000_000).to_i if time.nil?

          time = Time.parse(time.to_s) if time.is_a?(String)
          (time.to_f * 1_000_000_000).to_i
        end
      end
    end
  end
end

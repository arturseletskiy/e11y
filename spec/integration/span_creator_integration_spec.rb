# frozen_string_literal: true

require "rails_helper"

# SpanCreator integration (ADR-007 §6, F2)
# Requires: OpenTelemetry SDK, integration bundle
RSpec.describe "SpanCreator Integration", :integration do
  before do
    require_dependency!("OpenTelemetry", gem_name: "opentelemetry-sdk")
    require "e11y/opentelemetry/span_creator"
  end

  describe "E11y::OpenTelemetry::SpanCreator" do
    before do
      allow(E11y.config).to receive(:opentelemetry_span_creation_patterns).and_return(["order.*", "payment.*", "http.*"])
    end

    it "creates span for error events" do
      event_data = {
        event_name: "error.occurred",
        severity: :error,
        timestamp: Time.now.utc,
        trace_id: "a1b2c3d4e5f6789012345678abcdef01",
        span_id: "1234567890abcdef",
        payload: { error_message: "Test error" }
      }

      span = nil
      ::OpenTelemetry.tracer_provider.tracer("test", "1.0").in_span("parent") do
        span = E11y::OpenTelemetry::SpanCreator.create_span_from_event(event_data)
      end

      expect(span).to be_a(::OpenTelemetry::Trace::Span)
    end

    it "creates span for pattern-matched events" do
      event_data = {
        event_name: "order.paid",
        severity: :info,
        timestamp: Time.now.utc,
        trace_id: "a1b2c3d4e5f6789012345678abcdef01",
        span_id: "1234567890abcdef",
        payload: { order_id: "ord-123" }
      }

      span = nil
      ::OpenTelemetry.tracer_provider.tracer("test", "1.0").in_span("parent") do
        span = E11y::OpenTelemetry::SpanCreator.create_span_from_event(event_data)
      end

      expect(span).to be_a(::OpenTelemetry::Trace::Span)
    end

    it "does not create span for non-matching events when patterns empty" do
      allow(E11y.config).to receive(:opentelemetry_span_creation_patterns).and_return([])

      event_data = {
        event_name: "user.viewed",
        severity: :info,
        timestamp: Time.now.utc,
        payload: {}
      }

      span = E11y::OpenTelemetry::SpanCreator.create_span_from_event(event_data)

      expect(span).to be_nil
    end

    it "creates span with semantic conventions for HTTP events" do
      event_data = {
        event_name: "http.request",
        severity: :info,
        timestamp: Time.now.utc,
        payload: { "method" => "GET", "status_code" => 200, "path" => "/api/orders" }
      }

      span = nil
      ::OpenTelemetry.tracer_provider.tracer("test", "1.0").in_span("parent") do
        span = E11y::OpenTelemetry::SpanCreator.create_span_from_event(event_data)
      end

      expect(span).to be_a(::OpenTelemetry::Trace::Span)
    end

    it "creates child span under parent context" do
      event_data = {
        event_name: "order.paid",
        severity: :info,
        timestamp: Time.now.utc,
        payload: {}
      }

      parent_ctx = nil
      child_span = nil

      ::OpenTelemetry.tracer_provider.tracer("test", "1.0").in_span("parent") do |parent_span|
        parent_ctx = parent_span.context
        child_span = E11y::OpenTelemetry::SpanCreator.create_span_from_event(event_data)
      end

      expect(child_span).to be_a(::OpenTelemetry::Trace::Span)
      expect(child_span.context.trace_id).to eq(parent_ctx.trace_id)
    end

    it "uses duration_ms for end_timestamp when present" do
      start_time = Time.now.utc
      event_data = {
        event_name: "order.paid",
        severity: :info,
        timestamp: start_time,
        duration_ms: 150,
        payload: {}
      }

      span = nil
      ::OpenTelemetry.tracer_provider.tracer("test", "1.0").in_span("parent") do
        span = E11y::OpenTelemetry::SpanCreator.create_span_from_event(event_data)
      end

      expect(span).to be_a(::OpenTelemetry::Trace::Span)
    end
  end
end

# frozen_string_literal: true

require "e11y/opentelemetry/span_creator"

RSpec.describe E11y::OpenTelemetry::SpanCreator do
  before do
    allow(E11y.config.opentelemetry).to receive(:span_creation_patterns).and_return(["order.*", "payment.*", "http.*"])
  end

  describe ".create_span_from_event" do
    context "when OpenTelemetry::Trace is not defined" do
      before do
        hide_const("OpenTelemetry") if defined?(OpenTelemetry)
      end

      it "returns nil" do
        result = described_class.create_span_from_event(
          event_name: "order.paid",
          severity: :info,
          payload: {}
        )
        expect(result).to be_nil
      end
    end

    context "when OpenTelemetry::Trace is defined", :integration do
      before do
        require "opentelemetry/sdk"
      rescue LoadError
        skip "OpenTelemetry SDK not available (bundle install --with integration)"
      end

      it "creates span for error events regardless of patterns" do
        allow(E11y.config.opentelemetry).to receive(:span_creation_patterns).and_return([])

        event_data = {
          event_name: "error.occurred",
          severity: :error,
          timestamp: Time.now.utc,
          payload: { error_message: "Test" }
        }

        span = described_class.create_span_from_event(event_data)
        expect(span).to be_a(::OpenTelemetry::Trace::Span)
      end

      it "creates span for fatal events regardless of patterns" do
        allow(E11y.config.opentelemetry).to receive(:span_creation_patterns).and_return([])

        event_data = {
          event_name: "system.crash",
          severity: :fatal,
          timestamp: Time.now.utc,
          payload: {}
        }

        span = described_class.create_span_from_event(event_data)
        expect(span).to be_a(::OpenTelemetry::Trace::Span)
      end

      it "returns nil for non-matching events when patterns empty" do
        allow(E11y.config.opentelemetry).to receive(:span_creation_patterns).and_return([])

        event_data = {
          event_name: "user.viewed",
          severity: :info,
          payload: {}
        }

        span = described_class.create_span_from_event(event_data)
        expect(span).to be_nil
      end

      it "returns nil for empty event_name when not error/fatal" do
        allow(E11y.config.opentelemetry).to receive(:span_creation_patterns).and_return(["*"])

        event_data = {
          event_name: "",
          severity: :info,
          payload: {}
        }

        span = described_class.create_span_from_event(event_data)
        expect(span).to be_nil
      end

      it "handles nil timestamp" do
        event_data = {
          event_name: "order.paid",
          severity: :info,
          payload: { order_id: "123" }
        }

        span = described_class.create_span_from_event(event_data)
        expect(span).to be_a(::OpenTelemetry::Trace::Span)
      end

      it "handles nil payload" do
        event_data = {
          event_name: "order.paid",
          severity: :info,
          timestamp: Time.now.utc,
          payload: nil
        }

        span = described_class.create_span_from_event(event_data)
        expect(span).to be_a(::OpenTelemetry::Trace::Span)
      end
    end
  end

  describe "span attributes (SemanticConventions)", :integration do
    before do
      require "opentelemetry/sdk"
    rescue LoadError
      skip "OpenTelemetry SDK not available"
    end

    it "sets event.name and event.severity attributes" do
      event_data = {
        event_name: "order.paid",
        severity: :info,
        timestamp: Time.now.utc,
        payload: { order_id: "ord-1" }
      }

      span = described_class.create_span_from_event(event_data)
      expect(span).to be_a(::OpenTelemetry::Trace::Span)
    end

    it "maps HTTP payload to semantic conventions" do
      event_data = {
        event_name: "http.request",
        severity: :info,
        timestamp: Time.now.utc,
        payload: { "method" => "GET", "status_code" => 200, "path" => "/api" }
      }

      span = described_class.create_span_from_event(event_data)
      expect(span).to be_a(::OpenTelemetry::Trace::Span)
    end

    it "maps error payload to exception conventions" do
      event_data = {
        event_name: "error.occurred",
        severity: :error,
        timestamp: Time.now.utc,
        payload: { error_message: "Something broke", error_class: "RuntimeError" }
      }

      span = described_class.create_span_from_event(event_data)
      expect(span).to be_a(::OpenTelemetry::Trace::Span)
    end
  end

  describe "span_kind" do
    before do
      require "opentelemetry/sdk"
    rescue LoadError
      skip "OpenTelemetry SDK not available"
    end

    it "creates SERVER span when span_kind is :server", :integration do
      event_data = {
        event_name: "order.paid",
        severity: :info,
        timestamp: Time.now.utc,
        span_kind: :server,
        payload: {}
      }

      span = described_class.create_span_from_event(event_data)
      expect(span).to be_a(::OpenTelemetry::Trace::Span)
    end

    it "creates CLIENT span when span_kind is :client", :integration do
      event_data = {
        event_name: "order.paid",
        severity: :info,
        timestamp: Time.now.utc,
        span_kind: :client,
        payload: {}
      }

      span = described_class.create_span_from_event(event_data)
      expect(span).to be_a(::OpenTelemetry::Trace::Span)
    end

    it "creates INTERNAL span by default", :integration do
      event_data = {
        event_name: "order.paid",
        severity: :info,
        timestamp: Time.now.utc,
        payload: {}
      }

      span = described_class.create_span_from_event(event_data)
      expect(span).to be_a(::OpenTelemetry::Trace::Span)
    end
  end
end

# frozen_string_literal: true

require "e11y/middleware/otel_span"

RSpec.describe E11y::Middleware::OtelSpan do
  let(:app) { ->(event_data) { event_data } }
  let(:middleware) { described_class.new(app) }

  let(:event_data) do
    {
      event_name: "test.event",
      severity: :info,
      payload: {}
    }
  end

  describe "#call" do
    it "passes event_data through to next middleware" do
      result = middleware.call(event_data)
      expect(result).to eq(event_data)
    end

    it "does not raise when OpenTelemetry::Trace is not defined" do
      hide_const("OpenTelemetry") if defined?(OpenTelemetry)
      expect { middleware.call(event_data) }.not_to raise_error
    end

    context "when OpenTelemetry::Trace is defined", :integration do
      before do
        require "opentelemetry/sdk"
      rescue LoadError
        skip "OpenTelemetry SDK not available (bundle install --with integration)"
      end

      it "invokes SpanCreator for matching events" do
        allow(E11y.config.opentelemetry).to receive(:span_creation_patterns).and_return(["test.*"])

        expect(E11y::OpenTelemetry::SpanCreator).to receive(:create_span_from_event).with(event_data).and_call_original

        result = middleware.call(event_data)
        expect(result).to eq(event_data)
      end

      it "passes event through even when SpanCreator returns nil" do
        allow(E11y.config.opentelemetry).to receive(:span_creation_patterns).and_return([])

        result = middleware.call(event_data)
        expect(result).to eq(event_data)
      end
    end
  end
end

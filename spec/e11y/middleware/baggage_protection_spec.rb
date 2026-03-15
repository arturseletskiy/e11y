# frozen_string_literal: true

require "e11y/middleware/baggage_protection"

RSpec.describe E11y::Middleware::BaggageProtection do
  let(:app) { ->(event_data) { event_data } }
  let(:middleware) { described_class.new(app) }

  let(:event_data) do
    {
      event_name: "test.event",
      severity: :info,
      payload: {}
    }
  end

  before do
    allow(E11y).to receive(:config).and_return(config_double)
    allow(E11y).to receive(:logger).and_return(logger)
  end

  let(:config_double) do
    instance_double(E11y::Configuration, security: security_config, enabled: true)
  end

  let(:security_config) do
    instance_double(E11y::SecurityConfig, baggage_protection: baggage_config)
  end

  let(:baggage_config) do
    instance_double(
      E11y::BaggageProtectionConfig,
      enabled: true,
      allowed_keys: %w[trace_id span_id request_id],
      block_mode: :silent
    )
  end

  let(:logger) { instance_double(Logger, debug: nil, warn: nil) }

  describe "#call" do
    it "passes event_data through to next middleware" do
      result = middleware.call(event_data)
      expect(result).to eq(event_data)
    end

    context "when OpenTelemetry::Baggage is not loaded" do
      before do
        hide_const("OpenTelemetry") if defined?(OpenTelemetry)
      end

      it "no-ops and passes event through" do
        result = middleware.call(event_data)
        expect(result).to eq(event_data)
      end
    end

    context "when OpenTelemetry::Baggage is loaded", :opentelemetry do
      before do
        begin
          require "opentelemetry/sdk"
        rescue LoadError
          skip "OpenTelemetry SDK not available (bundle config set --local with integration)"
        end
        skip "OpenTelemetry::Baggage not available" unless defined?(OpenTelemetry::Baggage)
      end

      it "prepends interceptor on first call" do
        # Ensure we're first to prepend (no prior BaggageProtection run in this process)
        middleware.call(event_data)

        ctx = OpenTelemetry::Context.current
        result_ctx = OpenTelemetry::Baggage.set_value("user_email", "pii@example.com", context: ctx)

        # When protection is active, PII key is blocked (not in returned context)
        values = OpenTelemetry::Baggage.values(context: result_ctx)
        expect(values).not_to have_key("user_email")
      end

      it "allows keys in allowlist" do
        middleware.call(event_data)

        ctx = OpenTelemetry::Context.current
        result_ctx = OpenTelemetry::Baggage.set_value("trace_id", "abc123", context: ctx)

        expect(OpenTelemetry::Baggage.values(context: result_ctx)["trace_id"]).to eq("abc123")
      end

      it "only prepends once (idempotent)" do
        middleware.call(event_data)
        middleware.call(event_data)

        # Should not raise (multiple prepends would cause issues)
        ctx = OpenTelemetry::Context.current
        OpenTelemetry::Baggage.set_value("user_email", "pii@example.com", context: ctx)
      end
    end

    context "when config.security.baggage_protection.enabled is false" do
      before do
        allow(baggage_config).to receive(:enabled).and_return(false)
      end

      it "does not install protection and passes event through" do
        result = middleware.call(event_data)
        expect(result).to eq(event_data)
      end
    end

    context "when config is nil" do
      let(:config_double) { nil }

      it "no-ops and passes event through" do
        result = middleware.call(event_data)
        expect(result).to eq(event_data)
      end
    end
  end

  describe "BaggagePiiError" do
    it "is a StandardError" do
      expect(E11y::Middleware::BaggagePiiError).to be < StandardError
    end
  end
end

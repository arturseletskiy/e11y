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
    dbl = instance_double(E11y::Configuration, security: security_config, enabled: true)
    allow(dbl).to receive(:built_pipeline).and_return(->(e) { e })
    dbl
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

    # OTel integration tests moved to spec/integration/baggage_protection_integration_spec.rb
    # to avoid hide_const("OpenTelemetry") and config_double conflicts in full suite.

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
    it "is a StandardError (E11y::BaggagePiiError)" do
      expect(E11y::BaggagePiiError).to be < StandardError
    end
  end
end

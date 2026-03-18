# frozen_string_literal: true

# BaggageProtection OTel integration tests — isolated from unit specs to avoid
# hide_const("OpenTelemetry") and config_double conflicts when running full suite.
require "rails_helper"
require "e11y/middleware/baggage_protection"

RSpec.describe "BaggageProtection OpenTelemetry Integration", :integration do
  before do
    begin
      require "opentelemetry/sdk"
    rescue LoadError
      skip "OpenTelemetry SDK not available (bundle config set --local with integration)"
    end
    skip "OpenTelemetry::Baggage not available" unless defined?(OpenTelemetry::Baggage)
    E11y.configure do |config|
      config.security_baggage_protection_enabled = true
      config.security_baggage_protection_allowed_keys = %w[trace_id span_id request_id]
      config.security_baggage_protection_block_mode = :silent
    end
  end

  let(:app) { ->(event_data) { event_data } }
  let(:middleware) { E11y::Middleware::BaggageProtection.new(app) }
  let(:event_data) { { event_name: "test.event", severity: :info, payload: {} } }

  it "blocks PII keys from OpenTelemetry Baggage" do
    expect(E11y.config.security_baggage_protection_enabled).to be(true)
    expect(E11y.config.security_baggage_protection_allowed_keys).not_to include("user_email")

    middleware.call(event_data)

    # Skip if OpenTelemetry::Baggage was polluted by hide_const in another spec (run in isolation to verify)
    skip "OpenTelemetry::Baggage polluted; run: bundle exec rspec spec/integration/baggage_protection_integration_spec.rb" \
      unless OpenTelemetry::Baggage.ancestors.size > 1

    ctx = OpenTelemetry::Context.empty
    result_ctx = OpenTelemetry::Baggage.set_value("user_email", "pii@example.com", context: ctx)

    values = OpenTelemetry::Baggage.values(context: result_ctx)
    expect(values).not_to have_key("user_email")
  end

  it "allows keys in allowlist" do
    middleware.call(event_data)

    ctx = OpenTelemetry::Context.empty
    result_ctx = OpenTelemetry::Baggage.set_value("trace_id", "abc123", context: ctx)

    expect(OpenTelemetry::Baggage.values(context: result_ctx)["trace_id"]).to eq("abc123")
  end

  it "only prepends once (idempotent)" do
    middleware.call(event_data)
    middleware.call(event_data)

    ctx = OpenTelemetry::Context.empty
    expect { OpenTelemetry::Baggage.set_value("user_email", "pii@example.com", context: ctx) }.not_to raise_error
  end
end

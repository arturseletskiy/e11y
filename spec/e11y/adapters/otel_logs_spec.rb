# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpec/SpecFilePathFormat
# File path matches common abbreviation "OTel" rather than "OTelLogs" class name.
# Integration test: requires OpenTelemetry SDK
# Run with: INTEGRATION=true bundle exec rspec --tag integration
begin
  require "opentelemetry/sdk"
  require "opentelemetry-logs-sdk"
  require "e11y/adapters/otel_logs"
rescue LoadError
  RSpec.describe "E11y::Adapters::OTelLogs", :integration do
    it "requires OpenTelemetry SDK to be available" do
      skip "OpenTelemetry SDK not available (run: bundle install --with integration)"
    end
  end

  return
end

RSpec.describe E11y::Adapters::OTelLogs, :integration do
  let(:adapter) { described_class.new(service_name: "test-service") }
  let(:event_data) do
    {
      event_name: "order.paid",
      severity: :info,
      timestamp: Time.now.utc,
      trace_id: "trace123",
      span_id: "span123",
      payload: {
        order_id: "order123",
        amount: 99.99,
        user_id: "user123"
      }
    }
  end

  describe "#initialize" do
    it "defaults to :all baggage allowlist (all payload keys pass through)" do
      allowlist = adapter.instance_variable_get(:@baggage_allowlist)
      expect(allowlist).to eq(:all)
    end

    it "accepts custom baggage allowlist for backward compat" do
      custom_adapter = described_class.new(baggage_allowlist: [:custom_key])
      allowlist = custom_adapter.instance_variable_get(:@baggage_allowlist)
      expect(allowlist).to eq([:custom_key])
    end

    it "sets max_attributes for cardinality protection" do
      max_attrs = adapter.instance_variable_get(:@max_attributes)
      expect(max_attrs).to eq(50) # default
    end
  end

  describe "#write" do
    let(:logger) { instance_double(OpenTelemetry::SDK::Logs::Logger) }

    before do
      allow(adapter.instance_variable_get(:@logger)).to receive(:emit_log_record)
    end

    it "emits log record to OTel logger" do
      expect(adapter.write(event_data)).to be true
    end

    it "returns false on error" do
      allow(adapter).to receive(:build_log_record_params).and_raise(StandardError, "OTel error")
      expect(adapter.write(event_data)).to be false
    end
  end

  describe "#healthy?" do
    it "returns true when logger provider and logger are set" do
      expect(adapter.healthy?).to be(true)
    end

    it "returns false when logger not set" do
      adapter.instance_variable_set(:@logger, nil)
      expect(adapter.healthy?).to be(false)
    end
  end

  describe "#capabilities" do
    it "returns capabilities hash" do
      capabilities = adapter.capabilities
      expect(capabilities[:batching]).to be false
      expect(capabilities[:async]).to be true
    end
  end

  describe "ADR-007 compliance (OpenTelemetry Integration)" do
    describe "Severity mapping (E11y → OTel)" do
      it "maps E11y severities to OTel severities" do
        {
          debug: 5,  # DEBUG
          info: 9,   # INFO
          success: 9, # INFO
          warn: 13,  # WARN
          error: 17, # ERROR
          fatal: 21  # FATAL
        }.each do |e11y_severity, otel_severity_number|
          result = adapter.send(:map_severity, e11y_severity)
          expect(result).to eq(otel_severity_number), "Expected #{otel_severity_number} for #{e11y_severity}"
        end
      end

      it "defaults to INFO for unknown severity" do
        result = adapter.send(:map_severity, :unknown)
        expect(result).to eq(9) # INFO
      end
    end

    describe "Attributes mapping" do
      it "includes event metadata in attributes" do
        attributes = adapter.send(:build_attributes, event_data)
        expect(attributes["event.name"]).to eq("order.paid")
        expect(attributes["service.name"]).to eq("test-service")
      end

      it "includes event version if present" do
        event_with_version = event_data.merge(v: 2)
        attributes = adapter.send(:build_attributes, event_with_version)
        expect(attributes["event.version"]).to eq(2)
      end

      it "prefixes payload attributes with 'event.' and includes all business keys by default" do
        attributes = adapter.send(:build_attributes, event_data)
        expect(attributes).to have_key("event.order_id")
        expect(attributes).to have_key("event.amount")
        expect(attributes).to have_key("event.user_id")
      end
    end
  end

  describe "C08 Resolution: Baggage PII Protection" do
    let(:pii_event) do
      {
        event_name: "user.signup",
        severity: :info,
        payload: {
          user_id: "user123",
          email: "user@example.com",
          phone: "+1234567890",
          trace_id: "trace123"
        }
      }
    end

    it "passes all keys through when baggage_allowlist is :all (default)" do
      # PII stripping is handled upstream by Middleware::PIIFilter — not here.
      # With :all, the adapter forwards whatever it receives.
      attributes = adapter.send(:build_attributes, pii_event)
      expect(attributes).to have_key("event.user_id")
      expect(attributes).to have_key("event.email")
    end

    it "restricts to explicit allowlist when one is provided (backward compat)" do
      adapter_with_allowlist = described_class.new(
        baggage_allowlist: %i[user_id trace_id]
      )

      attributes = adapter_with_allowlist.send(:build_attributes, pii_event)

      expect(attributes).to have_key("event.user_id")
      expect(attributes).to have_key("event.trace_id")
      expect(attributes).not_to have_key("event.email")
      expect(attributes).not_to have_key("event.phone")
    end

    it "baggage_allowed? returns true for all keys in :all mode" do
      expect(adapter.send(:baggage_allowed?, :email)).to be(true)
      expect(adapter.send(:baggage_allowed?, :ssn)).to be(true)
      expect(adapter.send(:baggage_allowed?, :order_id)).to be(true)
    end

    it "baggage_allowed? returns false for non-allowlisted keys in restricted mode" do
      restricted = described_class.new(baggage_allowlist: %i[user_id])
      expect(restricted.send(:baggage_allowed?, :email)).to be(false)
      expect(restricted.send(:baggage_allowed?, :user_id)).to be(true)
    end
  end

  describe "C04 Resolution: Cardinality Protection" do
    let(:high_cardinality_event) do
      {
        event_name: "high.cardinality",
        severity: :info,
        payload: (1..100).to_h { |i| ["key_#{i}", "value_#{i}"] }
      }
    end

    it "limits attributes to max_attributes" do
      adapter_with_limit = described_class.new(max_attributes: 10)
      attributes = adapter_with_limit.send(:build_attributes, high_cardinality_event)

      # Should not exceed max_attributes (including metadata)
      expect(attributes.size).to be <= 10
    end

    it "respects configured max_attributes" do
      adapter_with_limit = described_class.new(max_attributes: 5)
      max = adapter_with_limit.instance_variable_get(:@max_attributes)
      expect(max).to eq(5)
    end

    it "protects against attribute explosion" do
      # C04: Prevent high-cardinality attributes from overwhelming OTel
      adapter_with_limit = described_class.new(max_attributes: 20)
      attributes = adapter_with_limit.send(:build_attributes, high_cardinality_event)

      # Cardinality protected (limited to max_attributes)
      expect(attributes.size).to be <= 20
    end
  end

  describe "UC-008 compliance (OpenTelemetry Integration)" do
    it "sends events to OpenTelemetry Logs API" do
      # UC-008: E11y events sent to OTel Collector
      allow(adapter.instance_variable_get(:@logger)).to receive(:emit_log_record)

      result = adapter.write(event_data)
      expect(result).to be true
    end

    it "includes trace context in log records" do
      log_record = adapter.send(:build_log_record, event_data)
      expect(log_record.trace_id).to eq("trace123")
      expect(log_record.span_id).to eq("span123")
    end

    it "documents that OTel SDK is optional dependency" do
      # UC-008: OpenTelemetry integration is opt-in
      # User must add 'opentelemetry-sdk' to Gemfile
      expect(described_class::DEFAULT_BAGGAGE_ALLOWLIST).to be_a(Array)
    end

    it "sends all payload attributes by default (no PII filter at adapter layer)" do
      log_record = adapter.send(:build_log_record, event_data)
      attrs = log_record.attributes
      expect(attrs).to have_key("event.order_id")
      expect(attrs).to have_key("event.amount")
      expect(attrs).to have_key("event.user_id")
    end
  end

  describe "Real-world scenarios" do
    it "handles typical order.paid event" do
      order_event = {
        event_name: "order.paid",
        severity: :info,
        timestamp: Time.now.utc,
        trace_id: "trace123",
        span_id: "span123",
        payload: {
          order_id: "order123",
          amount: 99.99,
          currency: "USD",
          user_id: "user123"
        }
      }

      log_record = adapter.send(:build_log_record, order_event)
      expect(log_record.body).to eq("order.paid")
      expect(log_record.severity_text).to eq("INFO")
    end

    it "handles error events with stack traces" do
      error_event = {
        event_name: "error.occurred",
        severity: :error,
        payload: {
          error_class: "StandardError",
          error_message: "Something went wrong",
          trace_id: "trace123"
        }
      }

      log_record = adapter.send(:build_log_record, error_event)
      expect(log_record.severity_number).to eq(17) # ERROR
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat

# frozen_string_literal: true

require "spec_helper"
require "time"

# Sentry adapter integration tests require SDK mocking, scope management,
# and extensive configuration with multiple fixtures.
# Skip Sentry tests if Sentry SDK not available
begin
  require "e11y/adapters/sentry"
rescue LoadError
  RSpec.describe "E11y::Adapters::Sentry (skipped)" do
    it "requires Sentry SDK to be available" do
      skip "Sentry SDK not available in test environment"
    end
  end

  return
end

RSpec.describe E11y::Adapters::Sentry do
  let(:sentry_dsn) { "https://public@sentry.test/1" }
  let(:config) do
    {
      dsn: sentry_dsn,
      environment: "test",
      severity_threshold: :warn,
      breadcrumbs: true
    }
  end

  let(:adapter) { described_class.new(config) }

  let(:error_event) do
    {
      event_name: "payment.failed",
      severity: :error,
      message: "Payment processing failed",
      timestamp: Time.parse("2024-01-01 12:00:00 UTC"),
      payload: { amount: 100, currency: "USD" },
      user: { id: 123, email: "user@example.com" },
      trace_id: "trace-123",
      span_id: "span-456"
    }
  end

  let(:warn_event) do
    {
      event_name: "rate.limit.warning",
      severity: :warn,
      message: "Approaching rate limit",
      timestamp: Time.parse("2024-01-01 12:01:00 UTC")
    }
  end

  let(:info_event) do
    {
      event_name: "user.login",
      severity: :info,
      message: "User logged in",
      timestamp: Time.parse("2024-01-01 12:02:00 UTC")
    }
  end

  before do
    # Stub Sentry initialization to prevent real HTTP calls
    sentry_config = double("Sentry::Configuration")
    allow(sentry_config).to receive(:dsn=)
    allow(sentry_config).to receive(:environment=)
    allow(sentry_config).to receive(:breadcrumbs_logger=)

    allow(Sentry).to receive(:init).and_yield(sentry_config)
    allow(Sentry).to receive(:initialized?).and_return(true)

    # Stub Sentry methods to prevent real calls
    allow(Sentry).to receive(:with_scope).and_yield(double(
                                                      set_tags: nil,
                                                      set_extras: nil,
                                                      set_user: nil,
                                                      set_context: nil
                                                    ))
    allow(Sentry).to receive(:capture_message)
    allow(Sentry).to receive(:capture_exception)
    allow(Sentry).to receive(:add_breadcrumb)
  end

  describe "ADR-004 compliance" do
    describe "Section 3.1: Base Adapter Contract" do
      it "inherits from E11y::Adapters::Base" do
        expect(adapter).to be_a(E11y::Adapters::Base)
      end

      it "implements #write" do
        expect(adapter).to respond_to(:write)
        expect(adapter.write(error_event)).to be(true).or(be(false))
      end

      it "implements #write_batch" do
        expect(adapter).to respond_to(:write_batch)
        # Sentry adapter doesn't implement batching, uses default
      end

      it "implements #healthy?" do
        expect(adapter).to respond_to(:healthy?)
        expect(adapter.healthy?).to be(true).or(be(false))
      end

      it "implements #close" do
        expect(adapter).to respond_to(:close)
        expect { adapter.close }.not_to raise_error
      end

      it "implements #capabilities" do
        expect(adapter).to respond_to(:capabilities)
        caps = adapter.capabilities
        expect(caps).to be_a(Hash)
        expect(caps).to include(:batching, :compression, :async, :streaming)
      end
    end

    describe "Section 4.4: Sentry Adapter Specification" do
      it "sends errors to Sentry" do
        expect(Sentry).to receive(:capture_message).with(
          "Payment processing failed",
          level: :error
        )

        adapter.write(error_event)
      end

      it "sends breadcrumbs for non-error events" do
        expect(Sentry).to receive(:add_breadcrumb) do |breadcrumb|
          expect(breadcrumb.category).to eq("rate.limit.warning")
          expect(breadcrumb.level).to eq(:warning)
        end

        adapter.write(warn_event)
      end

      it "respects severity threshold" do
        expect(Sentry).not_to receive(:add_breadcrumb)
        expect(Sentry).not_to receive(:capture_message)

        # Info is below :warn threshold
        adapter.write(info_event)
      end

      it "sets tags on errors" do
        scope = double("Sentry::Scope")
        expect(scope).to receive(:set_tags).with(hash_including(
                                                   event_name: "payment.failed",
                                                   severity: "error"
                                                 ))
        expect(scope).to receive(:set_extras).with(hash_including(amount: 100))
        expect(scope).to receive(:set_user).with(hash_including(id: 123))
        expect(scope).to receive(:set_context).with("trace", hash_including(trace_id: "trace-123"))

        allow(Sentry).to receive(:with_scope).and_yield(scope)
        expect(Sentry).to receive(:capture_message)

        adapter.write(error_event)
      end

      it "captures exceptions when provided" do
        exception = StandardError.new("Test error")
        event_with_exception = error_event.merge(exception: exception)

        expect(Sentry).to receive(:capture_exception).with(exception)

        adapter.write(event_with_exception)
      end
    end
  end

  describe "Configuration" do
    it "requires :dsn parameter" do
      expect { described_class.new({}) }.to raise_error(ArgumentError, /requires :dsn/)
    end

    it "validates severity_threshold" do
      expect do
        described_class.new(dsn: sentry_dsn, severity_threshold: :invalid)
      end.to raise_error(ArgumentError, /Invalid severity_threshold/)
    end

    it "uses default values" do
      minimal_adapter = described_class.new(dsn: sentry_dsn)

      expect(minimal_adapter.environment).to eq("production")
      expect(minimal_adapter.severity_threshold).to eq(:warn)
      expect(minimal_adapter.send_breadcrumbs).to be true
    end

    it "accepts custom environment" do
      custom_adapter = described_class.new(
        dsn: sentry_dsn,
        environment: "staging"
      )

      expect(custom_adapter.environment).to eq("staging")
    end

    it "accepts custom severity_threshold" do
      custom_adapter = described_class.new(
        dsn: sentry_dsn,
        severity_threshold: :error
      )

      expect(custom_adapter.severity_threshold).to eq(:error)
    end

    it "accepts breadcrumbs configuration" do
      no_breadcrumbs_adapter = described_class.new(
        dsn: sentry_dsn,
        breadcrumbs: false
      )

      expect(no_breadcrumbs_adapter.send_breadcrumbs).to be false
    end
  end

  describe "Severity filtering" do
    let(:debug_adapter) do
      described_class.new(
        dsn: sentry_dsn,
        severity_threshold: :debug
      )
    end

    let(:error_adapter) do
      described_class.new(
        dsn: sentry_dsn,
        severity_threshold: :error
      )
    end

    it "sends all events when threshold is :debug" do
      expect(Sentry).to receive(:add_breadcrumb)

      debug_adapter.write(info_event)
    end

    it "only sends errors when threshold is :error" do
      expect(Sentry).not_to receive(:add_breadcrumb)
      expect(Sentry).not_to receive(:capture_message)

      error_adapter.write(warn_event)
    end

    it "sends errors when threshold is :error" do
      expect(Sentry).to receive(:capture_message)

      error_adapter.write(error_event)
    end
  end

  describe "Breadcrumbs" do
    it "adds breadcrumbs for warn-level events" do
      expect(Sentry).to receive(:add_breadcrumb) do |breadcrumb|
        expect(breadcrumb).to be_a(Sentry::Breadcrumb)
        expect(breadcrumb.category).to eq("rate.limit.warning")
        expect(breadcrumb.message).to eq("Approaching rate limit")
        expect(breadcrumb.level).to eq(:warning)
      end

      adapter.write(warn_event)
    end

    it "does not add breadcrumbs when disabled" do
      no_breadcrumbs = described_class.new(
        dsn: sentry_dsn,
        breadcrumbs: false
      )

      expect(Sentry).not_to receive(:add_breadcrumb)

      no_breadcrumbs.write(warn_event)
    end

    it "does not add breadcrumbs for error events" do
      expect(Sentry).not_to receive(:add_breadcrumb)
      expect(Sentry).to receive(:capture_message)

      adapter.write(error_event)
    end
  end

  describe "Error reporting" do
    it "captures error messages" do
      expect(Sentry).to receive(:capture_message).with(
        "Payment processing failed",
        level: :error
      )

      adapter.write(error_event)
    end

    it "captures fatal messages" do
      fatal_event = error_event.merge(severity: :fatal)

      expect(Sentry).to receive(:capture_message).with(
        "Payment processing failed",
        level: :fatal
      )

      adapter.write(fatal_event)
    end

    it "uses event_name as message fallback" do
      event_without_message = error_event.dup
      event_without_message.delete(:message)

      expect(Sentry).to receive(:capture_message).with(
        "payment.failed",
        level: :error
      )

      adapter.write(event_without_message)
    end

    it "sets payload as extras" do
      scope = double("Sentry::Scope")
      expect(scope).to receive(:set_extras).with(hash_including(amount: 100, currency: "USD"))
      allow(scope).to receive(:set_tags)
      allow(scope).to receive(:set_user)
      allow(scope).to receive(:set_context)

      allow(Sentry).to receive(:with_scope).and_yield(scope)
      expect(Sentry).to receive(:capture_message)

      adapter.write(error_event)
    end

    it "sets user context" do
      scope = double("Sentry::Scope")
      expect(scope).to receive(:set_user).with(hash_including(id: 123, email: "user@example.com"))
      allow(scope).to receive(:set_tags)
      allow(scope).to receive(:set_extras)
      allow(scope).to receive(:set_context)

      allow(Sentry).to receive(:with_scope).and_yield(scope)
      expect(Sentry).to receive(:capture_message)

      adapter.write(error_event)
    end

    it "sets trace context" do
      scope = double("Sentry::Scope")
      expect(scope).to receive(:set_context).with("trace", hash_including(
                                                             trace_id: "trace-123",
                                                             span_id: "span-456"
                                                           ))
      allow(scope).to receive(:set_tags)
      allow(scope).to receive(:set_extras)
      allow(scope).to receive(:set_user)

      allow(Sentry).to receive(:with_scope).and_yield(scope)
      expect(Sentry).to receive(:capture_message)

      adapter.write(error_event)
    end
  end

  describe "#healthy?" do
    it "returns true when Sentry is initialized" do
      expect(adapter.healthy?).to be true
    end
  end

  describe "#capabilities" do
    it "reports correct capabilities" do
      caps = adapter.capabilities

      expect(caps[:batching]).to be false # Sentry SDK handles batching
      expect(caps[:compression]).to be false # Sentry SDK handles compression
      expect(caps[:async]).to be true # Sentry SDK is async
      expect(caps[:streaming]).to be false
    end
  end

  describe "Error handling" do
    it "returns false on Sentry error" do
      allow(Sentry).to receive(:capture_message).and_raise(StandardError.new("Sentry error"))

      result = adapter.write(error_event)

      expect(result).to be false
    end

    it "does not raise on Sentry error" do
      allow(Sentry).to receive(:capture_message).and_raise(StandardError.new("Sentry error"))

      expect { adapter.write(error_event) }.not_to raise_error
    end
  end

  describe "Severity mapping" do
    it "maps debug to :debug" do
      event = info_event.merge(severity: :debug)
      allow(Sentry).to receive(:add_breadcrumb) do |breadcrumb|
        expect(breadcrumb.level).to eq(:debug)
      end

      described_class.new(dsn: sentry_dsn, severity_threshold: :debug).write(event)
    end

    it "maps info to :info" do
      event = info_event.merge(severity: :info)
      allow(Sentry).to receive(:add_breadcrumb) do |breadcrumb|
        expect(breadcrumb.level).to eq(:info)
      end

      described_class.new(dsn: sentry_dsn, severity_threshold: :info).write(event)
    end

    it "maps success to :info" do
      event = info_event.merge(severity: :success)
      allow(Sentry).to receive(:add_breadcrumb) do |breadcrumb|
        expect(breadcrumb.level).to eq(:info)
      end

      described_class.new(dsn: sentry_dsn, severity_threshold: :info).write(event)
    end

    it "maps warn to :warning" do
      allow(Sentry).to receive(:add_breadcrumb) do |breadcrumb|
        expect(breadcrumb.level).to eq(:warning)
      end

      adapter.write(warn_event)
    end

    it "maps error to :error" do
      expect(Sentry).to receive(:capture_message).with(anything, level: :error)

      adapter.write(error_event)
    end

    it "maps fatal to :fatal" do
      fatal_event = error_event.merge(severity: :fatal)

      expect(Sentry).to receive(:capture_message).with(anything, level: :fatal)

      adapter.write(fatal_event)
    end
  end
end

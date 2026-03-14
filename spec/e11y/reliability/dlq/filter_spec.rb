# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/e11y/reliability/dlq/filter"

RSpec.describe E11y::Reliability::DLQ::Filter do
  let(:filter) { described_class.new }

  describe "#initialize" do
    it "sets default save severities" do
      expect(filter.stats[:save_severities]).to eq(%i[error fatal])
    end

    it "sets default behavior to :save" do
      expect(filter.stats[:default_behavior]).to eq(:save)
    end

    it "accepts custom save_severities" do
      custom_filter = described_class.new(save_severities: [:error])

      expect(custom_filter.stats[:save_severities]).to eq([:error])
    end
  end

  describe "#should_save?" do
    let(:event_data) do
      {
        event_name: "test.event",
        severity: :info,
        payload: {}
      }
    end

    context "with Event DSL use_dlq false (highest priority)" do
      before do
        discard_class = Class.new(E11y::Event::Base) do
          def self.event_name
            "debug.verbose"
          end
          use_dlq false
        end
        allow(E11y::Registry).to receive(:find).with("debug.verbose").and_return(discard_class)
        allow(E11y::Registry).to receive(:find).with("payment.failed").and_return(nil)
      end

      it "discards when event class has use_dlq false" do
        event = event_data.merge(event_name: "debug.verbose", severity: :error)

        expect(filter.should_save?(event)).to be false
      end

      it "allows unregistered events to proceed to severity rule" do
        event = event_data.merge(event_name: "payment.failed", severity: :error)

        expect(filter.should_save?(event)).to be true
      end
    end

    context "with Event DSL use_dlq true (priority 2)" do
      before do
        save_class = Class.new(E11y::Event::Base) do
          def self.event_name
            "payment.processed"
          end
          use_dlq true
        end
        allow(E11y::Registry).to receive(:find).with("payment.processed").and_return(save_class)
        allow(E11y::Registry).to receive(:find).with("user.login").and_return(nil)
      end

      it "saves when event class has use_dlq true" do
        filter_discard = described_class.new(save_severities: [], default_behavior: :discard)
        event = event_data.merge(event_name: "payment.processed", severity: :info)

        expect(filter_discard.should_save?(event)).to be true
      end

      it "falls back to default for unregistered events" do
        filter_discard = described_class.new(save_severities: [], default_behavior: :discard)
        event = event_data.merge(event_name: "user.login")

        expect(filter_discard.should_save?(event)).to be false
      end
    end

    context "with save_severities (priority 3)" do
      let(:filter) do
        described_class.new(
          save_severities: %i[error fatal],
          default_behavior: :discard
        )
      end

      before { allow(E11y::Registry).to receive(:find).and_return(nil) }

      it "saves error events" do
        event = event_data.merge(severity: :error)

        expect(filter.should_save?(event)).to be true
      end

      it "saves fatal events" do
        event = event_data.merge(severity: :fatal)

        expect(filter.should_save?(event)).to be true
      end

      it "discards info events" do
        event = event_data.merge(severity: :info)

        expect(filter.should_save?(event)).to be false
      end
    end

    it "accepts optional error argument (prevents BUG-001 crash)" do
      allow(E11y::Registry).to receive(:find).and_return(nil)
      error = StandardError.new("Adapter failed")

      expect { filter.should_save?(event_data, error) }.not_to raise_error
      expect(filter.should_save?(event_data, error)).to be true
    end

    context "with default_behavior (lowest priority)" do
      before { allow(E11y::Registry).to receive(:find).and_return(nil) }

      it "saves by default when :save" do
        filter_save = described_class.new(default_behavior: :save)
        event = event_data.merge(event_name: "random.event", severity: :info)

        expect(filter_save.should_save?(event)).to be true
      end

      it "discards by default when :discard" do
        filter_discard = described_class.new(
          save_severities: [],
          default_behavior: :discard
        )
        event = event_data.merge(event_name: "random.event", severity: :info)

        expect(filter_discard.should_save?(event)).to be false
      end
    end
  end

  describe "priority order" do
    let(:complex_filter) { described_class.new(save_severities: [:error], default_behavior: :discard) }

    before do
      discard_class = Class.new(E11y::Event::Base) do
        def self.event_name
          "debug.payment.test"
        end
        use_dlq false
      end
      save_class = Class.new(E11y::Event::Base) do
        def self.event_name
          "payment.success"
        end
        use_dlq true
      end
      allow(E11y::Registry).to receive(:find).with("debug.payment.test").and_return(discard_class)
      allow(E11y::Registry).to receive(:find).with("payment.success").and_return(save_class)
      allow(E11y::Registry).to receive(:find).with("user.action").and_return(nil)
      allow(E11y::Registry).to receive(:find).with("random.event").and_return(nil)
    end

    it "prioritizes use_dlq false over severity" do
      event = { event_name: "debug.payment.test", severity: :error }

      expect(complex_filter.should_save?(event)).to be false
    end

    it "prioritizes use_dlq true over severity" do
      event = { event_name: "payment.success", severity: :info }

      expect(complex_filter.should_save?(event)).to be true
    end

    it "prioritizes severity over default" do
      event = { event_name: "user.action", severity: :error }

      expect(complex_filter.should_save?(event)).to be true
    end

    it "uses default when no rules match" do
      event = { event_name: "random.event", severity: :info }

      expect(complex_filter.should_save?(event)).to be false
    end
  end

  describe "#stats" do
    let(:filter) do
      described_class.new(
        save_severities: %i[error fatal],
        default_behavior: :save
      )
    end

    it "returns filter configuration" do
      expect(filter.stats).to include(
        save_severities: %i[error fatal],
        default_behavior: :save
      )
    end
  end

  describe "metrics" do
    let(:event_data) do
      {
        event_name: "test.event",
        severity: :info,
        payload: {}
      }
    end

    before do
      allow(E11y::Metrics).to receive(:increment)
    end

    it "increments e11y_dlq_filter_decisions_total with action discarded and reason use_dlq" do
      discard_class = Class.new(E11y::Event::Base) do
        def self.event_name
          "test.event"
        end
        use_dlq false
      end
      allow(E11y::Registry).to receive(:find).with("test.event").and_return(discard_class)

      filter.should_save?(event_data)

      expect(E11y::Metrics).to have_received(:increment).with(
        :e11y_dlq_filter_decisions_total,
        { action: "discarded", reason: "use_dlq" }
      )
    end

    it "increments e11y_dlq_filter_decisions_total with action saved and reason use_dlq" do
      save_class = Class.new(E11y::Event::Base) do
        def self.event_name
          "payment.processed"
        end
        use_dlq true
      end
      allow(E11y::Registry).to receive(:find).with("payment.processed").and_return(save_class)

      filter_discard = described_class.new(save_severities: [], default_behavior: :discard)
      filter_discard.should_save?(event_data.merge(event_name: "payment.processed"))

      expect(E11y::Metrics).to have_received(:increment).with(
        :e11y_dlq_filter_decisions_total,
        { action: "saved", reason: "use_dlq" }
      )
    end

    it "increments e11y_dlq_filter_decisions_total with action saved and reason severity" do
      allow(E11y::Registry).to receive(:find).and_return(nil)

      filter.should_save?(event_data.merge(severity: :error))

      expect(E11y::Metrics).to have_received(:increment).with(
        :e11y_dlq_filter_decisions_total,
        { action: "saved", reason: "severity" }
      )
    end

    it "increments e11y_dlq_filter_decisions_total with action saved and reason default" do
      allow(E11y::Registry).to receive(:find).and_return(nil)

      filter.should_save?(event_data.merge(event_name: "random.event"))

      expect(E11y::Metrics).to have_received(:increment).with(
        :e11y_dlq_filter_decisions_total,
        { action: "saved", reason: "default" }
      )
    end

    it "increments e11y_dlq_filter_decisions_total with action discarded and reason default" do
      allow(E11y::Registry).to receive(:find).and_return(nil)

      filter_discard = described_class.new(save_severities: [], default_behavior: :discard)
      filter_discard.should_save?(event_data.merge(event_name: "random.event"))

      expect(E11y::Metrics).to have_received(:increment).with(
        :e11y_dlq_filter_decisions_total,
        { action: "discarded", reason: "default" }
      )
    end

    it "does not call E11y::Metrics.increment when Metrics does not respond to increment" do
      discard_class = Class.new(E11y::Event::Base) do
        def self.event_name
          "test.event"
        end
        use_dlq false
      end
      allow(E11y::Registry).to receive(:find).with("test.event").and_return(discard_class)
      allow(E11y::Metrics).to receive(:respond_to?).with(:increment).and_return(false)

      expect(filter.should_save?(event_data)).to be false
      expect(E11y::Metrics).not_to have_received(:increment)
    end
  end

  describe "real-world scenarios" do
    context "with audit events (preset has use_dlq true)" do
      let(:audit_event_class) do
        Class.new(E11y::Events::BaseAuditEvent) do
          def self.event_name
            "audit.user.deleted"
          end
        end
      end

      before do
        allow(E11y::Registry).to receive(:find).with("audit.user.deleted").and_return(audit_event_class)
        allow(E11y::Registry).to receive(:find).with("user.login").and_return(nil)
        allow(E11y::Registry).to receive(:find).with("unknown.error").and_return(nil)
      end

      it "saves audit events via preset" do
        event = { event_name: "audit.user.deleted", severity: :info }

        expect(filter.should_save?(event)).to be true
      end

      it "saves errors by severity for unregistered events" do
        event = { event_name: "unknown.error", severity: :error }

        expect(filter.should_save?(event)).to be true
      end
    end

    context "with development configuration" do
      let(:dev_filter) do
        described_class.new(
          save_severities: %i[error fatal],
          default_behavior: :discard
        )
      end

      before { allow(E11y::Registry).to receive(:find).and_return(nil) }

      it "only saves errors in development" do
        expect(dev_filter.should_save?(event_name: "user.login", severity: :info)).to be false
        expect(dev_filter.should_save?(event_name: "api.timeout", severity: :error)).to be true
      end
    end
  end
end

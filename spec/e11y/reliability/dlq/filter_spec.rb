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

    it "accepts custom always_save_patterns" do
      custom_filter = described_class.new(always_save_patterns: [/^payment\./])

      expect(custom_filter.stats[:always_save_patterns]).to include("/^payment\\./")
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

    context "with always_discard_patterns (highest priority)" do
      let(:filter) do
        described_class.new(
          always_discard_patterns: [/^debug\./, /^test\./],
          always_save_patterns: [/^test\./], # Lower priority
          save_severities: [:error] # Lower priority
        )
      end

      it "discards matching events even if other rules say save" do
        event = event_data.merge(event_name: "debug.verbose", severity: :error)

        expect(filter.should_save?(event)).to be false
      end

      it "discards test events" do
        event = event_data.merge(event_name: "test.event")

        expect(filter.should_save?(event)).to be false
      end

      it "allows non-matching events to proceed to next rule" do
        event = event_data.merge(event_name: "payment.failed", severity: :error)

        expect(filter.should_save?(event)).to be true
      end
    end

    context "with always_save_patterns (priority 2)" do
      let(:filter) do
        described_class.new(
          always_save_patterns: [/^payment\./, /^audit\./],
          save_severities: [], # Don't save by severity
          default_behavior: :discard # Don't save by default
        )
      end

      it "saves payment events" do
        event = event_data.merge(event_name: "payment.processed")

        expect(filter.should_save?(event)).to be true
      end

      it "saves audit events" do
        event = event_data.merge(event_name: "audit.log.created")

        expect(filter.should_save?(event)).to be true
      end

      it "discards non-matching events (fallback to default)" do
        event = event_data.merge(event_name: "user.login")

        expect(filter.should_save?(event)).to be false
      end
    end

    context "with save_severities (priority 3)" do
      let(:filter) do
        described_class.new(
          save_severities: %i[error fatal],
          default_behavior: :discard
        )
      end

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

    context "with default_behavior (lowest priority)" do
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
    let(:complex_filter) do
      described_class.new(
        always_discard_patterns: [/^debug\./],
        always_save_patterns: [/^payment\./],
        save_severities: [:error],
        default_behavior: :discard
      )
    end

    it "prioritizes always_discard over always_save" do
      # This should be discarded despite matching always_save pattern
      event = { event_name: "debug.payment.test", severity: :error }

      expect(complex_filter.should_save?(event)).to be false
    end

    it "prioritizes always_save over severity" do
      # This should be saved despite not being :error severity
      event = { event_name: "payment.success", severity: :info }

      expect(complex_filter.should_save?(event)).to be true
    end

    it "prioritizes severity over default" do
      # This should be saved despite default_behavior: :discard
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
        always_save_patterns: [/^payment\./],
        always_discard_patterns: [/^debug\./],
        save_severities: %i[error fatal],
        default_behavior: :save
      )
    end

    it "returns filter configuration" do
      stats = filter.stats

      expect(stats).to include(
        always_save_patterns: ["/^payment\\./"],
        always_discard_patterns: ["/^debug\\./"],
        save_severities: %i[error fatal],
        default_behavior: :save
      )
    end
  end

  describe "real-world scenarios" do
    context "with production configuration" do
      let(:prod_filter) do
        described_class.new(
          always_save_patterns: [
            /^payment\./,
            /^audit\./,
            /^order\.failed/,
            /^security\./
          ],
          always_discard_patterns: [
            /^debug\./,
            /^test\./,
            /\.heartbeat$/
          ],
          save_severities: %i[error fatal],
          default_behavior: :save
        )
      end

      it "saves critical business events" do
        expect(prod_filter.should_save?(
                 event_name: "payment.failed", severity: :error
               )).to be true

        expect(prod_filter.should_save?(
                 event_name: "audit.user.deleted", severity: :info
               )).to be true

        expect(prod_filter.should_save?(
                 event_name: "order.failed", severity: :warn
               )).to be true
      end

      it "discards noise" do
        expect(prod_filter.should_save?(
                 event_name: "debug.sql.query", severity: :debug
               )).to be false

        expect(prod_filter.should_save?(
                 event_name: "service.heartbeat", severity: :info
               )).to be false
      end

      it "saves errors by default" do
        expect(prod_filter.should_save?(
                 event_name: "unknown.error", severity: :error
               )).to be true
      end
    end

    context "with development configuration" do
      let(:dev_filter) do
        described_class.new(
          always_save_patterns: [],
          always_discard_patterns: [],
          save_severities: %i[error fatal],
          default_behavior: :discard
        )
      end

      it "only saves errors in development" do
        expect(dev_filter.should_save?(
                 event_name: "user.login", severity: :info
               )).to be false

        expect(dev_filter.should_save?(
                 event_name: "api.timeout", severity: :error
               )).to be true
      end
    end
  end
end

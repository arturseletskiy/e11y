# frozen_string_literal: true

require "spec_helper"
require "e11y/middleware/event_slo"

# rubocop:disable RSpec/SpecFilePathFormat
# File path uses abbreviated name 'slo' for clarity.
RSpec.describe E11y::Middleware::EventSlo do
  subject(:middleware) { described_class.new(app) }

  let(:app) { ->(event_data) { event_data } } # Simple passthrough app
  # Mock Event classes
  let!(:payment_event_class) do
    Class.new do
      def self.name
        "Events::PaymentProcessed"
      end

      def self.event_name
        "payment.processed"
      end

      def self.slo_config
        @slo_config ||= E11y::SLO::EventDriven::SLOConfig.new.tap do |cfg|
          cfg.enabled true
          cfg.slo_status_from do |payload|
            case payload[:status]
            when "completed" then "success"
            when "failed" then "failure"
            end
          end
          cfg.contributes_to "payment_success_rate"
          cfg.group_by :payment_method
        end
      end

      def self.respond_to?(method)
        method == :slo_config || super
      end
    end
  end
  let!(:no_slo_event_class) do
    Class.new do
      def self.name
        "Events::HealthCheck"
      end

      def self.event_name
        "health.check"
      end

      def self.respond_to?(method)
        method != :slo_config && super
      end
    end
  end

  before do
    # Stub constant lookup for our test classes
    stub_const("Events::PaymentProcessed", payment_event_class)
    stub_const("Events::HealthCheck", no_slo_event_class)

    # Mock E11y::Metrics
    allow(E11y::Metrics).to receive(:increment)
  end

  describe "#call" do
    context "when event has SLO enabled" do
      let(:event_data) do
        {
          event_name: "payment.processed",
          event_class: payment_event_class, # Explicit for testing (Phase 1 - no pipeline)
          payload: {
            payment_id: "p123",
            status: "completed",
            payment_method: "card"
          },
          severity: :info
        }
      end

      it "emits SLO metric for success" do
        result = middleware.call(event_data)

        expect(result).to eq(event_data) # Passthrough

        expect(E11y::Metrics).to have_received(:increment).with(
          :slo_event_result_total,
          hash_including(
            event_name: "payment.processed",
            slo_status: "success",
            slo_name: "payment_success_rate",
            group_by: "card"
          ),
          hash_including(value: a_kind_of(Numeric))
        )
      end

      it "emits SLO metric for failure" do
        event_data[:payload][:status] = "failed"

        middleware.call(event_data)

        expect(E11y::Metrics).to have_received(:increment).with(
          :slo_event_result_total,
          hash_including(slo_status: "failure"),
          hash_including(value: a_kind_of(Numeric))
        )
      end

      it "does not emit metric if slo_status is nil" do
        event_data[:payload][:status] = "pending"

        middleware.call(event_data)

        expect(E11y::Metrics).not_to have_received(:increment)
      end
    end

    context "when event has no SLO config" do
      let(:event_data) do
        {
          event_name: "health.check",
          payload: { health: "ok" },
          severity: :info
        }
      end

      it "skips SLO processing" do
        result = middleware.call(event_data)

        expect(result).to eq(event_data) # Passthrough
        expect(E11y::Metrics).not_to have_received(:increment)
      end
    end

    context "when event class cannot be resolved" do
      let(:event_data) do
        {
          event_name: "unknown.event",
          payload: {},
          severity: :info
        }
      end

      it "skips SLO processing gracefully" do
        expect { middleware.call(event_data) }.not_to raise_error
        expect(E11y::Metrics).not_to have_received(:increment)
      end
    end

    context "when SLO processing fails" do
      let(:event_data) do
        {
          event_name: "payment.processed",
          payload: { payment_id: "p999", status: "completed" },
          severity: :info
        }
      end

      before do
        allow(payment_event_class.slo_config).to receive(:slo_status_proc).and_raise(StandardError, "Boom")
      end

      it "returns event_data unchanged without failing" do
        result = nil

        expect { result = middleware.call(event_data) }.not_to raise_error

        expect(result).to eq(event_data) # Passthrough
        expect(E11y::Metrics).not_to have_received(:increment)
      end
    end

    context "when metric emission fails" do
      let(:event_data) do
        {
          event_name: "payment.processed",
          payload: { payment_id: "p111", status: "completed", payment_method: "card" },
          severity: :info
        }
      end

      before do
        allow(E11y::Metrics).to receive(:increment).and_raise(StandardError, "Metrics down")
      end

      it "does not fail event tracking" do
        expect { middleware.call(event_data) }.not_to raise_error
      end
    end
  end

  describe "Middleware Configuration" do
    it "uses :post_processing zone" do
      expect(described_class.middleware_zone).to eq(:post_processing)
    end
  end

  describe "ADR-014 & ADR-015 Compliance" do
    it "never modifies event_data (passthrough)" do
      event_data = {
        event_name: "payment.processed",
        payload: { payment_id: "p123", status: "completed", payment_method: "card" },
        severity: :info
      }

      original_data = event_data.dup

      middleware.call(event_data)

      expect(event_data).to eq(original_data)
    end

    it "processes in :post_processing zone (after routing)" do
      # ADR-015 §3: SLO should run after routing, before adapters
      expect(described_class.middleware_zone).to eq(:post_processing)
    end

    it "never fails event tracking due to SLO errors" do
      event_data = { event_name: "payment.processed", payload: {}, severity: :info }

      # Simulate various failures
      allow(E11y::Metrics).to receive(:increment).and_raise("Boom")

      # Should not raise
      expect { middleware.call(event_data) }.not_to raise_error
    end
  end
end
# rubocop:enable RSpec/SpecFilePathFormat

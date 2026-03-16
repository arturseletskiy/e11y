# frozen_string_literal: true

require "spec_helper"
require "e11y/slo/event_driven"

RSpec.describe E11y::SLO::EventDriven do
  # Test Event classes
  let!(:slo_enabled_event_class) do
    Class.new(E11y::Event::Base) do
      schema do
        required(:order_id).filled(:string)
        required(:status).filled(:string)
        optional(:slo_status).filled(:string)
      end

      slo do
        enabled true
        slo_status_from do |payload|
          next payload[:slo_status] if payload[:slo_status]

          case payload[:status]
          when "completed" then "success"
          when "failed" then "failure"
          end
        end
        contributes_to "order_processing"
        group_by :status
      end

      def self.name
        "Events::OrderProcessed"
      end

      def self.event_name
        "order.processed"
      end
    end
  end

  let!(:slo_disabled_event_class) do
    Class.new(E11y::Event::Base) do
      schema do
        required(:event_id).filled(:string)
      end

      slo do
        enabled false
      end

      def self.name
        "Events::DebugEvent"
      end

      def self.event_name
        "debug.event"
      end
    end
  end

  let!(:no_slo_event_class) do
    Class.new(E11y::Event::Base) do
      schema do
        required(:health).filled(:string)
      end

      def self.name
        "Events::HealthCheck"
      end

      def self.event_name
        "health.check"
      end
    end
  end

  describe "DSL (ClassMethods)" do
    context "when SLO enabled" do
      it "configures SLO settings" do
        expect(slo_enabled_event_class.slo_config).to be_a(E11y::SLO::EventDriven::SLOConfig)
        expect(slo_enabled_event_class.slo_config.enabled?).to be true
        expect(slo_enabled_event_class.slo_config.slo_status_proc).to be_a(Proc)
        expect(slo_enabled_event_class.slo_config.contributes_to).to eq("order_processing")
        expect(slo_enabled_event_class.slo_config.group_by).to eq(:status)
      end

      it "computes slo_status from payload" do
        proc = slo_enabled_event_class.slo_config.slo_status_proc
        expect(proc.call({ status: "completed" })).to eq("success")
        expect(proc.call({ status: "failed" })).to eq("failure")
        expect(proc.call({ status: "pending" })).to be_nil
      end

      it "allows explicit slo_status override" do
        proc = slo_enabled_event_class.slo_config.slo_status_proc
        expect(proc.call({ status: "completed", slo_status: "failure" })).to eq("failure")
      end
    end

    context "when SLO disabled" do
      it "configures SLO as disabled" do
        expect(slo_disabled_event_class.slo_config.enabled?).to be false
      end
    end

    context "when no SLO config" do
      it "returns nil slo_config" do
        expect(no_slo_event_class.slo_config).to be_nil
      end
    end
  end

  describe "slo_enabled? and slo_disabled?" do
    it "slo_enabled_event_class.slo_enabled? returns true" do
      expect(slo_enabled_event_class.slo_enabled?).to be true
    end

    it "slo_disabled_event_class.slo_disabled? returns true" do
      expect(slo_disabled_event_class.slo_disabled?).to be true
    end

    it "no_slo_event_class.slo_enabled? returns false, slo_disabled? returns false" do
      expect(no_slo_event_class.slo_enabled?).to be false
      expect(no_slo_event_class.slo_disabled?).to be false
    end
  end

  describe "ADR-014 Compliance" do
    it "follows explicit opt-in pattern" do
      # SLO must be explicitly enabled
      expect(slo_enabled_event_class.slo_config.enabled?).to be true
      expect(slo_disabled_event_class.slo_config.enabled?).to be false
      expect(no_slo_event_class.slo_config).to be_nil # No SLO config = not participating
    end

    it "supports auto-calculation with override" do
      proc = slo_enabled_event_class.slo_config.slo_status_proc

      # Auto-calculation (from status field)
      expect(proc.call({ status: "completed" })).to eq("success")

      # Explicit override (from slo_status field)
      expect(proc.call({ status: "completed", slo_status: "failure" })).to eq("failure")
    end
  end
end

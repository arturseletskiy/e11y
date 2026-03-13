# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::SelfMonitoring::ReliabilityMonitor do
  before do
    E11y::Metrics.reset_backend!
  end

  describe ".track_adapter_success" do
    it "increments adapter success counter" do
      expect(E11y::Metrics).to receive(:increment).with(
        :e11y_adapter_writes_total,
        { adapter: "E11y::Adapters::Loki", status: "success" }
      )

      described_class.track_adapter_success(adapter_name: "E11y::Adapters::Loki")
    end
  end

  describe ".track_adapter_failure" do
    it "increments adapter failure counter with error class" do
      expect(E11y::Metrics).to receive(:increment).with(
        :e11y_adapter_writes_total,
        { adapter: "E11y::Adapters::Loki", status: "failure", error_class: "Timeout::Error" }
      )

      described_class.track_adapter_failure(adapter_name: "E11y::Adapters::Loki", error_class: "Timeout::Error")
    end
  end

  describe ".track_circuit_state" do
    it "sets circuit breaker state gauge (closed)" do
      expect(E11y::Metrics).to receive(:gauge).with(
        :e11y_circuit_breaker_state,
        0, # closed
        { adapter: "E11y::Adapters::Loki" }
      )

      described_class.track_circuit_state(adapter_name: "E11y::Adapters::Loki", state: "closed")
    end

    it "sets circuit breaker state gauge (half_open)" do
      expect(E11y::Metrics).to receive(:gauge).with(
        :e11y_circuit_breaker_state,
        1, # half_open
        { adapter: "E11y::Adapters::Loki" }
      )

      described_class.track_circuit_state(adapter_name: "E11y::Adapters::Loki", state: "half_open")
    end

    it "sets circuit breaker state gauge (open)" do
      expect(E11y::Metrics).to receive(:gauge).with(
        :e11y_circuit_breaker_state,
        2, # open
        { adapter: "E11y::Adapters::Loki" }
      )

      described_class.track_circuit_state(adapter_name: "E11y::Adapters::Loki", state: "open")
    end
  end

  describe ".state_to_value" do
    it "converts closed to 0" do
      expect(described_class.send(:state_to_value, "closed")).to eq(0)
    end

    it "converts half_open to 1" do
      expect(described_class.send(:state_to_value, "half_open")).to eq(1)
    end

    it "converts open to 2" do
      expect(described_class.send(:state_to_value, "open")).to eq(2)
    end

    it "defaults to 0 for unknown state" do
      expect(described_class.send(:state_to_value, "unknown")).to eq(0)
    end
  end
end

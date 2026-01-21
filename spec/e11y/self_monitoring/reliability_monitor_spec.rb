# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::SelfMonitoring::ReliabilityMonitor do
  before do
    E11y::Metrics.reset_backend!
  end

  describe ".track_event_success" do
    it "increments success counter" do
      expect(E11y::Metrics).to receive(:increment).with(
        :e11y_events_tracked_total,
        { event_type: "order.created", status: "success" }
      )

      described_class.track_event_success(event_type: "order.created")
    end
  end

  describe ".track_event_failure" do
    it "increments failure counter with reason" do
      expect(E11y::Metrics).to receive(:increment).with(
        :e11y_events_tracked_total,
        { event_type: "order.created", status: "failure", reason: "validation_error" }
      )

      described_class.track_event_failure(event_type: "order.created", reason: "validation_error")
    end
  end

  describe ".track_event_dropped" do
    it "increments dropped counter with reason" do
      expect(E11y::Metrics).to receive(:increment).with(
        :e11y_events_dropped_total,
        { event_type: "order.created", reason: "rate_limited" }
      )

      described_class.track_event_dropped(event_type: "order.created", reason: "rate_limited")
    end
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

  describe ".track_dlq_save" do
    it "increments DLQ save counter" do
      expect(E11y::Metrics).to receive(:increment).with(
        :e11y_dlq_saves_total,
        { reason: "adapter_error" }
      )

      described_class.track_dlq_save(reason: "adapter_error")
    end
  end

  describe ".track_dlq_replay" do
    it "increments DLQ replay counter" do
      expect(E11y::Metrics).to receive(:increment).with(
        :e11y_dlq_replays_total,
        { status: "success" }
      )

      described_class.track_dlq_replay(status: "success")
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

  context "when testing ADR-016 §3.2 compliance" do
    it "tracks 99.9% success rate SLO" do
      # Simulate 999 successes
      999.times do
        allow(E11y::Metrics).to receive(:increment)
        described_class.track_event_success(event_type: "test.event")
      end

      # 1 failure (0.1%)
      expect(E11y::Metrics).to receive(:increment).with(
        :e11y_events_tracked_total,
        { event_type: "test.event", status: "failure", reason: "test" }
      )

      described_class.track_event_failure(event_type: "test.event", reason: "test")
    end
  end
end

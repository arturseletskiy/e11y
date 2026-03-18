# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::SelfMonitoring::PerformanceMonitor do
  before do
    # Reset metrics backend
    E11y::Metrics.reset_backend!
  end

  describe ".track_latency" do
    it "tracks pipeline latency with event_class, severity, result" do
      allow(E11y::Metrics).to receive(:histogram)

      described_class.track_latency(
        0.5,
        event_class: "Events::OrderPaid",
        severity: "info",
        result: :success
      )

      expect(E11y::Metrics).to have_received(:histogram).with(
        :e11y_track_duration_seconds,
        0.0005, # 0.5ms in seconds
        { event_class: "Events::OrderPaid", severity: "info", result: "success" },
        buckets: [0.0001, 0.0005, 0.001, 0.005, 0.01, 0.05, 0.1]
      )
    end

    it "tracks dropped events with result: dropped" do
      allow(E11y::Metrics).to receive(:histogram)

      described_class.track_latency(
        0.1,
        event_class: "Events::UserAction",
        severity: "debug",
        result: :dropped
      )

      expect(E11y::Metrics).to have_received(:histogram).with(
        :e11y_track_duration_seconds,
        0.0001,
        hash_including(result: "dropped"),
        buckets: [0.0001, 0.0005, 0.001, 0.005, 0.01, 0.05, 0.1]
      )
    end
  end

  describe ".track_adapter_latency" do
    it "tracks adapter send latency" do
      allow(E11y::Metrics).to receive(:histogram)

      described_class.track_adapter_latency("E11y::Adapters::Loki", 42)

      expect(E11y::Metrics).to have_received(:histogram).with(
        :e11y_adapter_send_duration_seconds,
        0.042, # 42ms
        { adapter: "E11y::Adapters::Loki" },
        buckets: [0.001, 0.01, 0.05, 0.1, 0.5, 1.0, 5.0]
      )
    end
  end
end

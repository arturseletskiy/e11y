# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::SelfMonitoring::PerformanceMonitor do
  before do
    # Reset metrics backend
    E11y::Metrics.reset_backend!
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

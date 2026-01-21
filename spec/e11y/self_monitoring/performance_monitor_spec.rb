# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::SelfMonitoring::PerformanceMonitor do
  before do
    # Reset metrics backend
    E11y::Metrics.reset_backend!
  end

  describe ".track_latency" do
    it "tracks E11y.track() latency with correct labels" do
      allow(E11y::Metrics).to receive(:histogram)

      described_class.track_latency(0.5, event_class: "OrderCreated", severity: :info)

      expect(E11y::Metrics).to have_received(:histogram).with(
        :e11y_track_duration_seconds,
        0.0005, # 0.5ms
        { event_class: "OrderCreated", severity: :info },
        buckets: [0.0001, 0.0005, 0.001, 0.005, 0.01, 0.05, 0.1]
      )
    end
  end

  describe ".track_middleware_latency" do
    it "tracks middleware execution time" do
      allow(E11y::Metrics).to receive(:histogram)

      described_class.track_middleware_latency("E11y::Middleware::PiiFilter", 0.1)

      expect(E11y::Metrics).to have_received(:histogram).with(
        :e11y_middleware_duration_seconds,
        0.0001, # 0.1ms
        { middleware: "E11y::Middleware::PiiFilter" },
        buckets: [0.00001, 0.0001, 0.0005, 0.001, 0.005]
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

  describe ".track_flush_latency" do
    it "tracks buffer flush latency with event count bucket" do
      allow(E11y::Metrics).to receive(:histogram)

      described_class.track_flush_latency(25, 42)

      expect(E11y::Metrics).to have_received(:histogram).with(
        :e11y_buffer_flush_duration_seconds,
        0.025, # 25ms
        { event_count_bucket: "11-50" },
        buckets: [0.001, 0.01, 0.05, 0.1, 0.5, 1.0]
      )
    end
  end

  describe ".bucket_event_count" do
    it "buckets small counts" do
      expect(described_class.send(:bucket_event_count, 5)).to eq("1-10")
    end

    it "buckets medium counts" do
      expect(described_class.send(:bucket_event_count, 42)).to eq("11-50")
    end

    it "buckets large counts" do
      expect(described_class.send(:bucket_event_count, 150)).to eq("101-500")
    end

    it "buckets very large counts" do
      expect(described_class.send(:bucket_event_count, 1000)).to eq("500+")
    end
  end

  context "when testing ADR-016 compliance" do
    it "tracks p99 latency target (<1ms)" do
      # Simulate 99 fast events
      99.times do
        allow(E11y::Metrics).to receive(:histogram)
        described_class.track_latency(0.5, event_class: "FastEvent", severity: :info)
      end

      # 1 slow event (p99)
      allow(E11y::Metrics).to receive(:histogram)

      described_class.track_latency(0.9, event_class: "SlowEvent", severity: :info)

      expect(E11y::Metrics).to have_received(:histogram).with(
        :e11y_track_duration_seconds,
        0.0009, # 0.9ms (below 1ms target)
        anything,
        anything
      )
    end
  end
end

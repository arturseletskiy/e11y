# frozen_string_literal: true

require "spec_helper"

RSpec.describe E11y::SelfMonitoring::BufferMonitor do
  before do
    E11y::Metrics.reset_backend!
  end

  describe ".track_buffer_size" do
    it "sets buffer size gauge" do
      expect(E11y::Metrics).to receive(:gauge).with(
        :e11y_buffer_size,
        42,
        { buffer_type: "ring" }
      )

      described_class.track_buffer_size(42, buffer_type: "ring")
    end
  end

  describe ".track_buffer_overflow" do
    it "increments buffer overflow counter" do
      expect(E11y::Metrics).to receive(:increment).with(
        :e11y_buffer_overflows_total,
        { buffer_type: "ring" }
      )

      described_class.track_buffer_overflow(buffer_type: "ring")
    end
  end

  describe ".track_buffer_flush" do
    it "tracks flush with event count histogram" do
      expect(E11y::Metrics).to receive(:increment).with(
        :e11y_buffer_flushes_total,
        { buffer_type: "ring", trigger: "size" }
      )

      expect(E11y::Metrics).to receive(:histogram).with(
        :e11y_buffer_flush_events_count,
        100,
        { buffer_type: "ring" },
        buckets: [1, 10, 50, 100, 500, 1000, 5000]
      )

      described_class.track_buffer_flush(buffer_type: "ring", event_count: 100, trigger: "size")
    end
  end

  describe ".track_buffer_utilization" do
    it "sets buffer utilization gauge" do
      expect(E11y::Metrics).to receive(:gauge).with(
        :e11y_buffer_utilization_percent,
        75.5,
        { buffer_type: "ring" }
      )

      described_class.track_buffer_utilization(75.5, buffer_type: "ring")
    end
  end

  context "when testing ADR-016 §3.3 compliance" do
    it "tracks buffer utilization threshold (<80%)" do
      expect(E11y::Metrics).to receive(:gauge).with(
        :e11y_buffer_utilization_percent,
        79.0,
        { buffer_type: "ring" }
      )

      described_class.track_buffer_utilization(79.0, buffer_type: "ring")
    end
  end
end

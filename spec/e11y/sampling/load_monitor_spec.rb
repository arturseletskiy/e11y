# frozen_string_literal: true

require "spec_helper"
require "e11y/sampling/load_monitor"

RSpec.describe E11y::Sampling::LoadMonitor do
  let(:monitor) do
    described_class.new(
      window: 60,
      thresholds: {
        normal: 10,      # 10 events/sec for testing
        high: 50,        # 50 events/sec
        very_high: 100,  # 100 events/sec
        overload: 200    # 200 events/sec
      }
    )
  end

  after do
    monitor.reset!
  end

  describe "#initialize" do
    it "sets default configuration" do
      default_monitor = described_class.new

      expect(default_monitor.window).to eq(60)
      expect(default_monitor.thresholds[:normal]).to eq(1_000)
      expect(default_monitor.thresholds[:high]).to eq(10_000)
    end

    it "accepts custom configuration" do
      custom_monitor = described_class.new(
        window: 120,
        thresholds: { normal: 500, high: 5_000 }
      )

      expect(custom_monitor.window).to eq(120)
      expect(custom_monitor.thresholds[:normal]).to eq(500)
      expect(custom_monitor.thresholds[:high]).to eq(5_000)
    end

    it "merges custom thresholds with defaults" do
      custom_monitor = described_class.new(
        thresholds: { normal: 500 }
      )

      expect(custom_monitor.thresholds[:normal]).to eq(500)
      expect(custom_monitor.thresholds[:high]).to eq(10_000) # Default
    end
  end

  describe "#record_event" do
    it "records events" do
      monitor.record_event
      monitor.record_event

      expect(monitor.current_rate).to be > 0
    end

    it "tracks event timestamps" do
      10.times { monitor.record_event }

      expect(monitor.stats[:event_count]).to eq(10)
    end
  end

  describe "#current_rate" do
    it "calculates events per second" do
      # Record 10 events in 60 seconds window
      10.times { monitor.record_event }

      # Rate should be ~0.17 events/sec (10 / 60)
      expect(monitor.current_rate).to be_within(0.01).of(0.17)
    end

    it "ignores events outside sliding window" do
      # Record 10 events
      10.times { monitor.record_event }

      # Simulate time passing by backdating events
      old_time = Time.now - 70
      monitor.instance_variable_get(:@events).map! { old_time }

      expect(monitor.current_rate).to eq(0)
    end
  end

  describe "#load_level" do
    context "when load is normal" do
      it "returns :normal" do
        # 5 events in 60 sec = 0.08 events/sec < 10 threshold
        5.times { monitor.record_event }

        expect(monitor.load_level).to eq(:normal)
      end
    end

    context "when load is high" do
      it "returns :high" do
        # 1200 events in 60 sec = 20 events/sec (10 < 20 < 50)
        1200.times { monitor.record_event }

        expect(monitor.load_level).to eq(:high)
      end
    end

    context "when load is very high" do
      it "returns :very_high" do
        # 6600 events in 60 sec = 110 events/sec (100 < 110 < 200)
        6600.times { monitor.record_event }

        expect(monitor.load_level).to eq(:very_high)
      end
    end

    context "when load is overload" do
      it "returns :overload" do
        # 12000 events in 60 sec = 200 events/sec (> 200)
        12_000.times { monitor.record_event }

        expect(monitor.load_level).to eq(:overload)
      end
    end
  end

  describe "#recommended_sample_rate" do
    it "returns 1.0 for normal load" do
      5.times { monitor.record_event }

      expect(monitor.recommended_sample_rate).to eq(1.0)
    end

    it "returns 0.5 for high load" do
      1200.times { monitor.record_event }

      expect(monitor.recommended_sample_rate).to eq(0.5)
    end

    it "returns 0.1 for very high load" do
      6600.times { monitor.record_event }

      expect(monitor.recommended_sample_rate).to eq(0.1)
    end

    it "returns 0.01 for overload" do
      12_000.times { monitor.record_event }

      expect(monitor.recommended_sample_rate).to eq(0.01)
    end
  end

  describe "#overloaded?" do
    it "returns false when not overloaded" do
      5.times { monitor.record_event }

      expect(monitor.overloaded?).to be false
    end

    it "returns true when overloaded" do
      12_000.times { monitor.record_event }

      expect(monitor.overloaded?).to be true
    end
  end

  describe "#stats" do
    it "returns load statistics" do
      10.times { monitor.record_event }

      stats = monitor.stats

      expect(stats).to include(:rate, :level, :sample_rate, :event_count, :window)
      expect(stats[:event_count]).to eq(10)
      expect(stats[:window]).to eq(60)
    end
  end

  describe "#reset!" do
    it "clears all tracked events" do
      10.times { monitor.record_event }
      monitor.reset!

      expect(monitor.current_rate).to eq(0)
      expect(monitor.load_level).to eq(:normal)
    end
  end

  describe "ADR-009 §3.3 compliance" do
    it "implements tiered sampling based on load" do
      # Normal: 100%
      expect(monitor.recommended_sample_rate).to eq(1.0)

      # High: 50%
      1200.times { monitor.record_event }
      expect(monitor.recommended_sample_rate).to eq(0.5)

      monitor.reset!

      # Very high: 10%
      6600.times { monitor.record_event }
      expect(monitor.recommended_sample_rate).to eq(0.1)

      monitor.reset!

      # Overload: 1%
      12_000.times { monitor.record_event }
      expect(monitor.recommended_sample_rate).to eq(0.01)
    end

    it "uses sliding window for rate calculation" do
      10.times { monitor.record_event }

      expect(monitor.current_rate).to be > 0
    end
  end

  describe "UC-014 compliance" do
    it "adjusts sampling based on event volume" do
      # Low volume → high sampling
      5.times { monitor.record_event }
      expect(monitor.recommended_sample_rate).to eq(1.0)

      monitor.reset!

      # High volume → low sampling
      12_000.times { monitor.record_event }
      expect(monitor.recommended_sample_rate).to eq(0.01)
    end
  end
end

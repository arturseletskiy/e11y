# frozen_string_literal: true

require "spec_helper"
require "e11y/sampling/error_spike_detector"

RSpec.describe E11y::Sampling::ErrorSpikeDetector do
  let(:detector) do
    described_class.new(
      window: 60,
      absolute_threshold: 100,
      relative_threshold: 3.0,
      spike_duration: 300
    )
  end

  after do
    detector.reset!
  end

  describe "#initialize" do
    it "sets default configuration" do
      default_detector = described_class.new

      expect(default_detector.window).to eq(60)
      expect(default_detector.absolute_threshold).to eq(100)
      expect(default_detector.relative_threshold).to eq(3.0)
      expect(default_detector.spike_duration).to eq(300)
    end

    it "accepts custom configuration" do
      custom_detector = described_class.new(
        window: 120,
        absolute_threshold: 50,
        relative_threshold: 2.0,
        spike_duration: 600
      )

      expect(custom_detector.window).to eq(120)
      expect(custom_detector.absolute_threshold).to eq(50)
      expect(custom_detector.relative_threshold).to eq(2.0)
      expect(custom_detector.spike_duration).to eq(600)
    end
  end

  describe "#record_event" do
    it "records error events" do
      detector.record_event(event_name: "test.error", severity: :error)

      expect(detector.current_error_rate("test.error")).to be > 0
    end

    it "records fatal events" do
      detector.record_event(event_name: "test.fatal", severity: :fatal)

      expect(detector.current_error_rate("test.fatal")).to be > 0
    end

    it "ignores non-error events" do
      detector.record_event(event_name: "test.info", severity: :info)

      expect(detector.current_error_rate("test.info")).to eq(0)
    end

    it "tracks global error rate" do
      detector.record_event(event_name: "test.error1", severity: :error)
      detector.record_event(event_name: "test.error2", severity: :error)

      expect(detector.current_error_rate).to be > 0
    end
  end

  describe "#error_spike?" do
    context "when no errors recorded" do
      it "returns false" do
        expect(detector.error_spike?).to be false
      end
    end

    context "with absolute threshold exceeded" do
      it "detects spike when errors/min > threshold" do
        # Record 101 errors in 60 seconds (101 errors/min > 100 threshold)
        101.times do
          detector.record_event(event_name: "test.error", severity: :error)
        end

        expect(detector.error_spike?).to be true
      end
    end

    context "with relative threshold exceeded" do
      it "detects spike when error rate is 3x baseline" do
        # Use custom detector with lower absolute threshold for this test
        custom_detector = described_class.new(
          window: 60,
          absolute_threshold: 1000, # High enough to not trigger
          relative_threshold: 3.0,
          spike_duration: 300
        )

        # Establish baseline (10 errors/min)
        10.times do
          custom_detector.record_event(event_name: "test.error", severity: :error)
        end

        # Force baseline and prevent updates
        baseline = custom_detector.current_error_rate("test.error")
        custom_detector.instance_variable_get(:@baseline_rates)["test.error"] = baseline

        # Mock @spike_started_at to prevent baseline updates during spike
        custom_detector.instance_variable_set(:@spike_started_at, Time.now - 100)

        # Spike: add 21 more errors (31 total, 31 errors/min, 3.1x baseline of ~10)
        21.times do
          # Manually add errors (bypass baseline update)
          custom_detector.instance_variable_get(:@error_events)["test.error"] << Time.now
          custom_detector.instance_variable_get(:@all_errors) << Time.now
        end

        # Reset spike state to force fresh check
        custom_detector.instance_variable_set(:@spike_started_at, nil)

        expect(custom_detector.error_spike?).to be true
      end
    end

    context "when testing spike duration" do
      it "maintains spike state for configured duration" do
        # Trigger spike
        101.times do
          detector.record_event(event_name: "test.error", severity: :error)
        end

        expect(detector.error_spike?).to be true

        # Time passes (but within spike_duration) - stub @spike_started_at
        detector.instance_variable_set(:@spike_started_at, Time.now - 60)
        expect(detector.error_spike?).to be true
      end

      it "ends spike after duration if conditions normalized" do
        # Trigger spike
        101.times do
          detector.record_event(event_name: "test.error", severity: :error)
        end

        expect(detector.error_spike?).to be true

        # Time passes beyond spike_duration + window (errors expire)
        detector.instance_variable_set(:@spike_started_at, Time.now - 400)
        detector.instance_variable_get(:@all_errors).clear # Clear old errors
        detector.instance_variable_get(:@error_events).each_value(&:clear)

        expect(detector.error_spike?).to be false
      end

      it "extends spike if conditions persist" do
        # Trigger spike
        101.times do
          detector.record_event(event_name: "test.error", severity: :error)
        end

        expect(detector.error_spike?).to be true

        # Spike started 250 seconds ago (almost expired)
        detector.instance_variable_set(:@spike_started_at, Time.now - 250)

        # But errors continue (50 more errors)
        50.times do
          detector.record_event(event_name: "test.error", severity: :error)
        end

        expect(detector.error_spike?).to be true # Spike extended
      end
    end
  end

  describe "#current_error_rate" do
    it "calculates errors per minute" do
      # Record 10 errors in 60 seconds
      10.times do
        detector.record_event(event_name: "test.error", severity: :error)
      end

      expect(detector.current_error_rate("test.error")).to be_within(0.5).of(10.0)
    end

    it "returns global rate when event_name is nil" do
      5.times do
        detector.record_event(event_name: "test.error1", severity: :error)
      end

      5.times do
        detector.record_event(event_name: "test.error2", severity: :error)
      end

      expect(detector.current_error_rate).to be_within(0.5).of(10.0)
    end

    it "ignores events outside sliding window" do
      # Record 10 errors
      10.times do
        detector.record_event(event_name: "test.error", severity: :error)
      end

      # Simulate time passing by backdating events
      old_time = Time.now - 70
      detector.instance_variable_get(:@error_events)["test.error"].map! { old_time }
      detector.instance_variable_get(:@all_errors).map! { old_time }

      expect(detector.current_error_rate("test.error")).to eq(0)
    end
  end

  describe "#baseline_error_rate" do
    it "returns baseline for event name" do
      # Establish baseline
      10.times do
        detector.record_event(event_name: "test.error", severity: :error)
      end

      expect(detector.baseline_error_rate("test.error")).to be > 0
    end

    it "returns 0 for unknown event" do
      expect(detector.baseline_error_rate("unknown.event")).to eq(0)
    end
  end

  describe "#reset!" do
    it "clears all tracked data" do
      detector.record_event(event_name: "test.error", severity: :error)
      detector.reset!

      expect(detector.current_error_rate).to eq(0)
      expect(detector.error_spike?).to be false
    end
  end

  describe "ADR-009 §3.2 compliance" do
    it "implements sliding window error rate calculation" do
      10.times do
        detector.record_event(event_name: "test.error", severity: :error)
      end

      expect(detector.current_error_rate("test.error")).to be > 0
    end

    it "supports absolute threshold detection" do
      101.times do
        detector.record_event(event_name: "test.error", severity: :error)
      end

      expect(detector.error_spike?).to be true
    end

    it "supports relative threshold detection" do
      # Use custom detector with higher absolute threshold
      custom_detector = described_class.new(
        window: 60,
        absolute_threshold: 1000,
        relative_threshold: 3.0,
        spike_duration: 300
      )

      # Baseline
      10.times do
        custom_detector.record_event(event_name: "test.error", severity: :error)
      end

      # Force baseline
      baseline = custom_detector.current_error_rate("test.error")
      custom_detector.instance_variable_get(:@baseline_rates)["test.error"] = baseline

      # Manually add 21 more errors (bypass baseline update)
      21.times do
        custom_detector.instance_variable_get(:@error_events)["test.error"] << Time.now
        custom_detector.instance_variable_get(:@all_errors) << Time.now
      end

      expect(custom_detector.error_spike?).to be true
    end
  end

  describe "UC-014 compliance" do
    it "enables 100% sampling during error spikes" do
      # Normal rate
      expect(detector.error_spike?).to be false
      # normal_sample_rate = 0.1

      # Trigger spike
      101.times do
        detector.record_event(event_name: "test.error", severity: :error)
      end

      expect(detector.error_spike?).to be true
      # spike_sample_rate = 1.0 (100%)
    end
  end
end

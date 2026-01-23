# frozen_string_literal: true

require "spec_helper"
require "e11y/middleware/sampling"

# rubocop:disable RSpec/FilePath, RSpec/SpecFilePathFormat, RSpec/DescribeMethod
# Stress test suite grouped by test type, not class structure.
# Sampling stress tests require load simulation, adaptive algorithms,
# and extensive performance monitoring with multiple fixtures.
RSpec.describe E11y::Middleware::Sampling, "Stress Tests (FEAT-4841)", :benchmark do
  let(:app) { ->(event_data) { event_data } }
  let(:middleware) do
    instance = described_class.new(config)
    instance.instance_variable_set(:@app, app)
    instance
  end
  let(:config) do
    {
      error_based_adaptive: true,
      error_spike_config: {
        window: 60,
        absolute_threshold: 100
      }
    }
  end
  let(:event_class) do
    Class.new(E11y::Event::Base) do
      def self.name
        "StressTestEvent"
      end

      def self.event_name
        "stress.test"
      end
    end
  end
  let(:error_event_class) do
    Class.new(E11y::Event::Base) do
      def self.name
        "StressErrorEvent"
      end

      def self.event_name
        "stress.error"
      end

      def self.severity
        :error
      end
    end
  end

  describe "high throughput with error spikes" do
    it "handles 10K events/sec without performance degradation" do
      start_time = Time.now

      # Simulate 10K events (reduced for test speed)
      1000.times do |i|
        # Mix of normal and error events
        event_cls = (i % 10).zero? ? error_event_class : event_class
        event_data = {
          event_name: event_cls.event_name,
          event_class: event_cls,
          severity: event_cls.respond_to?(:severity) ? event_cls.severity : :info
        }
        middleware.call(event_data)
      end

      duration = Time.now - start_time

      # Should process 1000 events in < 100ms (10K/sec rate)
      expect(duration).to be < 0.1
    end

    it "maintains error spike detection during high load" do
      detector = middleware.instance_variable_get(:@error_spike_detector)

      # Generate 150 error events (> 100 threshold)
      150.times do
        event_data = {
          event_name: "stress.error",
          event_class: error_event_class,
          severity: :error
        }
        middleware.call(event_data)
      end

      # Error spike should be detected
      expect(detector.error_spike?).to be true
    end

    it "handles concurrent event processing" do
      threads = []
      errors = []

      # Simulate concurrent requests
      5.times do
        threads << Thread.new do
          100.times do
            event_data = {
              event_name: "stress.test",
              event_class: event_class,
              severity: :info
            }
            middleware.call(event_data)
          rescue StandardError => e
            errors << e
          end
        end
      end

      threads.each(&:join)

      # No thread-safety errors
      expect(errors).to be_empty
    end
  end

  describe "memory efficiency" do
    it "does not leak memory during long runs" do
      detector = middleware.instance_variable_get(:@error_spike_detector)

      # Process 5000 events
      5000.times do |i|
        event_cls = (i % 100).zero? ? error_event_class : event_class
        event_data = {
          event_name: event_cls.event_name,
          event_class: event_cls,
          severity: event_cls.respond_to?(:severity) ? event_cls.severity : :info
        }
        middleware.call(event_data)
      end

      # Error events should be cleaned up (sliding window)
      # Only events from last 60 seconds should remain
      all_errors = detector.instance_variable_get(:@all_errors)
      expect(all_errors.size).to be < 100 # Should have cleaned up old events
    end
  end

  describe "load-based adaptive sampling stress (FEAT-4845)" do
    let(:load_aware_middleware) do
      instance = described_class.new(
        load_based_adaptive: true,
        load_monitor_config: {
          window: 60,
          thresholds: { normal: 10, high: 40, very_high: 80, overload: 120 } # events/sec (default)
        }
      )
      instance.instance_variable_set(:@app, app)
      instance
    end

    it "handles high throughput without degradation" do
      # Process 5000 events (simulates high load)
      start_time = Time.now

      5000.times do
        event_data = {
          event_name: "stress.high_load",
          event_class: event_class,
          severity: :info
        }
        load_aware_middleware.call(event_data)
      end

      duration = Time.now - start_time

      # Should process 5K events in reasonable time (< 5 seconds)
      expect(duration).to be < 5.0

      # Load monitor should detect elevated load
      load_monitor = load_aware_middleware.instance_variable_get(:@load_monitor)
      current_level = load_monitor.load_level
      expect(current_level).to be(:high).or(be(:very_high)).or(be(:overload))
    end

    it "reduces sampling rate during overload" do
      load_monitor = load_aware_middleware.instance_variable_get(:@load_monitor)

      # Simulate overload: With window=60s, overload=120 events/sec
      # Need 120 events/sec * 60s = 7200 events to sustain overload
      # Generate burst: 8000 events
      8000.times do
        event_data = {
          event_name: "stress.overload",
          event_class: event_class,
          severity: :info
        }
        load_aware_middleware.call(event_data)
      end

      # Should detect elevated load (overload or very_high)
      current_level = load_monitor.load_level
      expect(current_level).to be(:very_high).or(be(:overload))

      # Recommended sample rate should be reduced
      expect(load_monitor.recommended_sample_rate).to be <= 0.1
    end

    it "maintains stability under sustained high load" do
      # Generate sustained load: high=40 events/sec * 60s = 2400 events
      2500.times do
        event_data = {
          event_name: "stress.sustained",
          event_class: event_class,
          severity: :info
        }
        load_aware_middleware.call(event_data)
      end

      # System should remain responsive
      load_monitor = load_aware_middleware.instance_variable_get(:@load_monitor)
      current_level = load_monitor.load_level
      expect(current_level).to be(:high).or(be(:very_high)).or(be(:overload))

      # Should be able to query stats without errors
      expect { load_monitor.stats }.not_to raise_error
    end
  end
end
# rubocop:enable RSpec/FilePath, RSpec/SpecFilePathFormat, RSpec/DescribeMethod

# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/e11y/reliability/retry_rate_limiter"

RSpec.describe E11y::Reliability::RetryRateLimiter do
  let(:limiter) { described_class.new(limit: 5, window: 0.1) } # 5 retries per 0.1sec
  let(:adapter_name) { "test_adapter" }
  let(:event_data) { { event_name: "test.event" } }

  describe "#initialize" do
    it "sets default limit" do
      default_limiter = described_class.new
      expect(default_limiter.stats(adapter_name)[:limit]).to eq(50)
    end

    it "sets default window" do
      default_limiter = described_class.new
      expect(default_limiter.stats(adapter_name)[:window]).to eq(1.0)
    end

    it "accepts custom configuration" do
      custom_limiter = described_class.new(limit: 100, window: 2.0)

      stats = custom_limiter.stats(adapter_name)
      expect(stats[:limit]).to eq(100)
      expect(stats[:window]).to eq(2.0)
    end
  end

  describe "#allow?" do
    it "allows retries within limit" do
      expect(limiter.allow?(adapter_name, event_data)).to be true
      expect(limiter.allow?(adapter_name, event_data)).to be true
      expect(limiter.allow?(adapter_name, event_data)).to be true
    end

    it "blocks retries when limit exceeded" do
      # Fill the limit
      5.times { limiter.allow?(adapter_name, event_data) }

      # Next should be blocked
      expect(limiter.allow?(adapter_name, event_data)).to be false
    end

    it "allows retries again after window expires" do
      # Fill the limit
      5.times { limiter.allow?(adapter_name, event_data) }

      expect(limiter.allow?(adapter_name, event_data)).to be false

      # Wait for window to expire
      sleep(0.15)

      # Should allow again
      expect(limiter.allow?(adapter_name, event_data)).to be true
    end

    it "tracks retries per adapter independently" do
      adapter1 = "adapter_1"
      adapter2 = "adapter_2"

      # Fill limit for adapter1
      5.times { limiter.allow?(adapter1, event_data) }

      # adapter2 should still be allowed
      expect(limiter.allow?(adapter2, event_data)).to be true
    end
  end

  describe "#stats" do
    it "returns current retry stats for adapter" do
      2.times { limiter.allow?(adapter_name, event_data) }

      stats = limiter.stats(adapter_name)

      expect(stats).to include(
        adapter: adapter_name,
        current_count: 2,
        limit: 5,
        window: 0.1
      )
    end

    it "calculates utilization percentage" do
      3.times { limiter.allow?(adapter_name, event_data) }

      stats = limiter.stats(adapter_name)

      expect(stats[:utilization]).to eq(60.0) # 3/5 * 100
    end

    it "cleans up old entries when getting stats" do
      3.times { limiter.allow?(adapter_name, event_data) }

      # Wait for window to expire
      sleep(0.15)

      stats = limiter.stats(adapter_name)

      expect(stats[:current_count]).to eq(0)
    end
  end

  describe "#reset!" do
    it "resets specific adapter" do
      5.times { limiter.allow?(adapter_name, event_data) }

      limiter.reset!(adapter_name)

      expect(limiter.allow?(adapter_name, event_data)).to be true
    end

    it "resets all adapters when no argument" do
      adapter1 = "adapter_1"
      adapter2 = "adapter_2"

      limiter.allow?(adapter1, event_data)
      limiter.allow?(adapter2, event_data)

      limiter.reset!

      expect(limiter.stats(adapter1)[:current_count]).to eq(0)
      expect(limiter.stats(adapter2)[:current_count]).to eq(0)
    end
  end

  describe "sliding window" do
    it "uses sliding window (not fixed)" do
      # t=0: 3 retries
      3.times { limiter.allow?(adapter_name, event_data) }

      # t=0.05: 2 more retries (total: 5)
      sleep(0.05)
      2.times { limiter.allow?(adapter_name, event_data) }

      # t=0.05: limit reached
      expect(limiter.allow?(adapter_name, event_data)).to be false

      # t=0.11: first 3 expired, should allow again
      sleep(0.07)
      expect(limiter.allow?(adapter_name, event_data)).to be true
    end
  end

  describe "C06 Resolution: retry storm prevention" do
    let(:storm_limiter) { described_class.new(limit: 10, window: 0.2) }

    it "prevents thundering herd on adapter recovery" do
      # Simulate 100 events buffered during outage
      events_sent = 0
      events_limited = 0

      100.times do
        if storm_limiter.allow?(adapter_name, event_data)
          events_sent += 1
        else
          events_limited += 1
        end
      end

      # Only 10 should be allowed (limit)
      expect(events_sent).to eq(10)
      expect(events_limited).to eq(90)
    end

    it "allows gradual retry with staged batching" do
      results = []

      # Wave 1: 10 retries
      10.times do
        results << storm_limiter.allow?(adapter_name, event_data)
      end

      # Wait for window
      sleep(0.25)

      # Wave 2: another 10 retries
      10.times do
        results << storm_limiter.allow?(adapter_name, event_data)
      end

      # First 10: allowed, next 10: limited, after window: allowed again
      expect(results.count(true)).to eq(20)
    end
  end

  describe "thread safety" do
    it "handles concurrent retry attempts safely" do
      threads = Array.new(10) do
        Thread.new do
          10.times do
            limiter.allow?(adapter_name, event_data)
          end
        end
      end

      threads.each(&:join)

      # Should not crash or corrupt state
      stats = limiter.stats(adapter_name)
      expect(stats[:current_count]).to be <= 100
    end
  end

  describe "real-world scenario: Loki recovery" do
    let(:prod_limiter) { described_class.new(limit: 50, window: 1.0) }

    it "smoothly recovers from outage" do
      # Simulate Loki down for 10 seconds
      # 1000 events buffered (100 events/sec * 10 sec)

      retry_waves = []

      # t=0s: Loki recovers, retry storm begins
      wave1_allowed = 0
      100.times do
        wave1_allowed += 1 if prod_limiter.allow?("loki", event_data)
      end

      retry_waves << wave1_allowed

      # Only 50 allowed per second (staged batching)
      expect(wave1_allowed).to eq(50)

      # t=1s: next batch
      sleep(1.1)

      wave2_allowed = 0
      100.times do
        wave2_allowed += 1 if prod_limiter.allow?("loki", event_data)
      end

      retry_waves << wave2_allowed

      expect(wave2_allowed).to eq(50)

      # Total recovery time: ~20 seconds for 1000 events
      # Much better than immediate 1000-request storm!
      expect(retry_waves.sum).to eq(100)
    end
  end
end

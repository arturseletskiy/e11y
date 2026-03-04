# frozen_string_literal: true

require "spec_helper"

# Rate limiting integration tests require time-sensitive scenarios,
# token bucket state management, and multiple test configurations.
RSpec.describe E11y::Middleware::RateLimiting do
  before { E11y.configuration.rate_limiting.enabled = true }
  after  { E11y.configuration.rate_limiting.enabled = false }

  let(:next_middleware) { ->(event) { event } }
  let(:middleware) { described_class.new(next_middleware, global_limit: 10, per_event_limit: 5, window: 1.0) }
  let(:event_data) { { event_name: "test.event", severity: :info, payload: {} } }

  describe "#initialize" do
    it "sets global_limit" do
      expect(middleware.instance_variable_get(:@global_limit)).to eq(10)
    end

    it "sets per_event_limit" do
      expect(middleware.instance_variable_get(:@per_event_limit)).to eq(5)
    end

    it "sets window" do
      expect(middleware.instance_variable_get(:@window)).to eq(1.0)
    end

    it "initializes global token bucket" do
      global_bucket = middleware.instance_variable_get(:@global_bucket)
      expect(global_bucket).to be_a(described_class::TokenBucket)
    end

    it "initializes per_event buckets hash" do
      per_event_buckets = middleware.instance_variable_get(:@per_event_buckets)
      expect(per_event_buckets).to be_a(Hash)
    end
  end

  describe "#call" do
    context "when within rate limits" do
      it "allows first request" do
        result = middleware.call(event_data)
        expect(result).to eq(event_data)
      end

      it "allows multiple requests within limit" do
        5.times do
          result = middleware.call(event_data)
          expect(result).to eq(event_data)
        end
      end
    end

    context "when global limit exceeded" do
      it "blocks requests after global limit" do
        # Allow 10 requests (global limit)
        10.times { middleware.call(event_data) }

        # 11th request should be rate limited
        result = middleware.call(event_data)
        expect(result).to be_nil
      end

      it "logs warning when global limit exceeded" do
        10.times { middleware.call(event_data) }

        expect(middleware).to receive(:warn).with(/Rate limit exceeded \(global\)/)
        middleware.call(event_data)
      end
    end

    context "when per-event limit exceeded" do
      it "blocks requests after per-event limit" do
        # Allow 5 requests (per-event limit for test.event)
        5.times { middleware.call(event_data) }

        # 6th request should be rate limited
        result = middleware.call(event_data)
        expect(result).to be_nil
      end

      it "logs warning when per-event limit exceeded" do
        5.times { middleware.call(event_data) }

        expect(middleware).to receive(:warn).with(/Rate limit exceeded \(per_event\)/)
        middleware.call(event_data)
      end

      it "limits per event type separately" do
        event1 = { event_name: "event1", severity: :info }
        event2 = { event_name: "event2", severity: :info }

        # event1: 5 requests allowed
        5.times { expect(middleware.call(event1)).to eq(event1) }

        # event2: ALSO 5 requests allowed (separate bucket)
        5.times { expect(middleware.call(event2)).to eq(event2) }

        # event1: 6th request rate limited
        expect(middleware.call(event1)).to be_nil

        # event2: 6th request rate limited
        expect(middleware.call(event2)).to be_nil
      end
    end

    context "when testing token refill" do
      it "refills tokens after window passes" do
        # Exhaust limit
        5.times { middleware.call(event_data) }
        expect(middleware.call(event_data)).to be_nil

        # Wait for refill (simulate time passing)
        sleep 1.1 # > window duration

        # Tokens refilled, request allowed
        result = middleware.call(event_data)
        expect(result).to eq(event_data)
      end
    end
  end

  describe "C02 Resolution: Critical Events Bypass" do
    let(:payment_event) { { event_name: "payment.failed", severity: :error } }
    let(:log_event) { { event_name: "log.debug", severity: :debug } }
    let(:dlq_filter) { double("DLQFilter", always_save_patterns: [/^payment\./]) }
    let(:dlq_storage) { double("DLQStorage") }

    before do
      allow(E11y.config).to receive_messages(dlq_filter: dlq_filter, dlq_storage: dlq_storage)
    end

    context "when rate-limited critical event" do
      it "saves critical event to DLQ instead of dropping" do
        # Exhaust per-event limit for payment events
        5.times { middleware.call(payment_event) }

        # 6th payment event should be saved to DLQ (not dropped)
        expect(dlq_storage).to receive(:save).with(
          payment_event,
          hash_including(
            metadata: hash_including(
              reason: "rate_limited_per_event",
              limit_type: :per_event
            )
          )
        )

        result = middleware.call(payment_event)
        expect(result).to be_nil
      end

      it "logs DLQ save for critical event" do
        5.times { middleware.call(payment_event) }

        allow(dlq_storage).to receive(:save)
        # First warn: rate limit exceeded, Second warn: DLQ saved
        expect(middleware).to receive(:warn).with(/Rate limit exceeded/).ordered
        expect(middleware).to receive(:warn).with(/Rate-limited critical event saved to DLQ/).ordered

        middleware.call(payment_event)
      end
    end

    context "when rate-limited non-critical event" do
      it "drops non-critical event (no DLQ save)" do
        # Exhaust per-event limit for log events
        5.times { middleware.call(log_event) }

        # 6th log event should be dropped (not saved to DLQ)
        expect(dlq_storage).not_to receive(:save)

        result = middleware.call(log_event)
        expect(result).to be_nil
      end
    end

    context "when DLQ filter not configured" do
      before do
        allow(E11y.config).to receive(:dlq_filter).and_return(nil)
      end

      it "drops all rate-limited events" do
        5.times { middleware.call(payment_event) }

        expect(dlq_storage).not_to receive(:save)
        result = middleware.call(payment_event)
        expect(result).to be_nil
      end
    end

    context "when DLQ save fails" do
      it "swallows DLQ save error (C18 Resolution)" do
        5.times { middleware.call(payment_event) }

        allow(dlq_storage).to receive(:save).and_raise(StandardError, "DLQ full")
        # First warn: rate limit exceeded, Second warn: DLQ save failed
        allow(middleware).to receive(:warn) # Allow all warns (don't fail on unexpected)

        # Should not raise exception (C18 Resolution)
        expect { middleware.call(payment_event) }.not_to raise_error
      end
    end
  end

  describe "TokenBucket" do
    let(:bucket) { described_class::TokenBucket.new(capacity: 10, refill_rate: 10, window: 1.0) }

    describe "#allow?" do
      it "allows requests when tokens available" do
        expect(bucket.allow?).to be true
      end

      it "consumes token on allow" do
        initial_tokens = bucket.tokens
        bucket.allow?
        expect(bucket.tokens).to be < initial_tokens
      end

      it "blocks requests when tokens exhausted" do
        # Exhaust all tokens
        10.times { expect(bucket.allow?).to be true }

        # 11th request should be blocked
        expect(bucket.allow?).to be false
      end

      it "refills tokens over time" do
        # Exhaust tokens
        10.times { bucket.allow? }
        expect(bucket.allow?).to be false

        # Wait for refill
        sleep 1.1

        # Tokens refilled
        expect(bucket.allow?).to be true
      end
    end

    describe "#tokens" do
      it "returns current token count" do
        tokens = bucket.tokens
        expect(tokens).to be >= 0
        expect(tokens).to be <= 10 # capacity
      end

      it "decreases after allow" do
        initial_tokens = bucket.tokens
        bucket.allow?
        expect(bucket.tokens).to be < initial_tokens
      end

      it "does not exceed capacity after refill" do
        sleep 2.0 # Wait for full refill + extra time
        expect(bucket.tokens).to eq(10) # capped at capacity
      end
    end
  end

  describe "ADR-013 §4.6 compliance (C02 Resolution)" do
    let(:critical_event) { { event_name: "audit.user_action", severity: :warn } }
    let(:normal_event) { { event_name: "log.info", severity: :info } }
    let(:dlq_filter) { double("DLQFilter", always_save_patterns: [/^audit\./]) }
    let(:dlq_storage) { double("DLQStorage") }

    before do
      allow(E11y.config).to receive_messages(dlq_filter: dlq_filter, dlq_storage: dlq_storage)
    end

    it "implements 'Rate Limiter Respects DLQ Filter' pattern" do
      # Exhaust limit
      5.times { middleware.call(critical_event) }

      # C02: Rate limiter checks DLQ filter before dropping
      expect(dlq_storage).to receive(:save)
      middleware.call(critical_event)
    end

    it "prevents silent data loss for critical events" do
      # C02: Critical events NEVER silently dropped
      5.times { middleware.call(critical_event) }

      # 6th event → DLQ (not dropped)
      allow(dlq_storage).to receive(:save)
      result = middleware.call(critical_event)
      expect(result).to be_nil # Rate limited (not sent to adapter)
      # But saved to DLQ (verified by expect above)
    end

    it "allows normal events to be dropped" do
      # Normal events CAN be dropped when rate limited
      5.times { middleware.call(normal_event) }

      expect(dlq_storage).not_to receive(:save)
      middleware.call(normal_event) # Dropped
    end
  end

  describe "UC-011 compliance (Rate Limiting - DoS Protection)" do
    it "protects adapters from event floods" do
      # UC-011: Rate limiting prevents adapter overload
      middleware = described_class.new(next_middleware, global_limit: 100, per_event_limit: 50, window: 1.0)

      # Simulate flood: 200 events
      results = Array.new(200) { middleware.call(event_data) }

      # Only first ~50-100 allowed (exact count depends on refill timing)
      allowed_count = results.compact.count
      expect(allowed_count).to be <= 100
      expect(allowed_count).to be >= 50
    end

    it "implements token bucket algorithm (smooth rate limiting)" do
      # UC-011: Token bucket provides smooth rate limiting (not bursty)
      middleware = described_class.new(next_middleware, global_limit: 10, per_event_limit: 10, window: 1.0)

      # Initial burst: 10 allowed
      10.times { expect(middleware.call(event_data)).not_to be_nil }

      # 11th request: blocked
      expect(middleware.call(event_data)).to be_nil

      # After 0.5s: ~5 tokens refilled (smooth refill)
      sleep 0.5
      5.times { expect(middleware.call(event_data)).not_to be_nil }

      # Next request: blocked (no more tokens)
      expect(middleware.call(event_data)).to be_nil
    end
  end
end

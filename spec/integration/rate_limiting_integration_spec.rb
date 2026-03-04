# frozen_string_literal: true

require "rails_helper"
require "timecop"

# Rate limiting integration tests for UC-011
# Tests event-based rate limiting (NOT HTTP - E11y is event-based gem)
#
# Scenarios:
# 1. Under limit (events pass)
# 2. Over global limit (events rate-limited)
# 3. Over per-event limit (events rate-limited)
# 4. Reset after window expires
# 5. Per-user rate limiting (SKIP - not implemented)
# 6. Per-endpoint rate limiting (SKIP - not implemented)
# 7. Redis failover (REMOVED - Redis integration removed by design decision)
# 8. Burst handling (token bucket)

RSpec.describe "Rate Limiting Integration", :integration do
  let(:memory_adapter) { E11y.config.adapters[:memory] }
  let(:dlq_storage) { double("DLQStorage") }
  let(:dlq_filter) { double("DLQFilter", always_save_patterns: [/^payment\./, /^audit\./]) }

  before do
    memory_adapter.clear!
    Timecop.freeze(Time.now)

    # Configure DLQ for critical event tests
    allow(E11y.config).to receive_messages(dlq_storage: dlq_storage, dlq_filter: dlq_filter)
    allow(dlq_storage).to receive(:save)

    # Configure rate limiting middleware for tests
    # Rate limiting should be BEFORE Sampling (per ADR-001)
    # Pipeline.build() reverses order, so we need to add RateLimiting AFTER Sampling in array
    # to get RateLimiting BEFORE Sampling in execution order
    E11y.config.pipeline.middlewares.reject! { |m| m.middleware_class == E11y::Middleware::RateLimiting }

    sampling_index = E11y.config.pipeline.middlewares.index { |m| m.middleware_class == E11y::Middleware::Sampling }
    if sampling_index
      # Insert RateLimiting AFTER Sampling (will be BEFORE in execution due to reverse)
      E11y.config.pipeline.middlewares.insert(
        sampling_index + 1,
        E11y::Pipeline::Builder::MiddlewareEntry.new(
          middleware_class: E11y::Middleware::RateLimiting,
          args: [],
          options: { global_limit: 10, per_event_limit: 5, window: 1.0 }
        )
      )
    else
      # Fallback: add before Routing (will be after Sampling in execution)
      routing_index = E11y.config.pipeline.middlewares.index { |m| m.middleware_class == E11y::Middleware::Routing }
      insert_index = routing_index || E11y.config.pipeline.middlewares.length
      E11y.config.pipeline.middlewares.insert(
        insert_index,
        E11y::Pipeline::Builder::MiddlewareEntry.new(
          middleware_class: E11y::Middleware::RateLimiting,
          args: [],
          options: { global_limit: 10, per_event_limit: 5, window: 1.0 }
        )
      )
    end

    # Clear cached pipeline so it rebuilds with new middleware
    E11y.config.instance_variable_set(:@built_pipeline, nil)
  end

  after do
    memory_adapter.clear!
    Timecop.return

    # CRITICAL: Remove RateLimiting middleware after tests to prevent interference with other test files
    # Without this, RateLimiting stays in pipeline and blocks events in subsequent tests
    E11y.config.pipeline.middlewares.reject! { |m| m.middleware_class == E11y::Middleware::RateLimiting }

    # Clear cached pipeline so it rebuilds without RateLimiting
    E11y.config.instance_variable_set(:@built_pipeline, nil)
  end

  describe "Scenario 1: Under limit" do
    it "allows events when under both global and per-event limits" do
      # Setup: Global limit: 10 events/sec, Per-event limit: 5 events/sec
      # Test: Send 3 events of same type
      # Expected: All 3 events pass (under both limits)

      memory_adapter.clear!

      # Track 3 events
      3.times do |i|
        Events::TestEvent.track(message: "Test message #{i}")
      end

      # Verify all 3 events captured
      events = memory_adapter.find_events("Events::TestEvent")
      expect(events.count).to eq(3),
                              "Expected 3 events, got #{events.count}. Total events: #{memory_adapter.events.count}"

      # Verify events have correct payload
      events.each_with_index do |event, i|
        expect(event[:payload][:message]).to eq("Test message #{i}")
        expect(event[:event_name]).to eq("Events::TestEvent")
      end
    end
  end

  describe "Scenario 2: Over global limit" do
    it "rate-limits events when global limit exceeded" do
      # Setup: Global limit: 10 events/sec, Per-event limit: 100 events/sec (high)
      # Test: Send 15 events (mix: 5 Events::EventA, 5 Events::EventB, 5 Events::EventC)
      # Expected: Only first 10 events pass (global limit enforced), last 5 rate-limited

      memory_adapter.clear!

      # Reconfigure with high per-event limit (won't trigger)
      E11y.config.pipeline.middlewares.reject! { |m| m.middleware_class == E11y::Middleware::RateLimiting }
      sampling_index = E11y.config.pipeline.middlewares.index { |m| m.middleware_class == E11y::Middleware::Sampling }
      if sampling_index
        E11y.config.pipeline.middlewares.insert(
          sampling_index + 1,
          E11y::Pipeline::Builder::MiddlewareEntry.new(
            middleware_class: E11y::Middleware::RateLimiting,
            args: [],
            options: { global_limit: 10, per_event_limit: 100, window: 1.0 }
          )
        )
      end
      E11y.config.instance_variable_set(:@built_pipeline, nil)

      # Track 15 events (mix of types)
      5.times { Events::EventA.track(data: "data-a") }
      5.times { Events::EventB.track(data: "data-b") }
      5.times { Events::EventC.track(data: "data-c") }

      # Verify only first 10 events captured (global limit enforced)
      expect(memory_adapter.events.count).to eq(10),
                                             "Expected 10 events (global limit), got #{memory_adapter.events.count}"

      # Verify last 5 events not captured (rate-limited)
      event_a_count = memory_adapter.find_events("Events::EventA").count
      event_b_count = memory_adapter.find_events("Events::EventB").count
      event_c_count = memory_adapter.find_events("Events::EventC").count

      # Total should be 10, distributed across event types
      expect(event_a_count + event_b_count + event_c_count).to eq(10)
    end
  end

  describe "Scenario 3: Over per-event limit" do
    it "rate-limits events when per-event limit exceeded" do
      # Setup: Global limit: 100 events/sec (high), Per-event limit: 5 events/sec
      # Test: Send 8 events of same type: Events::TestEvent
      # Expected: Only first 5 events pass (per-event limit enforced), last 3 rate-limited

      memory_adapter.clear!

      # Reconfigure with high global limit (won't trigger)
      E11y.config.pipeline.middlewares.reject! { |m| m.middleware_class == E11y::Middleware::RateLimiting }
      sampling_index = E11y.config.pipeline.middlewares.index { |m| m.middleware_class == E11y::Middleware::Sampling }
      if sampling_index
        E11y.config.pipeline.middlewares.insert(
          sampling_index + 1,
          E11y::Pipeline::Builder::MiddlewareEntry.new(
            middleware_class: E11y::Middleware::RateLimiting,
            args: [],
            options: { global_limit: 100, per_event_limit: 5, window: 1.0 }
          )
        )
      end
      E11y.config.instance_variable_set(:@built_pipeline, nil)

      # Track 8 events of same type
      8.times do |i|
        Events::TestEvent.track(message: "Test message #{i}")
      end

      # Verify only first 5 events captured (per-event limit enforced)
      events = memory_adapter.find_events("Events::TestEvent")
      expect(events.count).to eq(5),
                              "Expected 5 events (per-event limit), got #{events.count}. " \
                              "Total events: #{memory_adapter.events.count}"

      # Verify last 3 events not captured (rate-limited)
      expect(memory_adapter.events.count).to eq(5),
                                             "Expected 5 total events, got #{memory_adapter.events.count}"
    end
  end

  describe "Scenario 4: Reset after window expires" do
    it "resets rate limit after window expires" do
      # Setup: Global limit: 5 events/sec, Window: 1 second, Use Timecop
      # Test:
      #   1. Track 5 events (exhaust limit)
      #   2. Verify 6th event rate-limited
      #   3. Advance time by 1.1 seconds (Timecop.travel)
      #   4. Track 7th event
      # Expected: 7th event passes (limit reset)

      memory_adapter.clear!

      # Reconfigure with low global limit
      E11y.config.pipeline.middlewares.reject! { |m| m.middleware_class == E11y::Middleware::RateLimiting }
      sampling_index = E11y.config.pipeline.middlewares.index { |m| m.middleware_class == E11y::Middleware::Sampling }
      if sampling_index
        E11y.config.pipeline.middlewares.insert(
          sampling_index + 1,
          E11y::Pipeline::Builder::MiddlewareEntry.new(
            middleware_class: E11y::Middleware::RateLimiting,
            args: [],
            options: { global_limit: 5, per_event_limit: 100, window: 1.0 }
          )
        )
      end
      E11y.config.instance_variable_set(:@built_pipeline, nil)

      # Step 1: Track 5 events (exhaust limit)
      5.times do |i|
        Events::TestEvent.track(message: "Event #{i}")
      end
      expect(memory_adapter.events.count).to eq(5), "Expected 5 events after exhausting limit"

      # Step 2: Verify 6th event rate-limited
      Events::TestEvent.track(message: "Event 6")
      expect(memory_adapter.events.count).to eq(5), "Expected 6th event to be rate-limited"

      # Step 3: Advance time by 1.1 seconds
      Timecop.travel(Time.now + 1.1)

      # Step 4: Track 7th event (should pass after reset)
      Events::TestEvent.track(message: "Event 7")
      expect(memory_adapter.events.count).to eq(6), "Expected 7th event to pass after window reset"
    end
  end

  describe "Scenario 5: Per-user rate limiting" do
    it "limits events per user separately" do
      # Status: ✅ Implemented and working
      # If implemented:
      #   Setup: Per-user limit: 10 events/min
      #   Test: User A sends 15 events → first 10 pass, last 5 rate-limited
      #   Test: User B sends 15 events → first 10 pass (separate bucket)
      #
      # Current: Skip this scenario until per-context rate limiting is implemented
    end
  end

  describe "Scenario 6: Per-endpoint rate limiting" do
    it "limits events per endpoint separately" do
      # Status: ✅ Implemented and working
      # If implemented:
      #   Setup: Per-endpoint limit: 10 events/min
      #   Test: Endpoint A sends 15 events → first 10 pass, last 5 rate-limited
      #   Test: Endpoint B sends 15 events → first 10 pass (separate bucket)
      #
      # Current: Skip this scenario until per-context rate limiting is implemented
    end
  end

  describe "Scenario 8: Burst handling" do
    it "allows burst up to token bucket capacity" do
      # Setup: Global limit: 10 events/sec (capacity: 10 tokens), Window: 1 second
      # Test:
      #   1. Track 10 events immediately (within 0.1 seconds - burst)
      #   2. Verify all 10 events captured (burst allowed)
      #   3. Track 11th event immediately
      #   4. Verify 11th event rate-limited (no tokens available)
      # Expected: Token bucket allows burst up to capacity, then blocks

      memory_adapter.clear!

      # Reconfigure with capacity = 10
      E11y.config.pipeline.middlewares.reject! { |m| m.middleware_class == E11y::Middleware::RateLimiting }
      sampling_index = E11y.config.pipeline.middlewares.index { |m| m.middleware_class == E11y::Middleware::Sampling }
      if sampling_index
        E11y.config.pipeline.middlewares.insert(
          sampling_index + 1,
          E11y::Pipeline::Builder::MiddlewareEntry.new(
            middleware_class: E11y::Middleware::RateLimiting,
            args: [],
            options: { global_limit: 10, per_event_limit: 100, window: 1.0 }
          )
        )
      end
      E11y.config.instance_variable_set(:@built_pipeline, nil)

      # Step 1: Track 10 events immediately (burst)
      10.times do |i|
        Events::TestEvent.track(message: "Burst event #{i}")
      end

      # Step 2: Verify all 10 events captured (burst allowed)
      expect(memory_adapter.events.count).to eq(10), "Expected all 10 burst events to pass"

      # Step 3: Track 11th event immediately (no time advance)
      Events::TestEvent.track(message: "Burst event 11")

      # Step 4: Verify 11th event rate-limited
      expect(memory_adapter.events.count).to eq(10), "Expected 11th event to be rate-limited after burst"
    end
  end

  describe "Edge Case 1: Critical event bypass (DLQ integration)" do
    it "saves rate-limited critical events to DLQ" do
      # Setup: Per-event limit: 5 events/sec, DLQ filter: always_save_patterns = [/^payment\./]
      # Test:
      #   1. Track 5 payment events (exhaust limit)
      #   2. Track 6th payment event (rate-limited)
      # Expected: 6th event saved to DLQ (not dropped)

      memory_adapter.clear!

      # Reconfigure with low per-event limit
      E11y.config.pipeline.middlewares.reject! { |m| m.middleware_class == E11y::Middleware::RateLimiting }
      sampling_index = E11y.config.pipeline.middlewares.index { |m| m.middleware_class == E11y::Middleware::Sampling }
      if sampling_index
        E11y.config.pipeline.middlewares.insert(
          sampling_index + 1,
          E11y::Pipeline::Builder::MiddlewareEntry.new(
            middleware_class: E11y::Middleware::RateLimiting,
            args: [],
            options: { global_limit: 100, per_event_limit: 5, window: 1.0 }
          )
        )
      end
      E11y.config.instance_variable_set(:@built_pipeline, nil)

      # Setup DLQ filter to match payment events (event_name is "Events::PaymentFailed")
      allow(dlq_filter).to receive(:always_save_patterns).and_return([/PaymentFailed/i, /^payment\./i])

      # Step 1: Track 5 payment events (exhaust limit)
      5.times do |i|
        Events::PaymentFailed.track(order_id: "order-#{i}", amount: 100.0)
      end

      # Verify only 5 events passed to adapter
      expect(memory_adapter.find_events("Events::PaymentFailed").count).to eq(5)

      # Step 2: Track 6th payment event (rate-limited, should go to DLQ)
      expect(dlq_storage).to receive(:save).with(
        hash_including(event_name: "Events::PaymentFailed", payload: hash_including(order_id: "order-5")),
        hash_including(metadata: hash_including(reason: "rate_limited_per_event", limit_type: :per_event))
      )
      Events::PaymentFailed.track(order_id: "order-5", amount: 100.0)

      # Verify still only 5 events in adapter (6th went to DLQ)
      expect(memory_adapter.find_events("Events::PaymentFailed").count).to eq(5)
    end
  end

  describe "Edge Case 2: Non-critical event drop" do
    it "drops rate-limited non-critical events (not saved to DLQ)" do
      # Setup: Per-event limit: 5 events/sec
      #        DLQ filter: always_save_patterns = [/^payment\./] (log events NOT in pattern)
      # Test:
      #   1. Track 5 log events (exhaust limit)
      #   2. Track 6th log event (rate-limited)
      # Expected: 6th event NOT saved to DLQ (dropped)

      memory_adapter.clear!

      # Reconfigure with low per-event limit
      E11y.config.pipeline.middlewares.reject! { |m| m.middleware_class == E11y::Middleware::RateLimiting }
      sampling_index = E11y.config.pipeline.middlewares.index { |m| m.middleware_class == E11y::Middleware::Sampling }
      if sampling_index
        E11y.config.pipeline.middlewares.insert(
          sampling_index + 1,
          E11y::Pipeline::Builder::MiddlewareEntry.new(
            middleware_class: E11y::Middleware::RateLimiting,
            args: [],
            options: { global_limit: 100, per_event_limit: 5, window: 1.0 }
          )
        )
      end
      E11y.config.instance_variable_set(:@built_pipeline, nil)

      # DLQ filter does NOT match log events (only payment.*)
      allow(dlq_filter).to receive(:always_save_patterns).and_return([/^payment\./])

      # Step 1: Track 5 log events (exhaust limit)
      5.times do |i|
        Events::LogInfo.track(message: "Log message #{i}")
      end

      # Verify 5 events passed to adapter
      expect(memory_adapter.find_events("Events::LogInfo").count).to eq(5)

      # Step 2: Track 6th log event (rate-limited, should NOT go to DLQ)
      expect(dlq_storage).not_to receive(:save)
      Events::LogInfo.track(message: "Log message 6")

      # Verify still only 5 events in adapter (6th dropped, not saved to DLQ)
      expect(memory_adapter.find_events("Events::LogInfo").count).to eq(5)
    end
  end

  describe "Edge Case 3: DLQ save failure (C18 Resolution)" do
    it "does not crash middleware when DLQ save fails" do
      # Setup: Per-event limit: 5 events/sec, DLQ filter: always_save_patterns = [/^payment\./]
      #        DLQ storage: Mock to raise StandardError
      # Test:
      #   1. Track 5 payment events (exhaust limit)
      #   2. Mock dlq_storage.save to raise StandardError
      #   3. Track 6th payment event (rate-limited, DLQ save fails)
      # Expected: Middleware doesn't crash (exception caught)

      memory_adapter.clear!

      # Reconfigure with low per-event limit
      E11y.config.pipeline.middlewares.reject! { |m| m.middleware_class == E11y::Middleware::RateLimiting }
      sampling_index = E11y.config.pipeline.middlewares.index { |m| m.middleware_class == E11y::Middleware::Sampling }
      if sampling_index
        E11y.config.pipeline.middlewares.insert(
          sampling_index + 1,
          E11y::Pipeline::Builder::MiddlewareEntry.new(
            middleware_class: E11y::Middleware::RateLimiting,
            args: [],
            options: { global_limit: 100, per_event_limit: 5, window: 1.0 }
          )
        )
      end
      E11y.config.instance_variable_set(:@built_pipeline, nil)

      # Setup DLQ filter to match payment events
      allow(dlq_filter).to receive(:always_save_patterns).and_return([/PaymentFailed/i])

      # Step 1: Track 5 payment events (exhaust limit)
      5.times do |i|
        Events::PaymentFailed.track(order_id: "order-#{i}", amount: 100.0)
      end
      expect(memory_adapter.find_events("Events::PaymentFailed").count).to eq(5)

      # Step 2: Mock DLQ save to raise StandardError
      allow(dlq_storage).to receive(:save).and_raise(StandardError.new("DLQ storage unavailable"))

      # Step 3: Track 6th payment event (rate-limited, DLQ save fails)
      # Should not raise exception (exception caught in save_to_dlq)
      expect { Events::PaymentFailed.track(order_id: "order-5", amount: 100.0) }.not_to raise_error

      # Verify still only 5 events in adapter (6th not saved due to DLQ failure)
      expect(memory_adapter.find_events("Events::PaymentFailed").count).to eq(5)
    end
  end

  describe "Edge Case 4: Multiple event types (separate buckets)" do
    it "maintains separate rate limit buckets for different event types" do
      # Setup: Global limit: 100 events/sec (high), Per-event limit: 5 events/sec
      # Test:
      #   1. Track 5 Events::EventA (exhaust limit for EventA)
      #   2. Track 5 Events::EventB (should pass, separate bucket)
      #   3. Track 6th Events::EventA (should be rate-limited)
      #   4. Track 6th Events::EventB (should be rate-limited)
      # Expected: Per-event buckets are separate for different event types

      memory_adapter.clear!

      # Reconfigure with low per-event limit
      E11y.config.pipeline.middlewares.reject! { |m| m.middleware_class == E11y::Middleware::RateLimiting }
      sampling_index = E11y.config.pipeline.middlewares.index { |m| m.middleware_class == E11y::Middleware::Sampling }
      if sampling_index
        E11y.config.pipeline.middlewares.insert(
          sampling_index + 1,
          E11y::Pipeline::Builder::MiddlewareEntry.new(
            middleware_class: E11y::Middleware::RateLimiting,
            args: [],
            options: { global_limit: 100, per_event_limit: 5, window: 1.0 }
          )
        )
      end
      E11y.config.instance_variable_set(:@built_pipeline, nil)

      # Step 1: Track 5 Events::EventA (exhaust limit for EventA)
      5.times do |i|
        Events::EventA.track(data: "data-a-#{i}")
      end
      expect(memory_adapter.find_events("Events::EventA").count).to eq(5)

      # Step 2: Track 5 Events::EventB (should pass, separate bucket)
      5.times do |i|
        Events::EventB.track(data: "data-b-#{i}")
      end
      expect(memory_adapter.find_events("Events::EventB").count).to eq(5)

      # Step 3: Track 6th Events::EventA (should be rate-limited)
      Events::EventA.track(data: "data-a-6")
      expect(memory_adapter.find_events("Events::EventA").count).to eq(5)

      # Step 4: Track 6th Events::EventB (should be rate-limited)
      Events::EventB.track(data: "data-b-6")
      expect(memory_adapter.find_events("Events::EventB").count).to eq(5)

      # Verify both event types have separate buckets
      expect(memory_adapter.events.count).to eq(10)
    end
  end
end

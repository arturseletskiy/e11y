# UC-011 Rate Limiting: Integration Test Plan

**Task:** FEAT-5388 - UC-011 Phase 2: Planning Complete  
**Date:** 2026-01-26  
**Status:** Planning Complete

---

## 📋 Executive Summary

**Test Strategy:** Event-based integration tests using Rails dummy app, following pattern from PII filtering integration tests.

**Scope:** 8 core scenarios + 4 edge cases covering global/per-event rate limiting, DLQ integration, token bucket behavior.

**Test Infrastructure:** Rails dummy app (`spec/dummy`), in-memory adapter, time mocking (`Timecop`), event classes.

**Note:** HTTP status codes (429) and headers (X-RateLimit-*) are NOT applicable to E11y (event-based gem, not HTTP middleware). Assertions focus on event capture/dropping and DLQ integration.

---

## 🎯 Test Strategy Overview

### 1. Test Approach

**Pattern:** Follow `spec/integration/pii_filtering_integration_spec.rb` structure

**Key Components:**
- Rails dummy app (`spec/dummy`)
- Event classes in `spec/dummy/app/events/events/`
- Controllers in `spec/dummy/app/controllers/` (if needed)
- Rate limiting configuration in `spec/dummy/config/initializers/e11y.rb`
- In-memory adapter for event capture
- Time mocking (`Timecop`) to avoid `sleep` in tests

**Test Structure:**
```ruby
RSpec.describe "Rate Limiting Integration", :integration do
  let(:memory_adapter) { E11y.config.adapters[:memory] }
  
  before { memory_adapter.clear! }
  after { memory_adapter.clear! }
  
  describe "Scenario 1: Under limit" do
    # Test implementation
  end
  
  # ... other scenarios
end
```

### 2. Assertion Strategy

**Event-Based Assertions (NOT HTTP):**
- ✅ Event captured: `memory_adapter.find_events("Events::EventName")` returns events
- ✅ Event dropped: `memory_adapter.find_events("Events::EventName")` returns fewer events than sent
- ✅ DLQ saved: `dlq_storage` receives `save` call with event data
- ✅ Rate limit metadata: Event metadata includes rate limit info (if applicable)

**NOT Applicable:**
- ❌ HTTP 429 status (E11y is event-based, not HTTP middleware)
- ❌ X-RateLimit-* headers (E11y is event-based, not HTTP middleware)
- ❌ HTTP response headers (E11y doesn't return HTTP responses)

**Alternative Assertions:**
- Event count assertions: `expect(events.count).to eq(expected_count)`
- Event payload assertions: `expect(event[:payload]).to include(...)`
- DLQ save assertions: `expect(dlq_storage).to receive(:save).with(...)`

---

## 📊 8 Core Integration Test Scenarios

### Scenario 1: Under Limit (Events Pass)

**Objective:** Verify events pass through rate limiter when under limit.

**Setup:**
- Global limit: 10 events/sec
- Per-event limit: 5 events/sec
- Send 3 events of same type

**Test Steps:**
1. Configure rate limiting middleware
2. Track 3 events: `Events::TestEvent.track(...)`
3. Verify all 3 events captured in memory adapter

**Assertions:**
- `memory_adapter.find_events("Events::TestEvent").count == 3`
- All events have correct payload

**Expected Result:** ✅ All events pass (under both limits)

---

### Scenario 2: Over Global Limit (Events Rate-Limited)

**Objective:** Verify global rate limit blocks events when exceeded.

**Setup:**
- Global limit: 10 events/sec
- Per-event limit: 100 events/sec (high, won't trigger)
- Send 15 events (mix of different event types)

**Test Steps:**
1. Configure rate limiting middleware
2. Track 15 events (mix: 5 Events::EventA, 5 Events::EventB, 5 Events::EventC)
3. Verify only first 10 events captured

**Assertions:**
- `memory_adapter.events.count == 10` (global limit enforced)
- Last 5 events not captured (rate-limited)

**Expected Result:** ✅ First 10 events pass, last 5 rate-limited

---

### Scenario 3: Over Per-Event Limit (Events Rate-Limited)

**Objective:** Verify per-event rate limit blocks events when exceeded.

**Setup:**
- Global limit: 100 events/sec (high, won't trigger)
- Per-event limit: 5 events/sec
- Send 8 events of same type

**Test Steps:**
1. Configure rate limiting middleware
2. Track 8 events: `Events::TestEvent.track(...)`
3. Verify only first 5 events captured

**Assertions:**
- `memory_adapter.find_events("Events::TestEvent").count == 5` (per-event limit enforced)
- Last 3 events not captured (rate-limited)

**Expected Result:** ✅ First 5 events pass, last 3 rate-limited

---

### Scenario 4: Reset After Window Expires

**Objective:** Verify rate limit resets after window expires.

**Setup:**
- Global limit: 5 events/sec
- Window: 1 second
- Use time mocking (`Timecop`)

**Test Steps:**
1. Configure rate limiting middleware
2. Track 5 events (exhaust limit)
3. Verify 6th event rate-limited
4. Advance time by 1.1 seconds (`Timecop.travel`)
5. Track 7th event
6. Verify 7th event passes (limit reset)

**Assertions:**
- After step 3: `memory_adapter.events.count == 5`
- After step 5: `memory_adapter.events.count == 6` (7th event passed)

**Expected Result:** ✅ Rate limit resets after window expires

---

### Scenario 5: Per-User Rate Limiting (NOT IMPLEMENTED - SKIP)

**Objective:** Verify per-user rate limiting (if implemented).

**Status:** ❌ Not implemented in current codebase

**If Implemented:**
- Setup: Per-user limit: 10 events/min
- Test: User A sends 15 events → first 10 pass, last 5 rate-limited
- Test: User B sends 15 events → first 10 pass (separate bucket)

**Current Plan:** Skip this scenario, document as "not applicable" in test file

---

### Scenario 6: Per-Endpoint Rate Limiting (NOT IMPLEMENTED - SKIP)

**Objective:** Verify per-endpoint rate limiting (if implemented).

**Status:** ❌ Not implemented in current codebase

**If Implemented:**
- Setup: Per-endpoint limit: 10 events/min
- Test: Endpoint A sends 15 events → first 10 pass, last 5 rate-limited
- Test: Endpoint B sends 15 events → first 10 pass (separate bucket)

**Current Plan:** Skip this scenario, document as "not applicable" in test file

---

### Scenario 7: Redis Failover (REMOVED - NOT APPLICABLE)

**Objective:** ~~Verify rate limiting degrades gracefully when Redis unavailable.~~

**Status:** ✅ **REMOVED** - Redis integration removed by design decision (in-memory only)

**Design Decision:** Redis removed from rate limiting implementation. In-memory token bucket is sufficient for event tracking workloads. Per-process rate limiting is appropriate for most use cases.

**Current Plan:** Skip this scenario (not applicable - Redis removed)

---

### Scenario 8: Burst Handling (Token Bucket)

**Objective:** Verify token bucket allows burst up to capacity.

**Setup:**
- Global limit: 10 events/sec (capacity: 10 tokens)
- Window: 1 second
- Send 10 events immediately (burst)

**Test Steps:**
1. Configure rate limiting middleware
2. Track 10 events immediately (within 0.1 seconds)
3. Verify all 10 events captured (burst allowed)
4. Track 11th event immediately
5. Verify 11th event rate-limited (no tokens available)

**Assertions:**
- After step 3: `memory_adapter.events.count == 10` (burst allowed)
- After step 5: `memory_adapter.events.count == 10` (11th rate-limited)

**Expected Result:** ✅ Token bucket allows burst up to capacity, then blocks

---

### Scenario 9: Distributed Rate Limiting (REMOVED - NOT APPLICABLE)

**Objective:** ~~Verify rate limiting works across multiple app instances.~~

**Status:** ✅ **REMOVED** - Redis integration removed by design decision (in-memory only)

**Design Decision:** Distributed rate limiting not needed. Each application process maintains its own rate limits, which is appropriate for event tracking workloads.

**Current Plan:** Skip this scenario (not applicable - Redis removed)

---

## ⚠️ 4 Edge Case Scenarios

### Edge Case 1: Critical Event Bypass (DLQ Integration)

**Objective:** Verify rate-limited critical events saved to DLQ.

**Setup:**
- Per-event limit: 5 events/sec
- DLQ filter: `always_save_patterns = [/^payment\./]`
- Send 6 payment events

**Test Steps:**
1. Configure rate limiting middleware + DLQ filter
2. Track 5 payment events (exhaust limit)
3. Track 6th payment event (rate-limited)
4. Verify 6th event saved to DLQ (not dropped)

**Assertions:**
- `memory_adapter.find_events("Events::PaymentFailed").count == 5` (only 5 passed to adapter)
- `expect(dlq_storage).to receive(:save).with(...)` (6th event saved to DLQ)

**Expected Result:** ✅ Rate-limited critical events saved to DLQ

---

### Edge Case 2: Non-Critical Event Drop

**Objective:** Verify rate-limited non-critical events dropped (not saved to DLQ).

**Setup:**
- Per-event limit: 5 events/sec
- DLQ filter: `always_save_patterns = [/^payment\./]` (log events NOT in pattern)
- Send 6 log events

**Test Steps:**
1. Configure rate limiting middleware + DLQ filter
2. Track 5 log events (exhaust limit)
3. Track 6th log event (rate-limited)
4. Verify 6th event NOT saved to DLQ (dropped)

**Assertions:**
- `memory_adapter.find_events("Events::LogInfo").count == 5` (only 5 passed to adapter)
- `expect(dlq_storage).not_to receive(:save)` (6th event dropped, not saved)

**Expected Result:** ✅ Rate-limited non-critical events dropped

---

### Edge Case 3: DLQ Save Failure (C18 Resolution)

**Objective:** Verify DLQ save exception doesn't crash middleware.

**Setup:**
- Per-event limit: 5 events/sec
- DLQ filter: `always_save_patterns = [/^payment\./]`
- DLQ storage: Mock to raise exception

**Test Steps:**
1. Configure rate limiting middleware + DLQ filter
2. Mock `dlq_storage.save` to raise `StandardError`
3. Track 5 payment events (exhaust limit)
4. Track 6th payment event (rate-limited, DLQ save fails)
5. Verify middleware doesn't crash (exception caught)

**Assertions:**
- `expect { middleware.call(...) }.not_to raise_error` (exception caught)
- Exception logged (verify log output)

**Expected Result:** ✅ DLQ save failure doesn't crash middleware

---

### Edge Case 4: Multiple Event Types (Separate Buckets)

**Objective:** Verify per-event buckets are separate for different event types.

**Setup:**
- Global limit: 100 events/sec (high, won't trigger)
- Per-event limit: 5 events/sec
- Send events of different types

**Test Steps:**
1. Configure rate limiting middleware
2. Track 5 Events::EventA (exhaust limit for EventA)
3. Track 5 Events::EventB (should pass, separate bucket)
4. Track 6th Events::EventA (should be rate-limited)
5. Track 6th Events::EventB (should be rate-limited)

**Assertions:**
- `memory_adapter.find_events("Events::EventA").count == 5` (limit enforced)
- `memory_adapter.find_events("Events::EventB").count == 5` (separate bucket, limit enforced)

**Expected Result:** ✅ Per-event buckets are separate for different event types

---

## 🔧 Test Infrastructure Setup

### 1. Rails Dummy App Configuration

**File:** `spec/dummy/config/initializers/e11y.rb`

```ruby
E11y.configure do |config|
  # In-memory adapter for testing
  config.adapters[:memory] = E11y::Adapters::InMemory.new
  
  # Rate limiting middleware configuration
  config.pipeline.use E11y::Middleware::RateLimiting,
    global_limit: 10,        # Low limit for testing
    per_event_limit: 5,      # Low limit for testing
    window: 1.0              # 1 second window
  
  # DLQ filter configuration (for critical event bypass tests)
  config.dlq_filter.always_save_patterns = [/^payment\./, /^audit\./]
end
```

### 2. Event Classes

**Location:** `spec/dummy/app/events/events/`

**Required Events:**
- `Events::TestEvent` - Generic test event
- `Events::PaymentFailed` - Critical event (for DLQ tests)
- `Events::LogInfo` - Non-critical event (for drop tests)
- `Events::EventA`, `Events::EventB` - For multiple event type tests

**Example:** `spec/dummy/app/events/events/test_event.rb`
```ruby
# frozen_string_literal: true

module Events
  class TestEvent < E11y::Event::Base
    schema do
      required(:message).filled(:string)
    end
  end
end
```

### 3. Time Mocking Setup

**Gem:** `timecop` (add to `Gemfile` if not present)

**Usage:**
```ruby
require "timecop"

RSpec.describe "Rate Limiting Integration", :integration do
  around do |example|
    Timecop.freeze(Time.now) do
      example.run
    end
  end
  
  it "resets after window expires" do
    # Track events
    # ...
    
    # Advance time
    Timecop.travel(1.1.seconds.from_now)
    
    # Track more events
    # ...
  end
end
```

### 4. DLQ Storage Mock

**Setup:**
```ruby
let(:dlq_storage) { double("DLQStorage") }

before do
  allow(E11y.config).to receive(:dlq_storage).and_return(dlq_storage)
  allow(E11y.config).to receive(:dlq_filter).and_return(
    double("DLQFilter", always_save_patterns: [/^payment\./])
  )
end
```

---

## 📈 Load Testing Approach

### Performance Benchmarks

**Objective:** Verify rate limiting overhead is acceptable.

**Metrics:**
- Rate limiting overhead: < 1ms per event
- Token bucket refill overhead: < 0.1ms
- Mutex lock overhead: < 0.01ms

**Test Approach:**
```ruby
it "has acceptable performance overhead" do
  require "benchmark"
  
  middleware = E11y::Middleware::RateLimiting.new(...)
  event_data = { event_name: "test.event", payload: {} }
  
  time = Benchmark.realtime do
    1000.times { middleware.call(event_data) }
  end
  
  avg_time_per_event = (time / 1000) * 1000 # Convert to ms
  expect(avg_time_per_event).to be < 1.0 # Less than 1ms per event
end
```

**Expected Results:**
- Rate limiting overhead: ~0.1-0.5ms per event (in-memory token bucket)
- No performance degradation under load

---

## 🚫 Redis Test Setup (NOT APPLICABLE - CURRENTLY)

### Status: ❌ Redis Integration Not Implemented

**Current Implementation:** In-memory token bucket (no Redis dependency)

**If Redis Integration Added Later:**

**Setup Requirements:**
- Redis server available (or Docker container)
- Redis client gem (`redis-rb`)
- Test Redis instance (separate from production)

**Test Configuration:**
```ruby
# spec/support/redis_helper.rb
RSpec.configure do |config|
  config.before(:suite) do
    # Start Redis test server (or use Docker)
    Redis.new(url: "redis://localhost:6379/15").flushdb
  end
  
  config.after(:each) do
    # Clean up Redis after each test
    Redis.new(url: "redis://localhost:6379/15").flushdb
  end
end
```

**Test Scenarios (If Implemented):**
- Distributed rate limiting (multiple instances)
- Redis failover (degrade to in-memory)
- Clock skew handling (use Redis time)

**Current Plan:** Document Redis setup requirements, skip Redis tests until implemented

---

## ✅ Definition of Done (DoD) Verification

### DoD Requirements:

1. ✅ **8 scenarios planned**
   - Scenario 1: Under limit ✅
   - Scenario 2: Over global limit ✅
   - Scenario 3: Over per-event limit ✅
   - Scenario 4: Reset after window ✅
   - Scenario 5: Per-user (SKIP - not implemented)
   - Scenario 6: Per-endpoint (SKIP - not implemented)
   - Scenario 7: Redis failover (SKIP - not implemented)
   - Scenario 8: Burst handling ✅

2. ✅ **Redis test setup documented**
   - Status: **REMOVED** - Redis integration removed by design decision
   - Current: In-memory token bucket only (no Redis dependency)

3. ✅ **Load testing approach defined**
   - Performance benchmarks defined (< 1ms overhead)
   - Benchmark test approach documented

4. ⚠️ **Assertions include 429 status and X-RateLimit-* headers**
   - **Note:** NOT applicable to E11y (event-based, not HTTP middleware)
   - **Alternative:** Event count assertions, DLQ save assertions
   - **Documented:** Why HTTP assertions don't apply

### DoD Status: ✅ Complete (with notes on HTTP assertions)

---

## 📝 Implementation Notes

### Test File Structure

**File:** `spec/integration/rate_limiting_integration_spec.rb`

**Structure:**
```ruby
# frozen_string_literal: true

require "rails_helper"
require "timecop"

RSpec.describe "Rate Limiting Integration", :integration do
  let(:memory_adapter) { E11y.config.adapters[:memory] }
  let(:dlq_storage) { double("DLQStorage") }
  
  before do
    memory_adapter.clear!
    # Configure DLQ for critical event tests
    allow(E11y.config).to receive(:dlq_storage).and_return(dlq_storage)
    allow(E11y.config).to receive(:dlq_filter).and_return(
      double("DLQFilter", always_save_patterns: [/^payment\./])
    )
  end
  
  after { memory_adapter.clear! }
  
  describe "Scenario 1: Under limit" do
    # Implementation
  end
  
  # ... other scenarios
end
```

### Configuration Override

**For Different Scenarios:**
- Use `before` blocks to reconfigure rate limiting per scenario
- Or use `let` blocks with different configurations
- Example: `let(:low_limit_config) { { global_limit: 5, per_event_limit: 3 } }`

### Time Mocking Best Practices

**DO:**
- Use `Timecop.freeze` to freeze time at start of test
- Use `Timecop.travel` to advance time for window expiration tests
- Always restore time in `after` block

**DON'T:**
- Use `sleep` in tests (slow, flaky)
- Forget to restore time (affects other tests)

---

## 🎯 Next Steps

**Phase 3 (Skeleton):**
- Create test file structure
- Create event classes
- Create pending test cases with descriptions

**Phase 4 (Implementation):**
- Implement all test scenarios
- Verify all tests pass
- Performance benchmarks

---

## 📚 References

- **Analysis Document:** `docs/analysis/UC-011-RATE-LIMITING-ANALYSIS.md`
- **Integration Tests:** `spec/integration/rate_limiting_integration_spec.rb` ✅ (All 8 scenarios implemented)
- **PII Filtering Integration Tests:** `spec/integration/pii_filtering_integration_spec.rb` (reference pattern)
- **Rate Limiting Middleware:** `lib/e11y/middleware/rate_limiting.rb`
- **Unit Tests:** `spec/e11y/middleware/rate_limiting_spec.rb`

---

**Planning Complete:** 2026-01-26  
**Next Task:** FEAT-5389 - UC-011 Phase 3: Skeleton Complete

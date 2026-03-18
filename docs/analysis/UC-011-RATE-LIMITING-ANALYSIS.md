# UC-011 Rate Limiting: Integration Test Analysis

**Task:** FEAT-5387 - UC-011 Phase 1: Analysis Complete  
**Date:** 2026-01-26  
**Status:** Analysis Complete

---

## 📋 Executive Summary

**Current State:**
- ✅ **Implemented:** Global + per-event rate limiting with in-memory token bucket
- ❌ **Not Implemented:** Per-context rate limiting (user_id, ip_address, tenant_id)
- ✅ **Design Decision:** In-memory token bucket (Redis removed - user feedback: "устаревшее решение")
- ✅ **Implemented:** DLQ integration for critical events (C02 Resolution)

**Unit Test Coverage:** Good (52 test cases covering global/per-event limits, token bucket, DLQ integration)

**Integration Test Coverage:** ✅ **COMPLETE** - All 8 scenarios implemented in `spec/integration/rate_limiting_integration_spec.rb`

**Integration Test Status:**
1. ✅ Under limit (events pass) - Scenario 1 implemented
2. ✅ Over global limit (events rate-limited) - Scenario 2 implemented
3. ✅ Over per-event limit (events rate-limited) - Scenario 3 implemented
4. ✅ Reset after window expires - Scenario 4 implemented
5. ⚠️ Per-user rate limiting (SKIP - not implemented) - Scenario 5 skipped as expected
6. ⚠️ Per-endpoint rate limiting (SKIP - not implemented) - Scenario 6 skipped as expected
7. ⚠️ Redis failover (REMOVED - Redis integration removed by design decision) - Scenario 7 removed as expected
8. ✅ Burst handling (token bucket) - Scenario 8 implemented

**Test File:** `spec/integration/rate_limiting_integration_spec.rb` (518 lines)
**Test Scenarios:** All applicable scenarios from planning document are implemented and passing

---

## 🔍 1. Current Implementation Analysis

### 1.1. Code Structure

**Location:** `lib/e11y/middleware/rate_limiting.rb`

**Key Components:**
- `E11y::Middleware::RateLimiting` - Main middleware class
- `TokenBucket` - In-memory token bucket implementation
- Global bucket: `@global_bucket` (default: 10,000 events/sec)
- Per-event buckets: `@per_event_buckets` (Hash, lazy initialization, default: 1,000 events/sec)

**Algorithm:** Token bucket (smooth refill, allows burst up to capacity)

**Thread Safety:** Mutex-protected (`@mutex`)

### 1.2. Current Features

| Feature | Status | Implementation |
|---------|--------|----------------|
| Global rate limiting | ✅ Implemented | `@global_bucket` (token bucket) |
| Per-event rate limiting | ✅ Implemented | `@per_event_buckets` (Hash of token buckets) |
| Per-context rate limiting | ❌ Not Implemented | Described in UC-011 but missing from code |
| Redis integration | ✅ Removed | Design decision: in-memory only (no Redis dependency) |
| DLQ integration (C02) | ✅ Implemented | `should_save_to_dlq?()` + `save_to_dlq()` |
| Token bucket refill | ✅ Implemented | Time-based refill (`refill_tokens`) |
| Thread safety | ✅ Implemented | Mutex synchronization |

### 1.3. Configuration

**Current API:**
```ruby
E11y.configure do |config|
  config.pipeline.use E11y::Middleware::RateLimiting,
    global_limit: 10_000,        # Max 10K events/sec globally
    per_event_limit: 1_000,      # Max 1K events/sec per event type
    window: 1.0                  # 1 second window
end
```

**UC-011 Desired API (NOT IMPLEMENTED):**
```ruby
E11y.configure do |config|
  config.rate_limiting do
    global limit: 10_000, window: 1.minute
    per_event 'payment.retry', limit: 100, window: 1.minute
    per_context :user_id, limit: 1_000, window: 1.minute
    per_context :ip_address, limit: 500, window: 1.minute
    on_exceeded :sample
    sample_rate 0.1
  end
end
```

**Gap:** Current implementation uses middleware initialization parameters, not DSL configuration.

---

## 📊 2. Unit Test Coverage Analysis

### 2.1. Test File: `spec/e11y/middleware/rate_limiting_spec.rb`

**Coverage Summary:**
- ✅ **52 test cases** covering:
  - Initialization (global_limit, per_event_limit, window, token buckets)
  - Global rate limiting (within limit, exceeded, logging)
  - Per-event rate limiting (within limit, exceeded, separate buckets per event type, logging)
  - Token refill mechanism (time-based refill after window)
  - C02 Resolution (critical events bypass → DLQ, non-critical events dropped, DLQ save failures)
  - TokenBucket class (allow?, tokens, refill, capacity limits)
  - UC-011 compliance (DoS protection, token bucket algorithm)

**Coverage Gaps:**
- ❌ No tests for per-context rate limiting (not implemented)
- ❌ No tests for Redis integration (not implemented)
- ❌ No tests for distributed rate limiting scenarios
- ❌ No tests for clock skew handling
- ❌ No tests for burst handling edge cases
- ❌ No tests for reset behavior (window reset)
- ❌ No tests for failover scenarios (Redis down)

### 2.2. Test Quality Assessment

**Strengths:**
- Comprehensive unit test coverage for implemented features
- Good edge case coverage (DLQ save failures, empty configs)
- Clear test organization (describe blocks for each feature)

**Weaknesses:**
- Tests use `sleep` for time-based scenarios (slow, flaky)
- No integration with real Rails application
- No tests for middleware pipeline integration
- No tests for Event.track() → middleware → adapter flow

---

## 🎯 3. Real-World Usage Patterns Analysis

### 3.1. Expected Usage Scenarios

**Scenario 1: Payment Retry Storm (UC-011 Primary Use Case)**
```ruby
# Production incident: Payment gateway down
1000.times do |i|
  Events::PaymentRetry.track(order_id: "order-#{i}", attempt: 1)
end
# Expected: First 100 events pass (per-event limit), rest rate-limited
```

**Scenario 2: Global Rate Limit Protection**
```ruby
# High-volume application: Multiple event types
10_000.times do |i|
  Events::PageView.track(page: "/products/#{i}")
end
# Expected: First 10,000 events pass (global limit), rest rate-limited
```

**Scenario 3: Per-User Abuse Prevention (NOT IMPLEMENTED)**
```ruby
# Single user flooding system
user_id = "user-123"
1_000.times do |i|
  Events::ApiRequest.track(user_id: user_id, endpoint: "/api/v1/data")
end
# Expected: First 1,000 events pass (per-context limit), rest rate-limited
# Current: ALL events pass (per-context not implemented)
```

**Scenario 4: Critical Event Bypass (C02 Resolution)**
```ruby
# Rate-limited critical event → DLQ
5.times { Events::PaymentFailed.track(order_id: "order-1", amount: 100) }
# 6th event: Rate-limited but saved to DLQ (critical event)
Events::PaymentFailed.track(order_id: "order-2", amount: 200)
# Expected: Event saved to DLQ, not dropped
```

### 3.2. Integration Test Scenarios Needed

Based on UC-011 requirements and real-world patterns, integration tests should cover:

1. **Under Limit:** Events pass through rate limiter successfully
2. **Over Limit:** Events rate-limited (return nil, saved to DLQ if critical)
3. **Reset:** Rate limit resets after window expires
4. **Per-User:** Different users have separate rate limits (if implemented)
5. **Per-Endpoint:** Different endpoints have separate rate limits (if implemented)
6. **Redis Failover:** Rate limiting degrades gracefully when Redis unavailable (if implemented)
7. **Burst:** Token bucket allows burst up to capacity, then smooth rate limiting
8. **Distributed:** Rate limiting works across multiple app instances (if implemented)

---

## ⚠️ 4. Edge Cases Analysis

### 4.1. Time-Based Edge Cases

**Clock Skew (Distributed Systems):**
- **Problem:** Multiple app instances with different system clocks
- **Impact:** Rate limiting may be inconsistent across instances
- **Current State:** Not applicable (in-memory, single instance)
- **If Redis Added:** Need clock skew handling strategy (e.g., use Redis time, not local time)

**Window Boundary:**
- **Problem:** Events at window boundary may be counted incorrectly
- **Current State:** Token bucket refills continuously (no fixed window boundaries)
- **Risk:** Low (token bucket avoids fixed window edge cases)

**Time Travel (Testing):**
- **Problem:** Tests using `sleep` are slow and flaky
- **Current State:** Unit tests use `sleep 1.1` for refill testing
- **Solution:** Use time mocking in integration tests (`Timecop` or similar)

### 4.2. Concurrency Edge Cases

**Race Conditions:**
- **Problem:** Multiple threads checking rate limit simultaneously
- **Current State:** Mutex-protected (`@mutex.synchronize`)
- **Risk:** Low (thread-safe implementation)

**Token Bucket Overflow:**
- **Problem:** Tokens exceed capacity after refill
- **Current State:** Capped at capacity (`[@tokens + tokens_to_add, @capacity].min`)
- **Risk:** None (handled correctly)

### 4.3. Configuration Edge Cases

**Zero Limits:**
- **Problem:** `global_limit: 0` or `per_event_limit: 0`
- **Current State:** No validation (would allow 0, blocking all events)
- **Risk:** Medium (should validate positive integers)

**Negative Limits:**
- **Problem:** `global_limit: -100`
- **Current State:** No validation (would cause incorrect behavior)
- **Risk:** Medium (should validate positive integers)

**Missing Event Name:**
- **Problem:** `event_data[:event_name]` is nil
- **Current State:** Would cause `NoMethodError` on `@per_event_buckets[nil]`
- **Risk:** Low (events always have event_name, but should validate)

### 4.4. DLQ Integration Edge Cases

**DLQ Storage Unavailable:**
- **Problem:** `dlq_storage.save()` raises exception
- **Current State:** Exception caught and logged (C18 Resolution)
- **Risk:** Low (handled correctly)

**DLQ Filter Not Configured:**
- **Problem:** `E11y.config.dlq_filter` is nil
- **Current State:** Returns false, event dropped (correct behavior)
- **Risk:** None (handled correctly)

**Critical Event Pattern Mismatch:**
- **Problem:** Event class doesn't have `use_dlq true` (or severity/default doesn't match)
- **Current State:** Event dropped (correct behavior for non-critical events)
- **Risk:** None (handled correctly)

---

## 🔗 5. Dependencies Analysis

### 5.1. Redis Integration Requirements

**UC-011 Requirement:** Distributed rate limiting with Redis (sliding window algorithm)

**Current State:** ❌ Not implemented (in-memory token bucket only)

**If Implemented, Requirements:**
- Redis client (e.g., `redis-rb` gem)
- Sliding window algorithm using Redis sorted sets (`ZADD`, `ZREMRANGEBYSCORE`, `ZCARD`)
- Key naming strategy: `e11y:rate_limit:global`, `e11y:rate_limit:event:{event_name}`, `e11y:rate_limit:context:{context_key}:{value}`
- TTL management (auto-expire old entries)
- Failover strategy (degrade to in-memory if Redis unavailable)

**Integration Test Requirements:**
- Redis server available (or mocked)
- Test distributed scenarios (multiple app instances)
- Test Redis failover (Redis down → degrade gracefully)
- Test clock skew handling (use Redis time, not local time)

### 5.2. Per-Context Rate Limiting Requirements

**UC-011 Requirement:** Per-user, per-IP, per-tenant rate limiting

**Current State:** ❌ Not implemented

**If Implemented, Requirements:**
- Context extraction from event payload/context
- Multiple context keys (user_id, ip_address, tenant_id, session_id)
- Separate token buckets per context value
- Allowlist support (bypass rate limiting for specific users/IPs)

**Integration Test Requirements:**
- Test context extraction (from payload, context, Rails Current)
- Test multiple users (separate limits)
- Test multiple IPs (separate limits)
- Test allowlist (bypass rate limiting)

### 5.3. Rails Integration Requirements

**Current State:** ✅ Middleware integrated in pipeline

**Integration Test Requirements:**
- Test Event.track() → middleware → adapter flow
- Test Rails request context (Current.user_id, request.remote_ip)
- Test middleware order (rate limiting before/after other middleware)
- Test configuration via Rails initializer

---

## 📈 6. Performance Considerations

### 6.1. Token Bucket Performance

**Current Implementation:**
- O(1) token check (`allow?`)
- O(1) token refill (time-based calculation)
- Mutex lock overhead (minimal for single-threaded scenarios)

**Performance Characteristics:**
- Fast: No external dependencies (in-memory)
- Scalable: Per-event buckets created on-demand (lazy initialization)
- Memory: Grows with number of unique event types (acceptable)

### 6.2. Redis Performance (If Implemented)

**Expected Performance:**
- O(log N) for sorted set operations (ZADD, ZCARD)
- Network latency (local Redis: ~1ms, remote Redis: ~10-50ms)
- Redis connection pooling (reuse connections)

**Bottlenecks:**
- Redis network latency (if remote)
- Redis memory usage (grows with number of rate limit keys)
- Redis failover (degradation to in-memory)

### 6.3. Integration Test Performance

**Current Unit Tests:**
- Slow: Uses `sleep` for time-based scenarios (1.1s per test)
- Flaky: Timing-dependent assertions

**Integration Test Strategy:**
- Use time mocking (`Timecop`) to avoid `sleep`
- Test token refill with mocked time
- Test window reset with mocked time
- Performance benchmarks: Rate limiting overhead < 1ms per event

---

## ✅ 7. Integration Test Scenarios (Proposed)

Based on analysis, integration tests should cover:

### 7.1. Basic Scenarios (8 scenarios)

1. **Under Limit:** Events pass through rate limiter
   - Global limit: 10 events/sec, send 5 events → all pass
   - Per-event limit: 5 events/sec, send 3 events → all pass

2. **Over Limit:** Events rate-limited
   - Global limit: 10 events/sec, send 15 events → first 10 pass, rest rate-limited
   - Per-event limit: 5 events/sec, send 8 events → first 5 pass, rest rate-limited

3. **Reset:** Rate limit resets after window expires
   - Exhaust limit, wait for window expiration, send event → event passes

4. **Per-User:** Different users have separate limits (if implemented)
   - User A: 10 events/min → all pass
   - User B: 10 events/min → all pass (separate bucket)

5. **Per-Endpoint:** Different endpoints have separate limits (if implemented)
   - Endpoint A: 10 events/min → all pass
   - Endpoint B: 10 events/min → all pass (separate bucket)

6. **Redis Failover:** Rate limiting degrades gracefully (if implemented)
   - Redis available: Distributed rate limiting works
   - Redis down: Degrades to in-memory rate limiting

7. **Burst:** Token bucket allows burst up to capacity
   - Capacity: 10 tokens, send 10 events immediately → all pass
   - 11th event: Rate-limited (no tokens available)

8. **Distributed:** Rate limiting works across multiple instances (if implemented)
   - Instance A: 5 events → count: 5
   - Instance B: 5 events → count: 10 (shared Redis state)
   - Instance C: 1 event → rate-limited (exceeds limit of 10)

### 7.2. Edge Case Scenarios

9. **Critical Event Bypass:** Rate-limited critical events saved to DLQ
   - Exhaust per-event limit for payment events
   - 6th payment event: Rate-limited but saved to DLQ

10. **Non-Critical Event Drop:** Rate-limited non-critical events dropped
    - Exhaust per-event limit for log events
    - 6th log event: Rate-limited and dropped (not saved to DLQ)

11. **DLQ Save Failure:** DLQ save exception doesn't crash middleware
    - Exhaust limit, DLQ save raises exception
    - Event dropped, exception caught and logged

12. **Missing Event Name:** Event without event_name handled gracefully
    - Event with `event_name: nil`
    - Should handle gracefully (validate or use default)

---

## 📝 8. Recommendations

### 8.1. Integration Test Implementation Priority

**Priority 1 (Must Have):**
1. Under limit scenario
2. Over limit scenario
3. Reset scenario
4. Critical event bypass (DLQ integration)

**Priority 2 (Should Have):**
5. Burst scenario
6. Per-user scenario (if implemented)
7. Per-endpoint scenario (if implemented)
8. DLQ save failure scenario

**Priority 3 (Nice to Have):**
9. Redis failover scenario (if implemented)
10. Distributed scenario (if implemented)
11. Clock skew handling (if implemented)

### 8.2. Implementation Notes

**Test Infrastructure:**
- Use `spec/dummy` Rails app (similar to PII filtering integration tests)
- Use `Timecop` for time mocking (avoid `sleep`)
- Use `E11y::Adapters::InMemory` for event capture
- Use `RSpec.describe "...", :integration` tag

**Test Structure:**
- Follow pattern from `spec/integration/pii_filtering_integration_spec.rb`
- Create event classes in `spec/dummy/app/events/events/`
- Create controllers in `spec/dummy/app/controllers/` (if needed)
- Configure rate limiting in `spec/dummy/config/initializers/e11y.rb`

**Performance Benchmarks:**
- Rate limiting overhead < 1ms per event
- Token bucket refill overhead < 0.1ms
- Mutex lock overhead < 0.01ms

---

## 🎯 9. Definition of Done (DoD) Verification

**DoD Requirements:**
- ✅ Analysis document with unit coverage gaps
- ✅ Redis integration requirements (if applicable)
- ✅ Distributed rate limiting patterns (if applicable)
- ✅ Clock skew handling strategy (if applicable)

**Status:**
- ✅ Unit coverage gaps identified (per-context, Redis, distributed, edge cases)
- ✅ Redis integration requirements documented (if implemented)
- ✅ Distributed rate limiting patterns documented (if implemented)
- ✅ Clock skew handling strategy documented (if implemented)

**Next Steps:**
- Proceed to Phase 2: Planning Complete (FEAT-5388)
- Create detailed integration test plan based on this analysis
- Identify which scenarios are feasible with current implementation (global + per-event)
- Identify which scenarios require new features (per-context, Redis)

---

## 📚 References

- **UC-011:** `docs/use_cases/UC-011-rate-limiting.md`
- **ADR-006:** `docs/ADR-006-security-compliance.md` (Section 4: Rate Limiting)
- **ADR-013:** `docs/ADR-013-reliability-error-handling.md` (Section 4.6: C02 Resolution)
- **Implementation:** `lib/e11y/middleware/rate_limiting.rb`
- **Unit Tests:** `spec/e11y/middleware/rate_limiting_spec.rb`
- **PII Filtering Integration Tests:** `spec/integration/pii_filtering_integration_spec.rb` (reference pattern)

---

**Analysis Complete:** 2026-01-26  
**Next Task:** FEAT-5388 - UC-011 Phase 2: Planning Complete

# UC-013 High Cardinality Protection: Integration Test Plan

**Task:** FEAT-5393 - UC-013 Phase 2: Planning Complete  
**Date:** 2026-01-26  
**Status:** Planning Complete

---

## 📋 Executive Summary

**Test Strategy:** Event-based integration tests using Rails dummy app, following pattern from rate limiting integration tests.

**Scope:** 8 core scenarios + 4 edge cases covering cardinality attack vectors, Prometheus limits, memory impact, overflow strategies.

**Test Infrastructure:** Rails dummy app (`spec/dummy`), in-memory adapter, event classes with metrics, Yabeda/Prometheus integration, cardinality protection configuration.

**Note:** Tests focus on metric label cardinality (NOT event cardinality). Assertions verify that high-cardinality labels are blocked/dropped/relabeled before reaching Prometheus.

---

## 🎯 Test Strategy Overview

### 1. Test Approach

**Pattern:** Follow `spec/integration/rate_limiting_integration_spec.rb` structure

**Key Components:**
- Rails dummy app (`spec/dummy`)
- Event classes in `spec/dummy/app/events/events/` with metric definitions
- Metrics middleware integration (Event.track() → Metrics Middleware → Cardinality Protection → Yabeda)
- Yabeda adapter for Prometheus export
- Cardinality protection configuration in test `before` blocks
- In-memory adapter for event capture (verify events tracked)
- Yabeda metrics inspection (verify metrics exported with correct cardinality)

**Test Structure:**
```ruby
RSpec.describe "High Cardinality Protection Integration", :integration do
  let(:memory_adapter) { E11y.config.adapters[:memory] }
  let(:yabeda_adapter) { E11y.config.adapters[:yabeda] }
  
  before do
    memory_adapter.clear!
    # Configure cardinality protection
    E11y.config.metrics.cardinality_protection do
      cardinality_limit 100  # Low limit for testing
      overflow_strategy :drop
    end
  end
  
  after do
    memory_adapter.clear!
    # Reset cardinality tracking
    E11y.config.metrics.cardinality_protection.reset! if E11y.config.metrics.cardinality_protection
  end
  
  describe "Scenario 1: UUID label flood" do
    # Test implementation
  end
  
  # ... other scenarios
end
```

### 2. Assertion Strategy

**Metric-Based Assertions:**
- ✅ Labels filtered: `cardinality_protection.filter(labels, metric_name)` returns filtered labels
- ✅ Cardinality tracked: `cardinality_protection.cardinality(metric_name)` returns current cardinality
- ✅ Labels dropped: High-cardinality labels not present in filtered labels
- ✅ Labels relabeled: High-cardinality values transformed (e.g., HTTP status → class)
- ✅ Prometheus export: Metrics exported to Prometheus with acceptable cardinality

**NOT Applicable:**
- ❌ HTTP status codes (E11y is event-based, not HTTP middleware)
- ❌ HTTP response headers (E11y doesn't return HTTP responses)
- ❌ Event cardinality (tests focus on metric label cardinality, not event count)

**Alternative Assertions:**
- Cardinality count assertions: `expect(protection.cardinality(metric_name)[:label_key]).to eq(expected_count)`
- Label presence assertions: `expect(filtered_labels).not_to have_key(:user_id)`
- Relabeling assertions: `expect(filtered_labels[:http_status]).to eq("2xx")`
- Prometheus format assertions: `expect(prometheus_text).to include("metric_name{label=\"value\"}")`

---

## 📊 8 Core Integration Test Scenarios

### Scenario 1: UUID Label Flood

**Objective:** Verify UUID flood attack is blocked (Layer 1: Denylist).

**Setup:**
- Event with `order_id` label (UUID in denylist)
- Send 1000 events with unique UUIDs

**Test Steps:**
1. Configure cardinality protection (default denylist)
2. Track 1000 events: `Events::OrderCreated.track(order_id: SecureRandom.uuid, status: 'paid')`
3. Verify `order_id` label dropped from all events
4. Verify only `status` label present in metrics

**Assertions:**
- `filtered_labels.keys` does NOT include `:order_id` (denylisted)
- `filtered_labels.keys` includes `:status` (allowed)
- Prometheus metrics have only `status` label (no `order_id`)

**Expected Result:** ✅ All `order_id` labels dropped, only `status` label exported

---

### Scenario 2: Unbounded Tags (Custom High-Cardinality Field)

**Objective:** Verify unbounded tag values are limited (Layer 2: Per-Metric Limits).

**Setup:**
- Event with custom high-cardinality label (NOT in denylist)
- Cardinality limit: 100 unique values
- Send 200 events with unique endpoint paths

**Test Steps:**
1. Configure cardinality protection (`cardinality_limit: 100`)
2. Track 200 events: `Events::ApiRequest.track(endpoint: "/api/users/#{i}", status: 'success')`
3. Verify first 100 unique endpoints tracked
4. Verify 101st-200th endpoints dropped (limit exceeded)

**Assertions:**
- `protection.cardinality("api_requests_total")[:endpoint] == 100` (limit reached)
- First 100 events have `endpoint` label in metrics
- 101st-200th events have `endpoint` label dropped (or relabeled to `[OTHER]`)

**Expected Result:** ✅ First 100 unique endpoints tracked, rest dropped/relabeled

---

### Scenario 3: Metric Explosion (Multiple Metrics)

**Objective:** Verify multiple metrics tracked separately (per-metric limits).

**Setup:**
- 3 different event types with metrics
- Each metric has high cardinality
- Cardinality limit: 100 per metric

**Test Steps:**
1. Configure cardinality protection (`cardinality_limit: 100`)
2. Track 150 events of each type:
   - `Events::OrderCreated.track(order_id: "order-#{i}", status: 'paid')`
   - `Events::PaymentProcessed.track(payment_id: "pay-#{i}", status: 'success')`
   - `Events::UserAction.track(user_id: "user-#{i}", action: 'click')`
3. Verify each metric tracked separately
4. Verify limits enforced per metric (not globally)

**Assertions:**
- `protection.cardinality("orders_total")[:status] == 100` (limit reached)
- `protection.cardinality("payments_total")[:status] == 100` (limit reached)
- `protection.cardinality("user_actions_total")[:action] == 100` (limit reached)
- Each metric has separate cardinality tracking

**Expected Result:** ✅ Each metric tracked separately, limits enforced per metric

---

### Scenario 4: Cardinality Limits Exceeded (Overflow Strategy: Drop)

**Objective:** Verify overflow strategy `:drop` drops labels when limit exceeded.

**Setup:**
- Cardinality limit: 10 unique values
- Overflow strategy: `:drop`
- Send 15 events with unique status values

**Test Steps:**
1. Configure cardinality protection (`cardinality_limit: 10`, `overflow_strategy: :drop`)
2. Track 15 events: `Events::OrderCreated.track(status: "status-#{i}")`
3. Verify first 10 status values tracked
4. Verify 11th-15th status values dropped (not in metrics)

**Assertions:**
- `protection.cardinality("orders_total")[:status] == 10` (limit reached)
- First 10 events have `status` label in metrics
- 11th-15th events have `status` label dropped (empty labels)

**Expected Result:** ✅ First 10 status values tracked, rest dropped

---

### Scenario 5: Cardinality Limits Exceeded (Overflow Strategy: Relabel)

**Objective:** Verify overflow strategy `:relabel` aggregates to `[OTHER]` when limit exceeded.

**Setup:**
- Cardinality limit: 10 unique values
- Overflow strategy: `:relabel`
- Send 15 events with unique status values

**Test Steps:**
1. Configure cardinality protection (`cardinality_limit: 10`, `overflow_strategy: :relabel`)
2. Track 15 events: `Events::OrderCreated.track(status: "status-#{i}")`
3. Verify first 10 status values tracked
4. Verify 11th-15th status values relabeled to `[OTHER]`

**Assertions:**
- `protection.cardinality("orders_total")[:status] == 11` (10 unique + [OTHER])
- First 10 events have original `status` label
- 11th-15th events have `status: "[OTHER]"` label

**Expected Result:** ✅ First 10 status values tracked, rest relabeled to `[OTHER]`

---

### Scenario 6: Fallback Behavior (Protection Disabled)

**Objective:** Verify fallback when cardinality protection disabled.

**Setup:**
- Cardinality protection disabled
- Send events with high-cardinality labels

**Test Steps:**
1. Configure cardinality protection (`enabled: false`)
2. Track 1000 events: `Events::OrderCreated.track(order_id: SecureRandom.uuid, status: 'paid')`
3. Verify all labels pass through (no filtering)

**Assertions:**
- `filtered_labels` includes `:order_id` (not filtered)
- All 1000 unique `order_id` values exported to Prometheus
- No cardinality limits enforced

**Expected Result:** ✅ All labels pass through when protection disabled

---

### Scenario 7: Relabeling Effectiveness (HTTP Status → Class)

**Objective:** Verify relabeling reduces cardinality while preserving signal.

**Setup:**
- Relabeling rule: HTTP status → class (`200, 201, 202` → `2xx`)
- Send events with various HTTP status codes

**Test Steps:**
1. Configure cardinality protection with relabeling:
   ```ruby
   protection.relabel(:http_status) { |v| "#{v.to_i / 100}xx" }
   ```
2. Track 100 events with various HTTP status codes:
   - `Events::ApiRequest.track(http_status: 200, endpoint: '/api/users')`
   - `Events::ApiRequest.track(http_status: 201, endpoint: '/api/users')`
   - `Events::ApiRequest.track(http_status: 202, endpoint: '/api/users')`
   - ... (various 2xx, 3xx, 4xx, 5xx codes)
3. Verify relabeled values (only 5 classes: 1xx, 2xx, 3xx, 4xx, 5xx)

**Assertions:**
- `protection.cardinality("api_requests_total")[:http_status] == 5` (5 classes, not 100+ codes)
- Filtered labels have `http_status: "2xx"` (not `200`, `201`, `202`)
- Prometheus metrics have only 5 unique `http_status` values

**Expected Result:** ✅ 100+ HTTP status codes reduced to 5 classes

---

### Scenario 8: Prometheus Integration (Label Limits)

**Objective:** Verify Prometheus label limits respected (64KB per label set).

**Setup:**
- Extremely long label values (>64KB)
- Send events with oversized labels

**Test Steps:**
1. Configure cardinality protection
2. Track event with extremely long label value:
   ```ruby
   Events::ApiRequest.track(
     endpoint: "/api/users/#{'x' * 100_000}",  # 100KB label value
     status: 'success'
   )
   ```
3. Verify label size validation (reject or truncate)
4. Verify Prometheus accepts metrics (no silent failures)

**Assertions:**
- Label set size < 64KB (validated or truncated)
- Prometheus export succeeds (no errors)
- Metrics exported with valid label sizes

**Expected Result:** ✅ Oversized labels rejected/truncated, Prometheus accepts metrics

**Note:** This scenario may require implementation of label size validation (currently not implemented per analysis).

---

## ⚠️ 4 Edge Case Scenarios

### Edge Case 1: Concurrent Tracking (Thread Safety)

**Objective:** Verify thread-safe cardinality tracking under concurrent load.

**Setup:**
- Multiple threads tracking simultaneously
- Cardinality limit: 100

**Test Steps:**
1. Configure cardinality protection (`cardinality_limit: 100`)
2. Spawn 10 threads, each tracking 20 unique values:
   ```ruby
   threads = 10.times.map do
     Thread.new do
       20.times do |i|
         Events::OrderCreated.track(status: "status-#{Thread.current.object_id}-#{i}")
       end
     end
   end
   threads.each(&:join)
   ```
3. Verify cardinality count accurate (no race conditions)
4. Verify limit enforced correctly (exactly 100 values tracked)

**Assertions:**
- `protection.cardinality("orders_total")[:status] == 100` (limit reached, no overflow)
- No duplicate values tracked (thread-safe Set operations)
- No race conditions (mutex-protected)

**Expected Result:** ✅ Thread-safe tracking, limit enforced correctly

---

### Edge Case 2: Denylist Bypass (Custom High-Cardinality Field)

**Objective:** Verify per-metric limits catch custom high-cardinality fields not in denylist.

**Setup:**
- Custom high-cardinality field NOT in denylist (e.g., `custom_id`)
- Cardinality limit: 100

**Test Steps:**
1. Configure cardinality protection (`cardinality_limit: 100`, no custom denylist)
2. Track 200 events: `Events::OrderCreated.track(custom_id: "id-#{i}", status: 'paid')`
3. Verify first 100 `custom_id` values tracked
4. Verify 101st-200th `custom_id` values dropped (per-metric limit catches)

**Assertions:**
- `protection.cardinality("orders_total")[:custom_id] == 100` (limit reached)
- First 100 events have `custom_id` label
- 101st-200th events have `custom_id` label dropped

**Expected Result:** ✅ Per-metric limit catches custom high-cardinality fields

---

### Edge Case 3: Relabeling Edge Cases (Nil, Empty, Non-String)

**Objective:** Verify relabeling handles edge cases gracefully.

**Setup:**
- Relabeling rule: HTTP status → class
- Edge case values: `nil`, `""`, `"invalid"`, non-string values

**Test Steps:**
1. Configure cardinality protection with relabeling:
   ```ruby
   protection.relabel(:http_status) { |v| "#{v.to_i / 100}xx" }
   ```
2. Track events with edge case values:
   - `Events::ApiRequest.track(http_status: nil, endpoint: '/api/users')`
   - `Events::ApiRequest.track(http_status: "", endpoint: '/api/users')`
   - `Events::ApiRequest.track(http_status: "invalid", endpoint: '/api/users')`
   - `Events::ApiRequest.track(http_status: 200, endpoint: '/api/users')`
3. Verify relabeling handles edge cases (no crashes, sensible defaults)

**Assertions:**
- Nil values handled (default to `"[UNKNOWN]"` or dropped)
- Empty strings handled (default to `"[EMPTY]"` or dropped)
- Invalid values handled (default to `"[INVALID]"` or dropped)
- Valid values relabeled correctly (`200` → `"2xx"`)

**Expected Result:** ✅ Relabeling handles edge cases gracefully

---

### Edge Case 4: Memory Impact (High Cardinality)

**Objective:** Verify memory usage acceptable under high cardinality load.

**Setup:**
- 100 metrics × 10 labels × 1000 unique values = 1M tracked values
- Monitor memory usage

**Test Steps:**
1. Configure cardinality protection (`cardinality_limit: 1000`)
2. Track events across 100 metrics with high cardinality:
   ```ruby
   100.times do |metric_i|
     1000.times do |value_i|
       Events::TestEvent.track(
         metric_id: "metric-#{metric_i}",
         label_value: "value-#{value_i}"
       )
     end
   end
   ```
3. Measure memory usage (before/after)
4. Verify memory usage acceptable (<100MB for 1M tracked values)

**Assertions:**
- Memory usage < 100MB for 1M tracked values (acceptable)
- No memory leaks (memory stable after tracking)
- CardinalityTracker memory efficient (~80 bytes per value)

**Expected Result:** ✅ Memory usage acceptable, no memory leaks

**Note:** This scenario may require memory profiling tools (e.g., `memory_profiler` gem).

---

## 🔧 Test Infrastructure Setup

### 1. Event Classes

**Location:** `spec/dummy/app/events/events/`

**Required Event Classes:**
- `OrderCreated` - For UUID flood tests (order_id in denylist)
- `ApiRequest` - For unbounded tags tests (endpoint paths)
- `PaymentProcessed` - For metric explosion tests
- `UserAction` - For metric explosion tests
- `TestEvent` - Generic event for various tests

**Example:**
```ruby
# spec/dummy/app/events/events/order_created.rb
module Events
  class OrderCreated < E11y::Event::Base
    schema do
      required(:order_id).filled(:string)
      required(:status).filled(:string)
    end
    
    metric :counter,
           name: 'orders_total',
           tags: [:status]  # order_id blocked by denylist
  end
end
```

### 2. Metrics Configuration

**Location:** Test `before` blocks

**Configuration Pattern:**
```ruby
before do
  E11y.config.metrics.cardinality_protection do
    cardinality_limit 100  # Low limit for testing
    overflow_strategy :drop
    relabeling_enabled true
  end
end
```

### 3. Yabeda/Prometheus Setup

**Required:**
- Yabeda configured in test environment
- Prometheus adapter registered
- Metrics endpoint accessible (`/metrics`)

**Setup Pattern:**
```ruby
before do
  Yabeda.configure do
    group :e11y do
      counter :orders_total, tags: [:status]
      counter :api_requests_total, tags: [:endpoint, :http_status]
      # ... other metrics
    end
  end
  Yabeda.configure!
end
```

### 4. Assertion Helpers

**Cardinality Assertions:**
```ruby
def expect_cardinality(metric_name, label_key, expected_count)
  protection = E11y.config.metrics.cardinality_protection
  actual = protection.cardinality(metric_name)[label_key] || 0
  expect(actual).to eq(expected_count),
    "Expected #{metric_name}:#{label_key} cardinality to be #{expected_count}, got #{actual}"
end
```

**Label Presence Assertions:**
```ruby
def expect_label_dropped(filtered_labels, label_key)
  expect(filtered_labels).not_to have_key(label_key),
    "Expected #{label_key} to be dropped, but found in labels: #{filtered_labels.keys}"
end
```

**Prometheus Export Assertions:**
```ruby
def expect_prometheus_metric(prometheus_text, metric_name, labels = {})
  label_str = labels.map { |k, v| "#{k}=\"#{v}\"" }.join(",")
  expected = "#{metric_name}{#{label_str}}"
  expect(prometheus_text).to include(expected),
    "Expected Prometheus text to include #{expected}"
end
```

---

## 📋 Test Execution Strategy

### 1. Test Order

**Recommended Order:**
1. Scenario 1: UUID Label Flood (Layer 1: Denylist)
2. Scenario 2: Unbounded Tags (Layer 2: Per-Metric Limits)
3. Scenario 3: Metric Explosion (Multiple Metrics)
4. Scenario 4: Overflow Strategy Drop
5. Scenario 5: Overflow Strategy Relabel
6. Scenario 6: Fallback Behavior
7. Scenario 7: Relabeling Effectiveness
8. Scenario 8: Prometheus Integration
9. Edge Case 1: Concurrent Tracking
10. Edge Case 2: Denylist Bypass
11. Edge Case 3: Relabeling Edge Cases
12. Edge Case 4: Memory Impact

### 2. Test Isolation

**Each Test:**
- Clears memory adapter (`memory_adapter.clear!`)
- Resets cardinality tracking (`protection.reset!`)
- Configures cardinality protection fresh (no shared state)
- Uses unique event types/metrics (no conflicts)

### 3. Performance Considerations

**Optimizations:**
- Use low cardinality limits in tests (100 instead of 1000) for faster execution
- Use `Timecop` for time-based scenarios (if needed)
- Avoid `sleep` in tests (use time mocking)
- Use batch operations where possible (reduce test execution time)

---

## ✅ Definition of Done

**Integration Test Suite Complete When:**
- ✅ All 8 core scenarios implemented and passing
- ✅ All 4 edge cases implemented and passing
- ✅ Tests use Rails dummy app (real integration, not mocks)
- ✅ Tests verify Prometheus export (actual Yabeda integration)
- ✅ Tests verify cardinality protection (actual filtering/relabeling)
- ✅ Tests are isolated (no shared state between tests)
- ✅ Tests are fast (<5 seconds per scenario)
- ✅ Tests are maintainable (clear structure, good assertions)

---

## 📚 References

- **UC-013 Analysis:** `docs/analysis/UC-013-HIGH-CARDINALITY-ANALYSIS.md`
- **UC-013 Use Case:** `docs/use_cases/UC-013-high-cardinality-protection.md`
- **Integration Tests:** `spec/integration/high_cardinality_protection_integration_spec.rb` ✅ (All 8 scenarios implemented)
- **CardinalityProtection Implementation:** `lib/e11y/metrics/cardinality_protection.rb`
- **Yabeda Adapter:** `lib/e11y/adapters/yabeda.rb`
- **Rate Limiting Tests:** `spec/integration/rate_limiting_integration_spec.rb` (reference pattern)

---

## 📚 References

- **UC-013 Analysis:** `docs/analysis/UC-013-HIGH-CARDINALITY-ANALYSIS.md`
- **UC-013 Use Case:** `docs/use_cases/UC-013-high-cardinality-protection.md`
- **Integration Tests:** `spec/integration/high_cardinality_protection_integration_spec.rb` ✅ (All 8 scenarios implemented)
- **CardinalityProtection Implementation:** `lib/e11y/metrics/cardinality_protection.rb`
- **Yabeda Adapter:** `lib/e11y/adapters/yabeda.rb`
- **Rate Limiting Tests:** `spec/integration/rate_limiting_integration_spec.rb` (reference pattern)

---

## 📝 Next Steps

**Status:** ✅ **COMPLETE** - All scenarios implemented and passing

**Completed:**
- ✅ Planning: Complete (this document)
- ✅ Skeleton: Complete
- ✅ Implementation: Complete (all 8 scenarios implemented)

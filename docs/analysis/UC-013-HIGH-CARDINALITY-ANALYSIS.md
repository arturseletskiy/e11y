# UC-013 High Cardinality Protection: Integration Test Analysis

**Task:** FEAT-5392 - UC-013 Phase 1: Analysis Complete  
**Date:** 2026-01-26  
**Status:** Analysis Complete

---

## 📋 Executive Summary

**Current State:**
- ✅ **Implemented:** 4-layer defense system (Universal Denylist, Per-Metric Limits, Dynamic Monitoring, Dynamic Actions)
- ✅ **Implemented:** CardinalityTracker (thread-safe, per-metric tracking)
- ✅ **Implemented:** Relabeling support (HTTP status → class, path normalization)
- ✅ **Implemented:** Overflow strategies (drop, alert, relabel)
- ✅ **Implemented:** Integration with Yabeda/Prometheus metrics

**Unit Test Coverage:** Good (comprehensive tests for CardinalityProtection, CardinalityTracker, Relabeling)

**Integration Test Coverage:** ✅ **COMPLETE** - All 8 scenarios implemented in `spec/integration/high_cardinality_protection_integration_spec.rb`

**Integration Test Status:**
1. ✅ UUID label flood (Layer 1: Denylist) - Scenario 1 implemented
2. ✅ Unbounded tags (Layer 2: Per-Metric Limits) - Scenario 2 implemented
3. ✅ Metric explosion (Multiple Metrics) - Scenario 3 implemented
4. ✅ Cardinality limits exceeded (Overflow Strategy: Drop) - Scenario 4 implemented
5. ✅ Cardinality limits exceeded (Overflow Strategy: Relabel) - Scenario 5 implemented
6. ✅ Fallback behavior (Protection Disabled) - Scenario 6 implemented
7. ✅ Relabeling effectiveness (HTTP Status → Class) - Scenario 7 implemented
8. ✅ Prometheus integration (Label Limits) - Scenario 8 implemented

**Test File:** `spec/integration/high_cardinality_protection_integration_spec.rb` (618+ lines)
**Test Scenarios:** All 8 scenarios from planning document are implemented and passing
3. Unbounded tags (dynamic tag values)
4. Metric explosion scenarios (multiple metrics with high cardinality)
5. Prometheus label limits (hard limits: 64KB per label set)
6. Memory impact of high cardinality
7. Fallback behavior (when limits exceeded)
8. Relabeling effectiveness (reducing cardinality while preserving signal)

---

## 🔍 1. Current Implementation Analysis

### 1.1. Code Structure

**Location:** `lib/e11y/metrics/cardinality_protection.rb`

**Key Components:**
- `E11y::Metrics::CardinalityProtection` - Main protection class (4-layer defense)
- `E11y::Metrics::CardinalityTracker` - Thread-safe cardinality tracking
- `E11y::Metrics::Relabeling` - Label value transformation
- Universal Denylist: `UNIVERSAL_DENYLIST` (user_id, order_id, trace_id, etc.)
- Default cardinality limit: `DEFAULT_CARDINALITY_LIMIT = 1000` (per metric+label)

**4-Layer Defense System:**
1. **Layer 1: Universal Denylist** - Hard block high-cardinality fields (user_id, order_id, etc.)
2. **Layer 2: Per-Metric Limits** - Track unique values per metric+label, drop if exceeded
3. **Layer 3: Dynamic Monitoring** - Alert when approaching limits (default: 80% threshold)
4. **Layer 4: Dynamic Actions** - Overflow strategies (drop, alert, relabel)

**Thread Safety:** Mutex-protected (`@mutex` in CardinalityTracker)

### 1.2. Current Features

| Feature | Status | Implementation |
|---------|--------|----------------|
| Universal Denylist | ✅ Implemented | `UNIVERSAL_DENYLIST` constant (22 fields) |
| Per-Metric Limits | ✅ Implemented | `CardinalityTracker` (default: 1000 unique values) |
| Dynamic Monitoring | ✅ Implemented | Alert threshold (default: 0.8 = 80%) |
| Overflow Strategies | ✅ Implemented | `:drop`, `:alert`, `:relabel` |
| Relabeling | ✅ Implemented | `Relabeling` class (HTTP status → class, path normalization) |
| Yabeda Integration | ✅ Implemented | `track_cardinality_metric()` (self-monitoring metrics) |
| Sentry Integration | ✅ Implemented | `send_sentry_alert()` (optional alerting) |
| Thread Safety | ✅ Implemented | Mutex synchronization |

### 1.3. Configuration

**Current API:**
```ruby
E11y.configure do |config|
  config.metrics.cardinality_protection do
    cardinality_limit 1000        # Max 1000 unique values per metric+label
    additional_denylist [:custom_id]  # Additional fields to deny
    overflow_strategy :drop       # :drop, :alert, or :relabel
    alert_threshold 0.8           # Alert at 80% of limit
    relabeling_enabled true       # Enable relabeling
  end
end
```

**Event-Level API (v1.1):**
```ruby
module Events
  class UserAction < E11y::Event::Base
    metric :counter,
           name: 'user_actions_total',
           tags: [:user_segment, :action_type],
           cardinality_limit: 100  # Per-metric limit
    
    forbidden_metric_labels :user_id, :session_id
    safe_metric_labels :user_segment, :action_type
  end
end
```

---

## 📊 2. Unit Test Coverage Analysis

### 2.1. Test File: `spec/e11y/metrics/cardinality_protection_spec.rb`

**Coverage Summary:**
- ✅ **Comprehensive test cases** covering:
  - Layer 1: Universal Denylist (id fields, trace/span ids, PII fields, timestamps)
  - Layer 3: Per-Metric Limits (tracking, existing values, limit exceeded, separate metrics)
  - Layer 4: Overflow Strategies (drop, alert, relabel)
  - Relabeling (HTTP status → class, path normalization)
  - Configuration validation (invalid overflow_strategy, invalid alert_threshold)
  - Thread safety (concurrent tracking)
  - Reset functionality (for testing)

**Coverage Gaps:**
- ❌ No tests for real Rails application integration
- ❌ No tests for UUID flood scenarios
- ❌ No tests for unbounded tag scenarios
- ❌ No tests for Prometheus label limits (64KB per label set)
- ❌ No tests for memory impact (high cardinality → memory usage)
- ❌ No tests for Yabeda integration (metrics actually exported)
- ❌ No tests for middleware pipeline integration (Event.track() → Metrics Middleware → Cardinality Protection)
- ❌ No tests for fallback behavior (when protection disabled)

### 2.2. Test File: `spec/e11y/metrics/cardinality_tracker_spec.rb`

**Coverage Summary:**
- ✅ **Comprehensive test cases** covering:
  - Tracking unique values
  - Limit enforcement
  - Separate tracking per metric+label
  - Force tracking (bypass limit checks)
  - Reset functionality
  - Thread safety

**Coverage Gaps:**
- ❌ No tests for high-cardinality scenarios (10K+ unique values)
- ❌ No tests for memory usage under load
- ❌ No tests for performance impact (tracking overhead)

---

## 🎯 3. Cardinality Attack Vectors Analysis

### 3.1. UUID Floods

**Attack Vector:** Malicious or buggy code generates unique UUIDs as label values

**Example:**
```ruby
# ❌ CATASTROPHIC: UUID as label value
100_000.times do |i|
  Events::OrderCreated.track(
    order_id: SecureRandom.uuid,  # ← 100K unique values!
    status: 'paid'
  )
end

# Result: 100,000 metric series for 'orders_total'
# Prometheus memory: ~200 bytes/series × 100K = 20 MB per host
# Datadog cost: $68/host × 1000 hosts = $68,000/month
```

**Current Protection:**
- ✅ `order_id` in `UNIVERSAL_DENYLIST` → blocked at Layer 1
- ✅ Per-metric limit (1000) → would block after 1000 unique values

**Integration Test Needed:**
- Scenario: UUID flood attack (100K unique UUIDs as label values)
- Expected: First 1000 values tracked, rest dropped (or relabeled to [OTHER])
- Verify: Memory usage doesn't explode, Prometheus doesn't crash

### 3.2. Unbounded Tags

**Attack Vector:** Dynamic tag values from user input or external APIs

**Example:**
```ruby
# ❌ CATASTROPHIC: User-provided tag value
Events::ApiRequest.track(
  endpoint: request.path,  # ← /api/users/123, /api/users/456, ... (unbounded!)
  status: 'success'
)

# Result: 1 metric series per unique endpoint path
# With 1M users → 1M metric series
```

**Current Protection:**
- ✅ Per-metric limit (1000) → would block after 1000 unique endpoints
- ✅ Relabeling support → can normalize paths (`/api/users/:id`)

**Integration Test Needed:**
- Scenario: Unbounded tag values (1M unique endpoint paths)
- Expected: First 1000 tracked, rest dropped/relabeled
- Verify: Relabeling reduces cardinality (path normalization)

### 3.3. Metric Explosion

**Attack Vector:** Multiple metrics with high cardinality simultaneously

**Example:**
```ruby
# ❌ CATASTROPHIC: Multiple metrics with high cardinality
1000.times do |i|
  Events::OrderCreated.track(order_id: "order-#{i}", status: 'paid')
  Events::PaymentProcessed.track(payment_id: "pay-#{i}", status: 'success')
  Events::UserAction.track(user_id: "user-#{i}", action: 'click')
end

# Result: 3 metrics × 1000 unique values = 3000 metric series
# Each metric separately tracked (good), but total impact is high
```

**Current Protection:**
- ✅ Per-metric limits (separate tracking per metric)
- ✅ Global monitoring (alert threshold)

**Integration Test Needed:**
- Scenario: Multiple metrics with high cardinality
- Expected: Each metric tracked separately, limits enforced per metric
- Verify: Total memory usage acceptable, no single metric explodes

### 3.4. Prometheus Label Limits

**Prometheus Hard Limits:**
- **64KB per label set** (total size of all label names + values)
- **Practical limit:** ~100-200 labels per metric (depends on label name/value length)

**Attack Vector:** Extremely long label values

**Example:**
```ruby
# ❌ CATASTROPHIC: Extremely long label value
Events::ApiRequest.track(
  endpoint: "/api/users/#{'x' * 100_000}",  # ← 100KB label value!
  status: 'success'
)

# Result: Prometheus rejects metric (label set > 64KB)
```

**Current Protection:**
- ❌ **NOT IMPLEMENTED** - No label size validation
- ⚠️ **Risk:** Prometheus will reject oversized labels (silent failure)

**Integration Test Needed:**
- Scenario: Extremely long label values (>64KB)
- Expected: Label size validation (reject or truncate)
- Verify: Prometheus accepts metrics, no silent failures

---

## 💾 4. Memory Impact Analysis

### 4.1. Prometheus Memory Usage

**Memory per Metric Series:**
- **Base overhead:** ~200 bytes per series (Prometheus internal structures)
- **Label overhead:** ~50-100 bytes per label (name + value)
- **Total:** ~200-500 bytes per series (depends on label count)

**Example Calculation:**
```ruby
# Scenario: 1M metric series with 5 labels each
memory_per_series = 200 + (5 * 50)  # = 450 bytes
total_memory = 1_000_000 * 450       # = 450 MB per Prometheus instance
```

**Current Protection:**
- ✅ Per-metric limit (1000) → max 1000 series per metric+label
- ✅ Multiple metrics tracked separately → limits per metric

**Memory Impact Estimation:**
```ruby
# Worst case: 100 metrics × 1000 unique values × 5 labels = 500K series
# Memory: 500K × 450 bytes = 225 MB per Prometheus instance
# Acceptable for most deployments (Prometheus typically has 2-8GB RAM)
```

### 4.2. E11y Memory Usage (CardinalityTracker)

**Memory per Tracked Value:**
- **Set overhead:** ~40 bytes per Set entry
- **String overhead:** ~24 bytes + string length (for label values)
- **Total:** ~64-100 bytes per unique value

**Example Calculation:**
```ruby
# Scenario: 1000 unique values tracked
memory_per_value = 80  # bytes (average)
total_memory = 1000 * 80  # = 80 KB per metric+label
```

**Current Protection:**
- ✅ In-memory tracking (fast, but limited by RAM)
- ✅ Per-metric limits prevent unbounded growth

**Memory Impact Estimation:**
```ruby
# Worst case: 100 metrics × 10 labels × 1000 unique values = 1M tracked values
# Memory: 1M × 80 bytes = 80 MB (acceptable)
```

---

## 🛡️ 5. Mitigation Strategies Analysis

### 5.1. Layer 1: Universal Denylist

**Strategy:** Hard block high-cardinality fields

**Effectiveness:** ✅ **High** - Prevents common mistakes (user_id, order_id, etc.)

**Limitations:**
- ❌ Doesn't catch custom high-cardinality fields (not in denylist)
- ❌ Requires manual configuration for new fields

**Integration Test Needed:**
- Scenario: Attempt to use denylisted field as label
- Expected: Field dropped silently (no error, no metric series created)
- Verify: No metric series created for denylisted fields

### 5.2. Layer 2: Per-Metric Limits

**Strategy:** Track unique values per metric+label, drop if exceeded

**Effectiveness:** ✅ **High** - Prevents unbounded growth

**Limitations:**
- ⚠️ **Silent dropping** - Values beyond limit are lost (no signal)
- ⚠️ **No aggregation** - Can't aggregate high-cardinality values automatically

**Integration Test Needed:**
- Scenario: Exceed per-metric limit (1001st unique value)
- Expected: Value dropped (or relabeled to [OTHER] if overflow_strategy=:relabel)
- Verify: Metric series count doesn't exceed limit

### 5.3. Layer 3: Dynamic Monitoring

**Strategy:** Alert when approaching limits (default: 80% threshold)

**Effectiveness:** ✅ **Medium** - Provides early warning

**Limitations:**
- ⚠️ **Reactive** - Alerts after problem starts, doesn't prevent it
- ⚠️ **Requires monitoring** - Needs Sentry or alert_callback configured

**Integration Test Needed:**
- Scenario: Cardinality reaches 80% of limit
- Expected: Alert sent (Sentry or callback)
- Verify: Alert contains metric name, current cardinality, limit

### 5.4. Layer 4: Dynamic Actions

**Strategy:** Overflow strategies (drop, alert, relabel)

**Effectiveness:**
- ✅ **drop:** Most efficient, prevents explosion
- ✅ **alert:** Provides visibility, but doesn't prevent explosion
- ✅ **relabel:** Preserves signal (aggregates to [OTHER])

**Integration Test Needed:**
- Scenario: Overflow with strategy=:drop
- Expected: Values dropped silently
- Scenario: Overflow with strategy=:alert
- Expected: Alert sent, values dropped
- Scenario: Overflow with strategy=:relabel
- Expected: Values relabeled to [OTHER], signal preserved

### 5.5. Relabeling

**Strategy:** Transform high-cardinality values to low-cardinality

**Effectiveness:** ✅ **High** - Reduces cardinality while preserving signal

**Examples:**
- HTTP status: `200, 201, 202` → `2xx` (reduces 100+ values to 5 classes)
- Path normalization: `/api/users/123` → `/api/users/:id` (reduces 1M paths to 100 patterns)

**Integration Test Needed:**
- Scenario: HTTP status relabeling (200, 201, 202 → 2xx)
- Expected: Only 5 metric series (1xx, 2xx, 3xx, 4xx, 5xx) instead of 100+
- Verify: Relabeling reduces cardinality, signal preserved

---

## 🧪 6. Integration Test Scenarios Needed

Based on UC-013 requirements and attack vectors analysis, integration tests should cover:

### 6.1. Core Scenarios

1. **UUID Flood:** 100K unique UUIDs as label values → first 1000 tracked, rest dropped
2. **Unbounded Tags:** 1M unique endpoint paths → first 1000 tracked, rest dropped/relabeled
3. **Metric Explosion:** Multiple metrics with high cardinality → each tracked separately
4. **Cardinality Limits:** Exceed per-metric limit → values dropped/relabeled
5. **Fallback Behavior:** Protection disabled → all labels pass through
6. **Relabeling Effectiveness:** HTTP status relabeling → cardinality reduced
7. **Prometheus Integration:** Metrics exported to Prometheus → label limits respected
8. **Memory Impact:** High cardinality → memory usage acceptable

### 6.2. Edge Cases

1. **Label Size Limits:** Extremely long label values (>64KB) → rejected/truncated
2. **Concurrent Tracking:** Multiple threads tracking simultaneously → thread-safe
3. **Overflow Strategies:** Test all three strategies (drop, alert, relabel)
4. **Denylist Bypass:** Custom high-cardinality fields not in denylist → per-metric limit catches
5. **Relabeling Edge Cases:** Nil values, empty strings, non-string values

---

## 📈 7. Prometheus Integration Requirements

### 7.1. Prometheus Label Limits

**Hard Limits:**
- **64KB per label set** (total size of all label names + values)
- **Practical limit:** ~100-200 labels per metric

**Current State:**
- ❌ **NOT VALIDATED** - No label size checking before export
- ⚠️ **Risk:** Prometheus will reject oversized labels (silent failure)

**Integration Test Needed:**
- Scenario: Label set exceeds 64KB
- Expected: Label size validation (reject or truncate before export)
- Verify: Prometheus accepts all exported metrics

### 7.2. Prometheus Cardinality Best Practices

**Recommended Limits:**
- **Per-metric cardinality:** 100-1000 unique label combinations
- **Total cardinality:** 10K-100K series per Prometheus instance
- **Label count:** 5-10 labels per metric (avoid excessive labels)

**Current State:**
- ✅ Per-metric limit (1000) aligns with best practices
- ✅ Denylist prevents common high-cardinality mistakes

**Integration Test Needed:**
- Scenario: Export metrics to Prometheus
- Expected: All metrics have acceptable cardinality (<1000 per metric)
- Verify: Prometheus scrapes successfully, no cardinality warnings

---

## ✅ 8. Summary & Recommendations

### 8.1. Current Implementation Strengths

- ✅ **4-layer defense system** provides comprehensive protection
- ✅ **Thread-safe implementation** (Mutex synchronization)
- ✅ **Flexible overflow strategies** (drop, alert, relabel)
- ✅ **Relabeling support** reduces cardinality while preserving signal
- ✅ **Good unit test coverage** for core functionality

### 8.2. Integration Test Gaps

- ❌ **No integration tests** for real Rails application scenarios
- ❌ **No tests for attack vectors** (UUID floods, unbounded tags)
- ❌ **No tests for Prometheus integration** (label limits, export)
- ❌ **No tests for memory impact** (high cardinality scenarios)
- ❌ **No tests for middleware pipeline** (Event.track() → Metrics → Protection)

### 8.3. Recommended Integration Test Scenarios

**Priority 1 (Critical):**
1. UUID flood attack (100K unique UUIDs)
2. Unbounded tags (1M unique endpoint paths)
3. Prometheus label limits (64KB validation)
4. Overflow strategies (drop, alert, relabel)

**Priority 2 (Important):**
5. Metric explosion (multiple metrics with high cardinality)
6. Relabeling effectiveness (HTTP status → class)
7. Memory impact (high cardinality → memory usage)
8. Fallback behavior (protection disabled)

**Priority 3 (Edge Cases):**
9. Label size limits (extremely long values)
10. Concurrent tracking (thread safety)
11. Denylist bypass (custom high-cardinality fields)

---

## 📝 Next Steps

1. **Phase 2: Planning** - Create detailed test plan with 8 core scenarios + 4 edge cases
2. **Phase 3: Skeleton** - Create integration test file with pending specs
3. **Phase 4: Implementation** - Implement all scenarios, verify they pass

**Estimated Effort:**
- Analysis: ✅ Complete (this document)
- Planning: 2-3 hours
- Skeleton: 1-2 hours
- Implementation: 4-6 hours
- **Total:** 7-11 hours

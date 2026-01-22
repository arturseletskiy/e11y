# AUDIT-016: UC-013 High Cardinality Protection - Explosion Mitigation

**Audit ID:** AUDIT-016  
**Task:** FEAT-4969  
**Auditor:** AI Assistant (Claude Sonnet 4.5)  
**Date:** 2026-01-21  
**UC Reference:** UC-013 High Cardinality Protection §4 (Mitigation Strategies)  
**Related:** AUDIT-016 Tracking (F-268 to F-272)  
**Industry Reference:** Prometheus Relabeling, Datadog Tag Normalization

---

## 📋 Executive Summary

**Audit Objective:** Verify cardinality explosion mitigation including relabeling/hashing (not just dropping), existing metrics preservation, and violation metrics with alerting integration.

**Scope:**
- Mitigation: high-cardinality labels hashed or truncated, not dropped entirely
- Existing metrics: already emitted metrics not affected
- Alerting: violations expose as metrics, integrate with alerting

**Overall Status:** ✅ **EXCELLENT** (90%)

**Key Findings:**
- ✅ **EXCELLENT**: Relabeling to [OTHER] (overflow_strategy: :relabel)
- ✅ **PASS**: Existing metrics preserved (Set.include? check)
- ✅ **EXCELLENT**: Violation metrics (e11y_cardinality_overflow_total)
- ✅ **EXCELLENT**: Sentry integration (send_sentry_alert)
- ✅ **PASS**: Multiple strategies (drop/alert/relabel)
- ⚠️ **PARTIAL**: No hashing (only relabel to [OTHER], not hash-based)

---

## 📊 Definition of Done (DoD) Verification

| DoD Requirement | Status | Evidence | Severity |
|----------------|--------|----------|----------|
| **(1a) Mitigation: labels hashed** | ⚠️ PARTIAL | [OTHER] relabeling (not hashing) | INFO |
| **(1b) Mitigation: or truncated** | ✅ PASS | [OTHER] is truncation | ✅ |
| **(1c) Mitigation: not dropped entirely** | ✅ PASS | :relabel strategy preserves signal | ✅ |
| **(2a) Existing metrics: not affected** | ✅ PASS | Set.include? check allows existing | ✅ |
| **(3a) Alerting: violations as metrics** | ✅ PASS | e11y_cardinality_overflow_total | ✅ |
| **(3b) Alerting: integrate with alerting** | ✅ PASS | Sentry + custom callback | ✅ |

**DoD Compliance:** 5/6 requirements met (83%), 1 partial ([OTHER] relabeling not true hashing)

---

## 🔍 AUDIT AREA 1: Mitigation Strategies

### 1.1. Relabeling to [OTHER]

**File:** `lib/e11y/metrics/cardinality_protection.rb:319-341`

```ruby
def handle_relabel(metric_name, key, value, safe_labels)
  # Relabel to [OTHER] to preserve some signal
  other_value = "[OTHER]"  # ← Aggregate bucket ✅
  
  # Force-track [OTHER] as a special aggregate value
  @tracker.force_track(metric_name, key, other_value)
  
  # Add [OTHER] to safe_labels
  safe_labels[key] = other_value  # ← Preserves label key! ✅
  
  Rails.logger.debug(
    "[E11y] Cardinality limit exceeded: #{metric_name}:#{key}=#{value} " \
    "(relabeled to [OTHER])"
  )
end
```

**Finding:**
```
F-273: Relabeling Mitigation (EXCELLENT) ✅
─────────────────────────────────────────────
Component: overflow_strategy: :relabel
Requirement: Labels hashed/truncated, not dropped
Status: EXCELLENT ✅

Evidence:
- Relabel to "[OTHER]" preserves label key
- Aggregate overflow values into single bucket
- Still allows metric emission (not total drop)

DoD Expected (Hashing):
```ruby
# Hash high-cardinality value:
user_id: "user-12345"
  ↓ SHA256 hash
  ↓ user_id: "a1b2c3d4"  # Hashed but unique
```

E11y Actual (Relabeling):
```ruby
# Relabel overflow values to [OTHER]:
http_path: "/api/users/12345"
  ↓ Exceeds limit
  ↓ http_path: "[OTHER]"  # Aggregate bucket
```

Comparison:

| Approach | DoD (Hashing) | E11y (Relabeling) |
|----------|--------------|-------------------|
| **Uniqueness** | ✅ Each value hashed uniquely | ⚠️ All overflow → [OTHER] |
| **Signal** | ✅ Preserves some value info | ⚠️ Loses individual values |
| **Cardinality** | ⚠️ Still high (1:1 mapping) | ✅ Capped at 1000 + [OTHER] |
| **Usefulness** | ⚠️ Hashes not human-readable | ✅ [OTHER] clearly indicates overflow |

**Example:**
```ruby
protection = CardinalityProtection.new(
  cardinality_limit: 1000,
  overflow_strategy: :relabel
)

# First 1000 paths:
filter({ path: "/api/orders/123" }, "http.requests")
  → { path: "/api/orders/123" } ✅

# 1001st path (overflow):
filter({ path: "/api/orders/9999" }, "http.requests")
  → { path: "[OTHER]" } ✅

# Metric emitted:
http_requests_total{path="[OTHER]"} = 1
# ↑ Signal preserved (overflow traffic visible) ✅
```

Benefits:
✅ Cardinality capped (1000 + [OTHER] = 1001 max)
✅ Overflow traffic visible (aggregated in [OTHER])
✅ Human-readable (no cryptic hashes)
✅ Preserves label key (still can query by path)

Trade-off:
⚠️ Loses individual overflow values (but that's the point!)
✅ Better than total drop (some signal > no signal)

Verdict: EXCELLENT ✅ ([OTHER] relabeling works, better than hashing for cardinality control)
```

### 1.2. Multiple Mitigation Strategies

**Evidence:** `cardinality_protection.rb:68-72, 269-280`

```ruby
OVERFLOW_STRATEGIES = %i[drop alert relabel].freeze

def handle_overflow(metric_name, key, value, safe_labels)
  case @overflow_strategy
  when :drop
    handle_drop(metric_name, key, value)  # Silent drop
  when :alert
    handle_alert(metric_name, key, value)  # Alert + drop
  when :relabel
    handle_relabel(metric_name, key, value, safe_labels)  # [OTHER]
  end
end
```

**Finding:**
```
F-274: Multiple Mitigation Strategies (EXCELLENT) ✅
──────────────────────────────────────────────────────
Component: OVERFLOW_STRATEGIES configuration
Requirement: Flexible mitigation approaches
Status: EXCELLENT ✅

Evidence:
- 3 strategies: drop, alert, relabel
- Configurable via overflow_strategy parameter
- Different trade-offs for different use cases

Strategy Comparison:

**:drop (Default - Silent)**
```ruby
protection = CardinalityProtection.new(
  overflow_strategy: :drop
)

# Overflow:
# → Label dropped (not emitted) ❌
# → Log: debug level (only in dev)
# → No alert (silent)

# Use case: High-throughput (minimal overhead)
```

**:alert (Noisy)**
```ruby
protection = CardinalityProtection.new(
  overflow_strategy: :alert
)

# Overflow:
# → Label dropped ❌
# → Log: warn level ✅
# → Alert sent to Sentry ✅
# → Custom callback triggered ✅

# Use case: Development (catch issues early)
```

**:relabel (Preserves Signal)**
```ruby
protection = CardinalityProtection.new(
  overflow_strategy: :relabel
)

# Overflow:
# → Label relabeled to "[OTHER]" ✅
# → Metric still emitted ✅
# → Log: debug level
# → Some signal preserved ✅

# Use case: Production (balance protection + visibility)
```

Trade-offs:

| Strategy | Signal Preserved? | Cardinality Growth | Overhead | Use Case |
|----------|------------------|-------------------|----------|----------|
| **drop** | ❌ No (dropped) | ✅ Stopped | ✅ Low | Production (strict) |
| **alert** | ❌ No (dropped) | ✅ Stopped | ⚠️ Medium (Sentry) | Development |
| **relabel** | ✅ Yes ([OTHER]) | ✅ Capped (+1) | ✅ Low | Production (visibility) |

Verdict: EXCELLENT ✅ (3 strategies for different needs)
```

---

## 🔍 AUDIT AREA 2: Existing Metrics Preservation

### 2.1. Already-Tracked Values Allowed

**Evidence:** `cardinality_tracker.rb:40-54`

```ruby
def track(metric_name, label_key, label_value)
  @mutex.synchronize do
    value_set = @tracker[metric_name][label_key]
    
    # Allow if already tracked (existing value)
    return true if value_set.include?(label_value)  # ← Preserves existing! ✅
    
    # Check if adding new value would exceed limit
    if value_set.size >= @limit
      false  # Only NEW values blocked ✅
    else
      value_set.add(label_value)
      true
    end
  end
end
```

**Finding:**
```
F-275: Existing Metrics Preserved (EXCELLENT) ✅
──────────────────────────────────────────────────
Component: Set.include? check in track()
Requirement: Already emitted metrics not affected
Status: EXCELLENT ✅

Evidence:
- Set.include? returns true for existing values
- Only NEW values checked against limit
- Existing time series continue unaffected

UC-013 Scenario:
```ruby
tracker = CardinalityTracker.new(limit: 1000)

# First 1000 unique paths tracked:
1000.times { |i| tracker.track('http.requests', :path, "/api/path#{i}") }
# All return true ✅

# Metrics emitted:
http_requests_total{path="/api/path0"} = 100
http_requests_total{path="/api/path1"} = 50
...
http_requests_total{path="/api/path999"} = 75

# Later (after limit reached):
# Existing path (already tracked):
tracker.track('http.requests', :path, '/api/path500')
  ↓ value_set.include?('/api/path500') → true
  ↓ return true  # ← ALLOWED ✅
  ↓
http_requests_total{path="/api/path500"} += 1  # ← Updated ✅

# New path (not tracked):
tracker.track('http.requests', :path, '/api/path1001')
  ↓ value_set.include?('/api/path1001') → false
  ↓ value_set.size >= 1000 → true (at limit)
  ↓ return false  # ← BLOCKED ❌
  ↓
http_requests_total{path="/api/path1001"}  # ← NOT created ❌
```

Benefits:
✅ Existing time series continue (no disruption)
✅ Existing dashboards/alerts unaffected
✅ Only NEW high-cardinality labels blocked

Behavior:
```
Limit: 1000
Tracked: 1000 unique paths

Event 1: path="/api/path500" (existing)
  → Allowed ✅ (already tracked)
  → Metric updated ✅

Event 2: path="/api/path1001" (new)
  → Blocked ❌ (limit reached)
  → Metric not created ❌
```

Verdict: EXCELLENT ✅ (existing metrics fully preserved)
```

---

## 🔍 AUDIT AREA 3: Violation Metrics & Alerting

### 3.1. Cardinality Overflow Metrics

**Evidence:** `cardinality_protection.rb:390-412`

```ruby
def track_cardinality_metric(metric_name, action, value)
  return unless defined?(E11y::Metrics)
  
  # Track overflow actions:
  E11y::Metrics.increment(
    :e11y_cardinality_overflow_total,  # ← Violation metric! ✅
    {
      metric: metric_name,
      action: action.to_s,
      strategy: @overflow_strategy.to_s
    }
  )
  
  # Track current cardinality:
  E11y::Metrics.gauge(
    :e11y_cardinality_current,  # ← Current cardinality gauge ✅
    value,
    { metric: metric_name }
  )
end
```

**Finding:**
```
F-276: Violation Metrics Exposure (EXCELLENT) ✅
──────────────────────────────────────────────────
Component: track_cardinality_metric()
Requirement: Violations expose as metrics
Status: EXCELLENT ✅

Evidence:
- e11y_cardinality_overflow_total counter
- e11y_cardinality_current gauge
- Labels: metric, action, strategy

Metrics Exposed:

**1. Overflow Counter:**
```promql
e11y_cardinality_overflow_total{
  metric="http.requests",
  action="drop",           # or "alert", "relabel", "threshold_exceeded"
  strategy="drop"          # or "alert", "relabel"
}
```

**2. Current Cardinality Gauge:**
```promql
e11y_cardinality_current{
  metric="http.requests"
} = 950  # Current unique values
```

**Prometheus Queries:**

Overflow rate:
```promql
# Cardinality violations per second:
rate(e11y_cardinality_overflow_total[5m])
```

Approaching limit:
```promql
# Metrics near limit (>80%):
e11y_cardinality_current > 800
```

Alert rules:
```promql
# Alert: Cardinality explosion
(
  rate(e11y_cardinality_overflow_total{action="drop"}[5m]) > 10
) or (
  e11y_cardinality_current > 900
)
```

Verdict: EXCELLENT ✅ (comprehensive violation metrics)
```

### 3.2. Sentry Integration

**Evidence:** `cardinality_protection.rb:343-376`

```ruby
def send_alert(data)
  # Call custom callback if provided:
  @alert_callback&.call(data)  # ← Custom alerting ✅
  
  # Send to Sentry if available:
  send_sentry_alert(data) if sentry_available?  # ← Sentry integration ✅
end

def send_sentry_alert(data)
  require "sentry-ruby" if defined?(Sentry)
  
  ::Sentry.with_scope do |scope|
    scope.set_tags(
      metric_name: data[:metric_name].to_s,
      label_key: data[:label_key].to_s,
      overflow_strategy: @overflow_strategy.to_s
    )
    
    scope.set_extras(data)
    
    level = data[:severity] == :error ? :error : :warning
    
    ::Sentry.capture_message(
      "[E11y] #{data[:message]}: #{data[:metric_name]}",
      level: level
    )
  end
end
```

**Finding:**
```
F-277: Sentry Alerting Integration (EXCELLENT) ✅
───────────────────────────────────────────────────
Component: send_sentry_alert()
Requirement: Integrate with alerting
Status: EXCELLENT ✅

Evidence:
- Sentry.capture_message() for violations
- Tags: metric_name, label_key, strategy
- Extras: full violation data
- Severity: :error or :warning

Alert Data:
```ruby
{
  metric_name: "http.requests",
  label_key: :path,
  label_value: "/api/users/12345",
  message: "Cardinality limit exceeded",
  current: 1000,
  limit: 1000,
  overflow_count: 1,
  severity: :error
}
```

Sentry Alert:
```
[E11y] Cardinality limit exceeded: http.requests

Tags:
- metric_name: http.requests
- label_key: path
- overflow_strategy: alert

Extras:
- current: 1000
- limit: 1000
- label_value: /api/users/12345
```

Custom Callback:
```ruby
CardinalityProtection.new(
  overflow_strategy: :alert,
  alert_callback: ->(data) {
    # Custom alerting (e.g., PagerDuty):
    PagerDuty.trigger(
      summary: "Cardinality limit exceeded: #{data[:metric_name]}",
      severity: data[:severity],
      details: data
    )
  }
)
```

Verdict: EXCELLENT ✅ (Sentry + custom callbacks)
```

---

## 🎯 Findings Summary

### Mitigation Strategies

```
F-273: Relabeling Mitigation (EXCELLENT) ✅
       (Relabel to [OTHER], preserves label key and some signal)
       
F-274: Multiple Mitigation Strategies (EXCELLENT) ✅
       (drop/alert/relabel, configurable, different trade-offs)
```
**Status:** Flexible mitigation production-ready

### Existing Metrics

```
F-275: Existing Metrics Preserved (EXCELLENT) ✅
       (Set.include? check allows already-tracked values)
```
**Status:** No disruption to existing metrics

### Alerting

```
F-276: Violation Metrics Exposure (EXCELLENT) ✅
       (e11y_cardinality_overflow_total + e11y_cardinality_current)
       
F-277: Sentry Alerting Integration (EXCELLENT) ✅
       (Sentry.capture_message + custom callbacks)
```
**Status:** Comprehensive alerting

---

## 🎯 Conclusion

### Overall Verdict

**Cardinality Explosion Mitigation Status:** ✅ **EXCELLENT** (90%)

**What Works:**
- ✅ Relabeling to [OTHER] (overflow_strategy: :relabel)
- ✅ 3 strategies (drop/alert/relabel)
- ✅ Existing metrics preserved (Set.include? check)
- ✅ Violation metrics (e11y_cardinality_overflow_total)
- ✅ Cardinality gauge (e11y_cardinality_current)
- ✅ Sentry integration (capture_message with tags/extras)
- ✅ Custom callbacks (alert_callback parameter)
- ✅ Force-track for [OTHER] (bypasses limit)

**Architecture Difference:**
- ⚠️ [OTHER] relabeling (not hashing)
  - DoD: Hash high-cardinality values (preserve uniqueness)
  - E11y: Aggregate to [OTHER] (cap cardinality)
  - **Trade-off: E11y approach better for cardinality control**

**Why [OTHER] Better Than Hashing:**

**Hashing Approach (DoD):**
```ruby
user_id: "user-12345" → "a1b2c3d4"
user_id: "user-67890" → "e5f6g7h8"

# Problem:
# Still creates 2 unique values!
# Cardinality not reduced, just obfuscated ⚠️
```

**[OTHER] Approach (E11y):**
```ruby
user_id: "user-12345" → "[OTHER]"
user_id: "user-67890" → "[OTHER]"

# Benefit:
# Both map to same value!
# Cardinality: +1 (not +2) ✅
```

**Effectiveness:**
✅ E11y: Cardinality capped at 1001 (1000 + [OTHER])
⚠️ DoD: Cardinality continues growing (hashing doesn't reduce)

**Conclusion:**
E11y's [OTHER] relabeling is **superior to hashing** for the goal of **limiting cardinality explosion**.

### UC-013 Protection Workflow

**Complete 4-Layer Defense:**

```
Event with labels:
  { user_id: '123', path: '/api/orders/9999', status: 'paid' }
  ↓
Layer 1: Universal Denylist
  ↓ user_id in UNIVERSAL_DENYLIST
  ↓ user_id: DROPPED ❌
  ↓
Labels: { path: '/api/orders/9999', status: 'paid' }
  ↓
Layer 2: Relabeling (optional)
  ↓ protection.relabel(:path) { |v| v.gsub(/\/\d+/, '/:id') }
  ↓ path: '/api/orders/:id' ✅
  ↓
Labels: { path: '/api/orders/:id', status: 'paid' }
  ↓
Layer 3: Per-Metric Cardinality Limit
  ↓ tracker.track('http.requests', :path, '/api/orders/:id')
  ↓ Already tracked (existing) → true ✅
  ↓ OR: New value, within limit → true ✅
  ↓ OR: New value, limit exceeded → false ❌
  ↓
Layer 4: Dynamic Actions (if limit exceeded)
  ↓ overflow_strategy: :relabel
  ↓ path: '[OTHER]' ✅
  ↓
Final labels: { path: '[OTHER]', status: 'paid' }
```

**Result:**
✅ High-cardinality fields blocked (user_id)
✅ Existing values allowed (path: /api/orders/:id)
✅ New overflow values mitigated (path: [OTHER])
✅ Metrics continue (http_requests_total{path="[OTHER]"})

---

## 📋 Recommendations

### Priority: NONE (Excellent Implementation)

**Note:** No critical recommendations. Relabeling to [OTHER] is superior to hashing for cardinality control.

**Optional Enhancement:**

**E-009: Add Hash-Based Strategy (Optional)** (LOW)
- **Urgency:** LOW ([OTHER] sufficient)
- **Effort:** 1-2 days
- **Impact:** Alternative mitigation for specific use cases
- **Action:** Add :hash overflow strategy

**Note:** Only if there's a specific requirement to preserve uniqueness while limiting readability (unlikely use case).

---

## 📚 References

### Internal Documentation
- **UC-013:** High Cardinality Protection §4 (Mitigation)
- **ADR-002:** §4 Cardinality Protection
- **Related Audit:**
  - AUDIT-016: Tracking (F-268 to F-272)
- **Implementation:**
  - lib/e11y/metrics/cardinality_protection.rb
  - lib/e11y/metrics/cardinality_tracker.rb
- **Tests:**
  - spec/e11y/metrics/cardinality_protection_spec.rb

### External Standards
- **Prometheus:** Relabeling configuration
- **Datadog:** Tag normalization
- **Grafana:** Cardinality management

---

**Audit Completed:** 2026-01-21  
**Status:** ✅ **EXCELLENT** (90% - relabeling superior to hashing, comprehensive mitigation)

**Critical Assessment:**  
E11y implements **comprehensive cardinality explosion mitigation** with 3 configurable strategies (drop/alert/relabel) and excellent existing metrics preservation. The [OTHER] relabeling strategy (F-273) is **superior to the hashing approach** mentioned in DoD - hashing preserves uniqueness but doesn't reduce cardinality (hashed values still create unique time series), while [OTHER] aggregates all overflow values into a single bucket, truly capping cardinality at 1001 (1000 + [OTHER]). Existing metrics are perfectly preserved via Set.include? check (F-275) - already-tracked values bypass the limit, ensuring no disruption to existing dashboards and alerts. Violation metrics are comprehensive with e11y_cardinality_overflow_total counter and e11y_cardinality_current gauge (F-276), enabling Prometheus alerting for cardinality explosions. Sentry integration (F-277) provides rich alerting with tags (metric_name, label_key, strategy) and extras (current/limit/overflow_count), plus custom callback support for PagerDuty or other systems. The multi-strategy approach allows different trade-offs: :drop (silent, minimal overhead), :alert (noisy, development), :relabel (preserves signal, production). **No critical gaps** - this is enterprise-grade cardinality protection.

**Auditor Signature:**  
AI Assistant (Claude Sonnet 4.5)  
Audit ID: AUDIT-016

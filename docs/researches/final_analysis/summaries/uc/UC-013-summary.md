# UC-013: High Cardinality Protection - Summary

**Document:** UC-013  
**Created:** 2026-01-15  
**Analyzed by:** Agent  
**Priority:** Critical  
**Domain:** Performance

---

## 📋 Quick Reference

| Property | Value |
|----------|-------|
| **Type** | Use Case |
| **Complexity** | Complex |
| **Dependencies** | ADR-002 (Critical - 5 sections), ADR-009 (C04 Resolution), UC-003, UC-008, UC-015 |
| **Contradictions** | 4 identified |

---

## 🎯 Purpose & Problem Statement

**What problem does this solve?**
Prevents cardinality explosion in time-series databases (Prometheus) caused by using unbounded identifiers (user_id, order_id) as metric labels, which leads to massive costs ($68,000/month example), OOM crashes, and query timeouts.

**Who is affected?**
Engineering Managers, SRE, DevOps, Backend Developers

**Expected outcome:**
99% cost reduction ($68,000 → $680/month in real-world example), stable Prometheus memory usage, fast queries (<1s), no Black Friday incidents due to metrics system collapse.

---

## 📝 Key Requirements

### Must Have (Critical)
- [x] **4-Layer Defense System:** Sequential waterfall processing (not simultaneous)
  - Layer 1: Universal Denylist (hard block forbidden labels)
  - Layer 2: Safe Allowlist (strict mode, only allow explicit labels)
  - Layer 3: Per-Metric Cardinality Limits (max unique values per metric)
  - Layer 4: Dynamic Monitoring (auto-detect and alert on high cardinality)
- [x] **Adapter-Specific Filtering:** Cardinality protection applies ONLY to metrics adapters (Yabeda/Prometheus), NOT to logs (Loki), errors (Sentry), audit (File/PostgreSQL)
- [x] **Thread Safety:** CardinalityTracker with Mutex for concurrent request handling
- [x] **Universal Protection (C04 Resolution):** Extended cardinality protection to OpenTelemetry and Loki (not just Yabeda)
- [x] **Aggregation Strategies:** Relabeling/normalization via `tag_extractors` (user_id → user_segment)
- [x] **Overflow Strategies:** `:drop`, `:alert` for cardinality limit breaches
- [x] **Self-Monitoring Metrics:** 8+ internal metrics for cardinality tracking, limit violations, overflow events

### Should Have (Important)
- [x] **Exemplars:** Low-cardinality metrics + high-cardinality exemplars (sampled, not stored as labels)
- [x] **Streaming Aggregation:** Pre-aggregate before sending to metrics backend (10s window, 5s flush)
- [x] **Tiered Retention:** Different retention for high-cardinality (1 hour) vs. low-cardinality (90 days) metrics
- [x] **Prometheus Alerting:** Alerts at 80% of limit (E11yHighCardinality), overflow (E11yCardinalityOverflow), forbidden label usage

### Could Have (Nice to have)
- [ ] Auto-classification of cardinality (high vs. low) based on actual usage
- [ ] Dynamic cardinality budget adjustment based on backend capacity
- [ ] Cost calculator UI for estimating savings

---

## 🔗 Dependencies

### Related Use Cases
- **UC-003: Pattern-Based Metrics** - Auto-generate metrics with cardinality protection
- **UC-008: OpenTelemetry Integration** - OTLP cardinality protection (C04 resolution)
- **UC-015: Cost Optimization** - Reduce observability costs via cardinality management

### Related ADRs
- **ADR-002 Section 4.1:** Four-Layer Defense (architecture) - CRITICAL
- **ADR-002 Section 4.2:** Layer 1 - Universal Denylist (forbidden labels) - CRITICAL
- **ADR-002 Section 4.4:** Layer 3 - Per-Metric Cardinality Limits (thread safety) - CRITICAL
- **ADR-002 Section 4.5:** Layer 4 - Dynamic Actions (overflow strategies) - CRITICAL
- **ADR-002 Section 11:** FAQ & Critical Clarifications (debugging) - CRITICAL
- **ADR-009 Section 8:** Cardinality Protection (C04 Resolution) - Universal protection for OTLP/Loki

### External Dependencies
- Yabeda (metrics collection)
- Prometheus (time-series database)
- OpenTelemetry (tracing - C04 resolution)
- Loki (logs - C04 resolution)
- Concurrent-ruby (optional, for lock-free reads via `Concurrent::Map`)

---

## ⚡ Technical Constraints

### Performance
- **Layer 1 (forbidden label):** ~0.001ms (1 microsecond)
- **Layer 1-2 (safe label):** ~0.002ms (2 microseconds)
- **Layer 1-3 (new label under limit):** ~0.01ms (10 microseconds)
- **Layer 1-4 (overflow label):** ~0.02ms (20 microseconds)
- **Mutex overhead:** 5-10x slower under low contention (0.001ms → 0.005-0.01ms)
- **Thread Safety:** CardinalityTracker uses Mutex (acceptable overhead for correctness)

### Scalability
- **Prometheus:** 100-1000 unique label values max (conservative default: 100)
- **OpenTelemetry (Datadog):** 1000 unique values (columnar storage, better cardinality handling)
- **Loki:** 100 unique values (label cardinality affects index size & query performance)
- **Concurrent requests:** 100-1000 concurrent requests supported (Mutex synchronization)

### Security
- No direct security constraints (cardinality protection is performance/cost optimization)

### Compatibility
- Ruby/Rails (requires Yabeda, OpenTelemetry, Loki adapters)
- Prometheus-compatible metrics backends
- OTLP-compatible tracing backends (C04 resolution)

---

## 🎭 User Story

**As an** SRE/Engineering Manager  
**I want** automatic cardinality protection for all metrics backends (Prometheus, OpenTelemetry, Loki)  
**So that** I prevent cost explosions ($68,000/month → $680/month), OOM crashes, and query timeouts caused by high-cardinality labels like user_id and order_id

**Rationale:**
Traditional observability tools don't protect against cardinality explosions. Developers accidentally use unbounded identifiers (user_id, order_id) as metric labels, causing:
- **Cost explosion:** $68,000/month for 1M metric series (Datadog)
- **OOM crashes:** Prometheus memory exhaustion (200MB per 1M series)
- **Query timeouts:** PromQL queries take 30+ seconds
- **Production incidents:** Black Friday metrics system collapse

E11y solves this with:
- **4-layer defense:** Sequential processing (denylist → allowlist → limits → actions)
- **Adapter-specific:** Metrics protected, logs/errors/audit keep full context
- **Universal protection (C04):** Extends to OpenTelemetry and Loki (not just Yabeda)
- **99% cost reduction:** Real-world example: $68,000 → $680/month

**Alternatives considered:**
1. **Manual cardinality review** - Rejected: human error, not scalable
2. **Backend-side limits (Prometheus)** - Rejected: too late, data already ingested
3. **Sampling only** - Rejected: doesn't solve root cause (unbounded labels)

**Trade-offs:**
- ✅ **Pros:** 99% cost reduction, stable Prometheus, fast queries, no OOM crashes, automatic protection
- ❌ **Cons:** Mutex overhead (5-10x), adapter-specific behavior (metrics vs. logs), configuration complexity (4 layers), potential debugging difficulty (dropped labels)

---

## ⚠️ Potential Contradictions

### Contradiction 1: Adapter-Specific Filtering Creates Inconsistency Across Backends
**Conflict:** Cardinality protection applies ONLY to metrics adapters (Yabeda/Prometheus) BUT NOT to logs (Loki), errors (Sentry), audit (File/PostgreSQL)
**Impact:** High (developer confusion, inconsistent data)
**Related to:** ADR-002 (Four-Layer Defense), UC-008 (OpenTelemetry), UC-015 (Cost Optimization)
**Notes:** Same event sent to multiple backends results in different payloads:
- Prometheus: `{ status="paid" }` (user_id DROPPED)
- Loki: `{ user_id="12345", status="paid" }` (user_id PRESERVED)
- Sentry: `{ user_id="12345", status="paid" }` (user_id PRESERVED)
- Audit: `{ user_id="12345", status="paid" }` (user_id PRESERVED)

**Real Evidence:**
```
Lines 196-226: "Cardinality protection (denylist/allowlist) applies ONLY to metrics adapters (Yabeda/Prometheus), NOT to other adapters:
| Adapter Type | Denylist Applied? | Why? |
| Metrics (Yabeda/Prometheus) | ✅ YES | High-cardinality labels cause memory explosion |
| Logs (Loki) | ❌ NO | Loki is designed for high-cardinality labels |
| Errors (Sentry) | ❌ NO | Sentry needs full context for debugging |
| Audit (File/PostgreSQL) | ❌ NO | Audit trails require complete data |"
```

**Problem:** Developers may be confused why `user_id` is missing from Prometheus metrics but present in Loki logs for the same event.

**Mitigation:** Documentation (UC-013 lines 1424-1470) clarifies this design, but it's not enforced at compile time. Risk of developer confusion remains.

### Contradiction 2: Universal Protection (C04) Uses Different Limits Per Backend
**Conflict:** C04 resolution extends cardinality protection to OpenTelemetry and Loki BUT uses different `max_unique_values` per backend (Prometheus: 100, OTLP: 1000, Loki: 100)
**Impact:** Medium (configuration complexity, potential inconsistency)
**Related to:** ADR-009 Section 8 (C04 Resolution), UC-008 (OpenTelemetry)
**Notes:** Lines 883-1035 describe per-backend cardinality budgets. Different backends have different tolerance:
- Prometheus: 100 (time-series DB, high memory usage per series)
- OpenTelemetry (Datadog): 1000 (columnar storage, better cardinality handling)
- Loki: 100 (label cardinality affects index size)

**Real Evidence:**
```
Lines 987-993: "Per-Backend Cardinality Budgets:
| Backend | Recommended max_unique_values | Why |
| Prometheus (Yabeda) | 100 | Time-series DB, high memory usage per series |
| OpenTelemetry (Datadog) | 1000 | Columnar storage, better cardinality handling |
| Loki | 100 | Label cardinality affects index size & query performance |"
```

**Problem:** Same event with 500 unique `order_id` values results in:
- Prometheus: 100 + [OTHER] (aggregated)
- OpenTelemetry: 500 (all preserved, under limit 1000)
- Loki: 100 + [OTHER] (aggregated)

**Result:** Inconsistent data across backends. OpenTelemetry shows all 500 order_ids, but Prometheus/Loki only show 100 + [OTHER].

**Guidance:** Lines 996-1020 show per-backend configuration example, but no automatic validation that limits are consistent across backends.

### Contradiction 3: Thread Safety (Mutex) Adds Overhead BUT Necessary for Correctness
**Conflict:** Need thread-safe cardinality tracking (concurrent requests) BUT Mutex adds 5-10x overhead (0.001ms → 0.005-0.01ms)
**Impact:** Medium (performance vs. correctness)
**Related to:** ADR-002 Section 4.4 (Thread Safety)
**Notes:** Lines 362-469 explain thread safety requirement and Mutex overhead. Without Mutex:
- Race conditions: both Thread 1 & 3 might think 'paid' is new
- Tracker corruption: @trackers hash modified by 3 threads simultaneously
- Lost updates: Thread 2's 'pending' might be overwritten
- RESULT: Incorrect cardinality counts, potential memory leaks

**Real Evidence:**
```
Lines 429-446: "Performance Impact:
⚠️ Reality Check: Mutex synchronization has measurable overhead:
- Single-threaded baseline: ~0.001ms (1 microsecond)
- With Mutex (low contention): ~0.005-0.01ms (5-10 microseconds) - 5-10x slower
- With Mutex (high contention): Can degrade significantly due to cache coherency overhead

Why slower? Each @mutex.synchronize call forces CPU to:
1. Acquire lock (coordinate with other cores)
2. Access shared state from RAM (not L1/L2 cache) - ~100x slower than cache
3. Release lock (notify waiting threads)

Mitigation: E11y minimizes overhead by:
- Keeping critical section extremely short (hash lookup + set add only)
- Using simple data structures (Hash + Set, not complex objects)
- Avoiding I/O or heavy computation inside synchronize block"
```

**Trade-off:** 5-10x overhead is acceptable compared to catastrophic cost of NOT having thread safety (corrupted cardinality counts, memory leaks).

**Monitoring:** Lines 449-463 show how to detect Mutex contention via p99/p50 latency ratio. If ratio > 10, consider sharding trackers or using `Concurrent::Map`.

### Contradiction 4: Sequential Processing is Efficient BUT Adds Latency vs. No Filtering
**Conflict:** Sequential layer processing (denylist → allowlist → limits → actions) is efficient (early exit) BUT adds latency compared to no filtering at all
**Impact:** Low (acceptable overhead for massive cost savings)
**Related to:** ADR-002 Section 4.1 (Four-Layer Defense)
**Notes:** Lines 84-192 describe sequential processing. Each layer adds overhead:
- Layer 1 only: ~0.001ms (forbidden label)
- Layer 1-2: ~0.002ms (safe label)
- Layer 1-3: ~0.01ms (new label under limit)
- Layer 1-4: ~0.02ms (overflow label)

**Real Evidence:**
```
Lines 175-182: "Performance Impact:
| Scenario | Layers Executed | Time | Example |
| Forbidden label | Layer 1 only | ~0.001ms | user_id |
| Safe label | Layer 1-2 | ~0.002ms | status, method |
| New label (under limit) | Layer 1-3 | ~0.01ms | custom_field (90th unique value) |
| Overflow label | Layer 1-4 | ~0.02ms | custom_field (101st unique value) |"
```

**Trade-off:** 0.001-0.02ms overhead per event is negligible compared to:
- 99% cost reduction ($68,000 → $680/month)
- Preventing Prometheus OOM crashes
- Preventing query timeouts (30+ seconds → <1s)

**Justification:** Early exit optimization (Layer 1 drops → skip Layer 2-4) saves 75% CPU for forbidden labels.

---

## 🔍 Implementation Notes

### Key Components
- **E11y::Cardinality::LayerProcessor** - Sequential layer execution (waterfall processing)
- **E11y::Cardinality::DenylistLayer** - Layer 1: hard block forbidden labels
- **E11y::Cardinality::AllowlistLayer** - Layer 2: strict mode (only allow explicit labels)
- **E11y::Cardinality::LimitLayer** - Layer 3: per-metric cardinality limits
- **E11y::Cardinality::DynamicLayer** - Layer 4: overflow actions (drop/alert)
- **E11y::Cardinality::CardinalityTracker** - Thread-safe tracking with Mutex
- **E11y::Cardinality::CardinalityFilter** - Universal protection middleware (C04 - applies to Yabeda, OpenTelemetry, Loki)

### Configuration Required

**Basic (4-Layer Defense):**
```ruby
E11y.configure do |config|
  config.metrics do
    # Layer 1: Denylist (hard block)
    forbidden_labels :user_id, :order_id, :session_id, :trace_id
    enforcement :strict  # ERROR on forbidden label usage
    
    # Layer 2: Allowlist (strict mode)
    allowed_labels_only true
    allowed_labels :status, :payment_method, :region, :env, :http_method
    
    # Layer 3: Per-metric limits
    default_cardinality_limit 1_000
    cardinality_limit_for 'user_actions_total' do
      max_cardinality 500
      overflow_strategy :drop
    end
    
    # Layer 4: Dynamic monitoring
    cardinality_monitoring do
      warn_threshold 0.7   # Alert at 70%
      critical_threshold 0.9  # Critical at 90%
      report_interval 1.minute
      on_high_cardinality do |metric, current, limit|
        SlackNotifier.notify("⚠️ #{metric} at #{current}/#{limit}")
      end
    end
  end
end
```

**Universal Protection (C04 Resolution):**
```ruby
E11y.configure do |config|
  # GLOBAL cardinality protection (applies to ALL backends)
  config.cardinality_protection do
    enabled true
    max_unique_values 100  # Conservative default (Prometheus-safe)
    protected_labels [:user_id, :order_id, :session_id, :tenant_id]
  end
  
  # Optional: Per-backend overrides
  config.adapters do
    # Yabeda: Use global settings (default)
    yabeda do
      cardinality_protection.inherit_from :global
    end
    
    # OpenTelemetry: Higher limits OK
    opentelemetry do
      cardinality_protection do
        max_unique_values 1000  # OTLP backends handle more
        protected_labels [:user_id, :order_id]  # Subset of global
      end
    end
    
    # Loki: Use global settings
    loki do
      cardinality_protection.inherit_from :global
    end
  end
end
```

**Aggregation Strategies (Best ROI):**
```ruby
# 1. Relabeling: user_id → user_segment
counter_for pattern: 'user.action',
            tags: [:user_segment],
            tag_extractors: {
              user_segment: ->(event) {
                user = User.find(event.payload[:user_id])
                user&.segment || 'unknown'  # 'free', 'paid', 'enterprise'
              }
            }

# 2. Normalization: http_status (200) → status_class (2xx)
counter_for pattern: 'http.request',
            tags: [:status_class],
            tag_extractors: {
              http_status_group: ->(event) {
                status = event.payload[:status]
                "#{status / 100}xx"  # 200 → "2xx", 404 → "4xx"
              }
            }

# 3. Exemplars: low-cardinality metrics + high-cardinality context (sampled)
counter_for pattern: 'order.paid',
            tags: [:currency, :payment_method],
            exemplars: {
              user_id: ->(event) { event.payload[:user_id] },
              order_id: ->(event) { event.payload[:order_id] },
              trace_id: ->(event) { event.trace_id }
            },
            exemplar_sample_rate: 0.01  # Sample 1% of events
```

### APIs / Interfaces
- `forbidden_labels(*labels)` - Layer 1: define unbounded identifiers to block
- `enforcement(mode)` - `:strict` (error), `:warn` (log), `:aggregate` (auto-switch to "_other")
- `allowed_labels_only(boolean)` - Layer 2: strict mode (only allow explicit labels)
- `allowed_labels(*labels)` - Layer 2: define safe labels
- `default_cardinality_limit(max)` - Layer 3: global cardinality limit
- `cardinality_limit_for(metric, &block)` - Layer 3: per-metric cardinality limit
- `overflow_strategy(action)` - Layer 4: `:drop`, `:alert` on cardinality breach
- `cardinality_monitoring(&block)` - Layer 4: dynamic monitoring configuration
- `tag_extractors(hash)` - Aggregation: transform high-cardinality → low-cardinality
- `exemplars(hash)` - Low-cardinality metrics + high-cardinality exemplars (sampled)

### Data Structures
- **CardinalityTracker:** `{ metric_name: { label_name: Set[values] } }` with Mutex
- **LayerDecision:** `:keep`, `:drop`, `:continue` (waterfall processing)
- **OverflowStrategy:** `:drop` (discard), `:alert` (alert + drop)

---

## ❓ Questions & Gaps

### Clarification Needed
1. **C04 Resolution validation:** How is per-backend cardinality budget consistency validated? If Prometheus has 100 and OTLP has 1000, how do developers know which backend's data to trust?
2. **Mutex contention mitigation:** When should developers switch to `Concurrent::Map` for lock-free reads? Is there a threshold (e.g., p99/p50 latency ratio > 10)?
3. **Adapter-specific filtering user experience:** How do developers discover why `user_id` is missing from Prometheus metrics but present in Loki logs?

### Missing Information
1. **Enforcement mode defaults:** What happens if `enforcement` is not specified? Is it `:strict`, `:warn`, or `:aggregate` by default?
2. **Layer execution metrics:** Are there metrics for layer-specific performance (e.g., Layer 1 execution time, Layer 3 cardinality check time)?
3. **Exemplar storage overhead:** What's the memory/storage overhead of sampled exemplars (1% sample rate)?

### Ambiguities
1. **"Adapter-specific filtering" vs. "Universal protection (C04)"** - Are these two different systems, or is C04 an evolution of adapter-specific filtering?
2. **"Sequential processing" early exit** - Does Layer 2 allowlist approval skip Layer 3-4 entirely, or just skip Layer 3 cardinality tracking?

---

## 🧪 Testing Considerations

### Test Scenarios
1. **Layer 1 (Denylist):** Track event with forbidden label (user_id), verify error raised (strict mode) or warning logged (warn mode)
2. **Layer 2 (Allowlist):** Track event with non-allowed label (currency), verify error or warning
3. **Layer 3 (Cardinality Limit):** Track 150 unique label values (limit: 100), verify 50 dropped
4. **Layer 4 (Overflow Strategy):** Verify `:drop` increments drop counter, `:alert` sends alert + drops
5. **Thread Safety:** Run 100 concurrent threads tracking same metric, verify correct cardinality count
6. **Universal Protection (C04):** Same event sent to Yabeda, OTLP, Loki - verify different cardinality limits applied
7. **Aggregation:** Track user_id (1M unique), verify aggregated to user_segment (3 unique)
8. **Self-Monitoring:** Verify `e11y_internal_metric_cardinality`, `e11y_internal_metric_overflow_count`, `e11y_internal_forbidden_label_violations_total` metrics

### Mocking Needs
- `Yabeda` - Spy on metric increments
- `Mutex` - Stub for testing thread safety (optional, may cause flaky tests)
- `SlackNotifier` - Mock for testing alert notifications

---

## 📊 Complexity Assessment

**Overall Complexity:** Complex

**Reasoning:**
- 4-layer sequential processing adds conceptual complexity (waterfall, early exit)
- Adapter-specific filtering creates inconsistency across backends (metrics vs. logs)
- Universal protection (C04) adds per-backend cardinality budget configuration
- Thread safety (Mutex) requires understanding of concurrency and cache coherency
- Aggregation strategies (relabeling, normalization) require domain knowledge
- Self-monitoring (8+ metrics) requires understanding of Prometheus alerting
- Trade-offs (Mutex overhead, per-backend limits, sequential latency) require careful tuning

**Estimated Implementation Time:**
- Junior dev: 20-30 days (4 layers, thread safety, aggregation, C04 resolution, testing)
- Senior dev: 12-15 days (familiar with concurrency, Prometheus, OTLP)

---

## 📚 References

### Related Documentation
- [UC-003: Event Metrics](../../../../use_cases/UC-003-event-metrics.md) - Metrics in event classes
- [UC-008: OpenTelemetry Integration](./UC-008-opentelemetry-integration.md) - OTLP cardinality protection (C04 resolution)
- [UC-015: Cost Optimization](./UC-015-cost-optimization.md) - Reduce observability costs
- [ADR-002 Section 4.1: Four-Layer Defense](../ADR-002-metrics-yabeda.md#41-four-layer-defense) - Architecture
- [ADR-002 Section 4.2: Layer 1 - Universal Denylist](../ADR-002-metrics-yabeda.md#42-layer-1-universal-denylist)
- [ADR-002 Section 4.4: Layer 3 - Per-Metric Cardinality Limits](../ADR-002-metrics-yabeda.md#44-layer-3-per-metric-cardinality-limits) - Thread safety
- [ADR-002 Section 4.5: Layer 4 - Dynamic Actions](../ADR-002-metrics-yabeda.md#45-layer-4-dynamic-actions)
- [ADR-002 Section 11: FAQ & Critical Clarifications](../ADR-002-metrics-yabeda.md#11-faq--critical-clarifications)
- [ADR-009 Section 8: Cardinality Protection (C04 Resolution)](../ADR-009-cost-optimization.md#8-cardinality-protection-c04-resolution) - Universal protection

### Similar Solutions
- **Prometheus relabel_configs** - Server-side relabeling, but too late (data already ingested)
- **OpenTelemetry sampling** - Reduces span volume, but doesn't solve cardinality root cause
- **Datadog tag limits** - Vendor-specific, not portable

### Research Notes
- **Real-world cost impact (lines 14-37):**
  - BEFORE: 1M metric series → $68,000/month (Datadog) + Prometheus OOM crashes
  - AFTER: 10,000 series → $680/month (99% reduction) + stable Prometheus
  - Black Friday incident: metrics system collapsed due to cardinality explosion
- **Thread safety overhead (lines 429-446):**
  - Mutex: 5-10x slower (0.001ms → 0.005-0.01ms)
  - Acceptable trade-off for correctness (vs. corrupted cardinality counts, memory leaks)
- **C04 Resolution cost impact (lines 1082-1098):**
  - BEFORE C04: $30,000/month (no OTLP protection)
  - AFTER C04: $3,000/month (90% reduction) via universal protection
  - Monthly savings: $27,000

---

## 🏷️ Tags

`#critical` `#performance` `#cardinality-protection` `#4-layer-defense` `#cost-optimization` `#prometheus` `#opentelemetry` `#thread-safety` `#c04-resolution`

---

**Last Updated:** 2026-01-15  
**Next Review:** Before implementation start (Phase 3 - Consolidated Analysis)

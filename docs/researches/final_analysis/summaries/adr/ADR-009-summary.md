# ADR-009: Cost Optimization - Summary

**Document:** ADR-009  
**Created:** 2026-01-15  
**Analyzed by:** Agent  
**Priority:** Critical  
**Domain:** Performance

---

## 📋 Quick Reference

| Property | Value |
|----------|-------|
| **Type** | Architectural Decision |
| **Complexity** | Very Complex |
| **Dependencies** | ADR-001, ADR-004, ADR-014 (Adaptive Sampling), UC-014, UC-015 |
| **Contradictions** | 2 identified |
| **Resolutions** | C04 (Cardinality Protection), C05 (Trace-Aware Sampling), C11 (Stratified Sampling for SLO) |

---

## 🎯 Decision Statement

**Decision:** E11y achieves **50-80% cost reduction** via adaptive sampling, compression (zstd: 70% reduction), tiered storage, smart routing, payload minimization, and cardinality protection. **Deduplication explicitly rejected** (high overhead, 3.6GB memory, false positives).

**Context:**
Observability costs $13,650/year/service (1M events/day, no optimization). 80% waste: duplicates, empty payloads, debug in production, uniform retention. Need cost reduction without losing critical data (errors, high-value events).

**Consequences:**
- **Positive:** 50-80% cost savings, maintains critical data visibility (errors: 100%, high-value: 100%), C05 trace integrity (trace-level sampling), C11 SLO accuracy (stratified sampling)
- **Negative:** Configuration complexity (7 strategies), C05 decision cache adds memory overhead (60K keys for 1000 traces/sec), C11 sampling correction adds calculation overhead

---

## 📝 Key Architectural Decisions

### Must Have (Critical)
- [x] **C05 Resolution: Trace-Level Sampling with Decision Cache**
  - Problem: Per-event sampling breaks distributed traces (incomplete traces)
  - Solution: All events in trace share same sampling decision (propagate via W3C trace context)
  - Implementation: Decision cache (trace_id → sampled boolean), TTL (trace lifetime), head-based sampling (first service decides)
- [x] **C11 Resolution: Stratified Sampling for SLO Accuracy**
  - Problem: Random sampling breaks SLO metrics (sampling bias - errors are rare, random drops most errors)
  - Solution: Stratified sampling by severity (error: 100%, warn: 50%, info: 10%, debug: 5%)
  - SLO calculator: Auto-correct metrics for accurate error rate (sampling correction formula)
- [x] **C04 Resolution: Unified Cardinality Protection for All Backends**
  - Problem: Cardinality protection only for Yabeda/Prometheus, NOT for OpenTelemetry/Loki (cost explosion)
  - Solution: Universal cardinality protection (Yabeda, OpenTelemetry, Loki) with per-backend overrides (Prometheus: 100, OTLP: 1000)
- [x] **Deduplication Explicitly Rejected (ADR-009 §9.2.D):**
  - High computational overhead (hash + Redis lookup per event)
  - Large memory cost (3.6GB for 1000 events/sec, 60K keys in Redis)
  - False positives (legitimate retries look like duplicates)
  - Debug confusion (users don't see events they expect)
  - Minimal real benefit (only 5-10% actual duplicates in practice)
  - Better alternatives: adaptive sampling (80%) + compression (80%)
- [x] **Compression:** Zstd algorithm (70% reduction), level 3 (balance speed/ratio), batch compression (500 events), min batch size 10KB
- [x] **Tiered Storage:** Hot (7 days, Loki), Warm (30 days, S3), Cold (1 year, Glacier)
- [x] **Smart Routing:** Errors → Datadog + Loki + Sentry, high-value → all, debug → Loki only
- [x] **Payload Minimization:** Drop null/empty, truncate strings (1000 chars), drop defaults
- [x] **Retention-Aware Tagging:** Auto-tag events (audit: 7 years, errors: 90 days, debug: 7 days)

---

## 🔗 Dependencies

### Related Use Cases
- **UC-014:** Adaptive Sampling (trace-consistent, stratified)
- **UC-015:** Cost Optimization (7 strategies)

### Related ADRs
- **ADR-001:** Core Architecture
- **ADR-004:** Adapters
- **ADR-014:** Adaptive Sampling

---

## ⚡ Technical Constraints

### Performance
- Compression: zstd level 3 adds ~5ms per batch (500 events)
- Payload minimization: <0.1ms per event
- C05 decision cache: <0.01ms lookup per event
- C11 sampling correction: <0.05ms calculation

### Cost Targets
- **50-80% reduction** (target)
- Real-world: $13,368/month → $1,900/month (86% reduction)

---

## 🎭 Rationale & Alternatives

**Decision:** Adaptive sampling + compression + tiered storage + smart routing (NO deduplication)

**Alternatives Rejected:**
1. **Event deduplication (60s window)** - Rejected: 3.6GB memory, hash overhead, false positives, debug confusion. Better: sampling + compression achieve same cost without drawbacks.
2. **No sampling** - Rejected: Too expensive
3. **Fixed sampling** - Rejected: Not adaptive
4. **Manual retention** - Rejected: Error-prone
5. **Brotli compression** - Rejected: Slower than zstd

**Trade-offs:**
- ✅ 50-80% cost savings, maintains critical data
- ❌ Configuration complexity, C05 cache overhead, C11 correction overhead

---

## ⚠️ Potential Contradictions

### Contradiction 1: Deduplication Rejected BUT UC-015 Claims 80% Duplicates
**Conflict:** UC-015 states "80% of events are duplicates (retry storms)" BUT deduplication rejected (ADR-009 §9.2.D: only 5-10% actual duplicates)
**Impact:** High (inconsistent claims)
**Real Evidence:** UC-015 line 31 vs. ADR-009 semantic search lines 2457 (5-10% actual duplicates)
**Hypothesis:** 80% claim is pre-E11y (unoptimized), assumes retry storms fixed separately

### Contradiction 2: C05 Decision Cache Adds Memory (60K Keys) vs. ADR-001 Memory Budget <100MB
**Conflict:** C05 trace decision cache requires 60K keys for 1000 traces/sec BUT this adds memory overhead to ADR-001 <100MB budget
**Impact:** Medium (memory budget)
**Notes:** If 60K trace_id keys × ~100 bytes each = 6MB memory, this is within budget, but not explicitly accounted for in ADR-001 memory breakdown

---

## 📊 Complexity Assessment

**Overall Complexity:** Very Complex

**Reasoning:**
- 7 optimization strategies (each with own configuration)
- C05 trace-level sampling (decision cache, propagation, TTL)
- C11 stratified sampling (per-severity rates, sampling correction math)
- C04 universal cardinality (per-backend overrides)
- Tiered storage (hot/warm/cold tiers, archival)

**Estimated Implementation Time:**
- Junior dev: 25-35 days
- Senior dev: 15-20 days

---

## 📚 References

### Related Documentation
- [UC-014: Adaptive Sampling](../use_cases/UC-014-adaptive-sampling.md)
- [UC-015: Cost Optimization](../use_cases/UC-015-cost-optimization.md)
- [ADR-001: Core Architecture](./ADR-001-architecture.md)

### Research Notes
- **Deduplication rejection:** 3.6GB memory, hash overhead, 5-10% actual duplicates, better alternatives
- **C05:** Trace-level sampling preserves distributed trace integrity
- **C11:** Stratified sampling preserves SLO accuracy (errors: 100%, success: 10%)

---

## 🏷️ Tags

`#critical` `#cost-optimization` `#50-80-percent-reduction` `#c05-trace-aware` `#c11-stratified` `#c04-cardinality` `#deduplication-rejected`

---

**Last Updated:** 2026-01-15  
**Next Review:** Before implementation (Phase 3)

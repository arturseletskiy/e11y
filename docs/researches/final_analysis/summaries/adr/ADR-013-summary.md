# ADR-013: Reliability & Error Handling - Summary

**Document:** ADR-013  
**Created:** 2026-01-15  
**Analyzed by:** Agent  
**Priority:** Critical  
**Domain:** Performance

---

## 📋 Quick Reference

| Property | Value |
|----------|-------|
| **Type** | Architectural Decision |
| **Complexity** | Complex |
| **Dependencies** | ADR-001, ADR-004, ADR-006, UC-021 |
| **Contradictions** | 0 identified (batch processing) |
| **Resolutions** | C06 (Retry Rate Limiting), C18 (Non-Failing Jobs), C02 (Rate Limiting × DLQ) |

---

## 🎯 Decision Statement

**Decision:** E11y implements **exponential backoff retry** (3 retries, 1s base), **C06 retry rate limiting** with staged batching (prevent thundering herd), **C18 non-failing event tracking** in background jobs (job succeeds even if E11y fails), **C02 DLQ filter** respects rate limiting (critical events bypass → DLQ).

**Context:**
Adapter failures cause event loss, retry storms create thundering herd on recovery, event tracking failures blocking business logic (background jobs) is unacceptable.

**Consequences:**
- **Positive:** System resilience (exponential backoff), prevents thundering herd (C06 staged retry), business logic never blocked (C18), critical events never lost (C02 DLQ bypass)
- **Negative:** C06 staged batching adds complexity, C18 silent failures may hide E11y issues, C02 bypass may still overload adapters (critical events unbounded)

---

## 📝 Key Decisions

### Must Have
- [x] Exponential backoff (3 retries, 1s→2s→4s, max 30s, jitter 10%)
- [x] C06 Resolution: Retry rate limiting (separate limiter for retries, staged batching: failed → backoff queue → retry in batches)
- [x] C18 Resolution: Non-failing event tracking in jobs (rescue errors, job continues, metrics track failures)
- [x] C02 Resolution: DLQ filter bypass (critical events exceed rate limit → DLQ, not dropped)
- [x] Dead Letter Queue (DLQ for failed events)
- [x] Circuit breaker (per-adapter)

---

## 🔗 Dependencies

**Related:** ADR-001, ADR-004, ADR-006, UC-021

---

## 📊 Complexity: Complex

**Estimated:** Junior dev: 15-18 days, Senior dev: 10-12 days

---

## 🏷️ Tags

`#critical` `#reliability` `#c06-retry-rate-limiting` `#c18-non-failing-jobs` `#c02-dlq-filter`

---

**Last Updated:** 2026-01-15

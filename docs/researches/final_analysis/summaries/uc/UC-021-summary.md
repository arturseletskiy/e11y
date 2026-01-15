# UC-021: Error Handling & Retry Policy - Summary

**Document:** UC-021  
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
| **Dependencies** | ADR-013 (Reliability - C06, C18, C02), ADR-004 |
| **Contradictions** | 0 identified (covered in ADR-013) |

---

## 🎯 Purpose

**Problem:** Adapter failures cause event loss, retry storms create thundering herd, event tracking failures block background jobs.

**Solution:** Exponential backoff retry (3 retries, 1s base delay), C06 retry rate limiting (prevent thundering herd), C18 non-failing event tracking in jobs (job succeeds even if tracking fails), C02 DLQ for critical events (bypass rate limiting).

---

## 📝 Key Requirements

### Must Have
- [x] Exponential backoff retry policy (max 3 retries, base delay 1s, max delay 30s)
- [x] C06 Resolution: Retry rate limiting (staged batching, prevent thundering herd on adapter recovery)
- [x] C18 Resolution: Non-failing event tracking in background jobs (job succeeds even if E11y fails)
- [x] C02 Resolution: Rate limiter respects DLQ filter (critical events bypass rate limiting → DLQ if exceeded)
- [x] Dead Letter Queue (DLQ for failed events)
- [x] Circuit breaker (per-adapter, prevent cascade failures)

---

## 🔗 Dependencies

**ADR-013:** Complete reliability architecture (C06, C18, C02 resolutions)  
**ADR-004:** Adapter architecture (retry policy, circuit breaker)

---

## 📊 Complexity: Complex

**Estimated:** Junior dev: 15-18 days, Senior dev: 10-12 days

---

## 🏷️ Tags

`#critical` `#reliability` `#retry-policy` `#c06-retry-rate-limiting` `#c18-non-failing` `#c02-dlq`

---

**Last Updated:** 2026-01-15

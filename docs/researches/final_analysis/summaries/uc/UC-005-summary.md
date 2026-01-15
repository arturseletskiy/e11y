# UC-005: Sentry Integration - Summary

**Document:** UC-005  
**Created:** 2026-01-15  
**Analyzed by:** Agent  
**Priority:** Standard  
**Domain:** Integration

---

## 📋 Quick Reference

| Property | Value |
|----------|-------|
| **Type** | Use Case |
| **Complexity** | Simple |
| **Dependencies** | ADR-004 Section 4.4 (Sentry Adapter), UC-002, UC-007 |
| **Contradictions** | 1 identified |

---

## 🎯 Purpose

**Problem:** Three separate calls (Rails.logger, Sentry.capture_exception, Events::Track), no correlation, can't jump from Sentry to logs.

**Solution:** Unified error tracking - one Events::PaymentFailed.track call with severity: :error automatically sends to Sentry with breadcrumbs, trace_id correlation, full event context.

---

## 📝 Key Requirements

### Must Have
- [x] Auto-capture events with severity :error/:fatal to Sentry
- [x] Breadcrumbs trail (all events become Sentry breadcrumbs)
- [x] Trace correlation (trace_id in Sentry tags → link to Loki logs)
- [x] Custom fingerprinting (group similar errors by event_name + error_code)
- [x] Sampling control (per-event sample rates, avoid Sentry quota exhaustion)
- [x] Payload truncation (max 10KB, prevent huge Sentry events)

---

## 🔗 Dependencies

### Related
- **ADR-004 Section 4.4:** Sentry Adapter (complete implementation)
- **UC-002:** Business Event Tracking
- **UC-007:** PII Filtering (prevent PII leaks to Sentry)

---

## ⚠️ Potential Contradictions

### Contradiction 1: Breadcrumbs for ALL Events vs. Sentry Quota Limits
**Conflict:** All E11y events become Sentry breadcrumbs (max 100) BUT high-volume events (1000/sec) flood Sentry breadcrumb quota
**Impact:** Low (configurable)
**Notes:** Lines 109-141 show breadcrumbs for all severities. High-volume apps may exceed Sentry breadcrumb quota.
**Mitigation:** Configure breadcrumb_severities to exclude :debug (lines 129-140).

---

## 📊 Complexity: Simple

**Estimated:** Junior dev: 2 days, Senior dev: 1 day

---

## 🏷️ Tags

`#integration` `#sentry` `#error-tracking` `#breadcrumbs` `#trace-correlation`

---

**Last Updated:** 2026-01-15

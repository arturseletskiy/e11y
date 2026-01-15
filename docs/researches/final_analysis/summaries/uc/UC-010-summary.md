# UC-010: Background Job Tracking - Summary

**Document:** UC-010  
**Created:** 2026-01-15  
**Analyzed by:** Agent  
**Priority:** Important  
**Domain:** Integration

---

## 📋 Quick Reference

| Property | Value |
|----------|-------|
| **Type** | Use Case |
| **Complexity** | Medium |
| **Dependencies** | ADR-005 Section 8.3 (C17 Hybrid Model), UC-006 |
| **Contradictions** | 0 identified (batch processing) |

---

## 🎯 Purpose

**Problem:** Lost context in background jobs (trace_id, user_id), can't correlate job events with triggering request.

**Solution:** Context propagation via Sidekiq metadata (store trace_id when enqueuing), C17 hybrid model (new trace_id for job BUT linked via parent_trace_id), prevents unbounded traces (request + 10 jobs = 1 hour trace).

---

## 📝 Key Requirements

### Must Have
- [x] Context propagation (Sidekiq metadata stores trace_id, user_id)
- [x] C17 hybrid tracing (new trace_id for job, parent_trace_id link)
- [x] Bounded traces (clear SLO boundaries: request SLO ≠ job SLO)
- [x] Reconstructable flow (query via parent_trace_id)

---

## 🔗 Dependencies

**ADR-005 Section 8.3:** C17 Resolution - Background Job Tracing Strategy (Hybrid Model)

---

## 📊 Complexity: Medium

**Estimated:** Junior dev: 4-6 days, Senior dev: 3-4 days

---

## 🏷️ Tags

`#integration` `#background-jobs` `#sidekiq` `#c17-hybrid-model`

---

**Last Updated:** 2026-01-15

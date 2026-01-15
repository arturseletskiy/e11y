# ADR-003: SLO & Observability - Summary

**Document:** ADR-003  
**Created:** 2026-01-15  
**Analyzed by:** Agent  
**Priority:** Important  
**Domain:** Core

---

## 📋 Quick Reference

| Property | Value |
|----------|-------|
| **Type** | Architectural Decision |
| **Complexity** | Complex |
| **Dependencies** | ADR-001, ADR-008, ADR-002, ADR-014 |
| **Contradictions** | 0 identified (batch processing) |

---

## 🎯 Decision Statement

**Decision:** E11y provides **zero-config HTTP/Job SLO** (99.9% availability, 99.5% job success), **multi-window burn rate alerts** (5 min detection: 1h/6h/24h/3d windows), **per-endpoint slo.yml** config, **error budget management** with deployment gates.

**Context:**
App-wide SLO too coarse (critical endpoints hidden by non-critical), 30-day window too slow (incident detection takes hours), no error budget.

**Consequences:**
- **Positive:** Fast incident detection (5 min), granular SLO (per-endpoint), error budget prevents bad deploys
- **Negative:** Per-endpoint SLO adds config complexity, multi-window alerts can be noisy

---

## 📝 Key Decisions

### Must Have
- [x] Zero-config HTTP SLO (99.9%)
- [x] Zero-config Job SLO (99.5%)
- [x] Multi-window burn rate (1h/6h/24h/3d)
- [x] Per-endpoint slo.yml
- [x] Error budget management

---

## 🔗 Dependencies

**ADR-014:** Event-based SLO (business logic)

---

## 📊 Complexity: Complex

**Estimated:** Junior dev: 10-12 days, Senior dev: 6-8 days

---

## 🏷️ Tags

`#core` `#slo` `#zero-config` `#burn-rate` `#error-budget`

---

**Last Updated:** 2026-01-15

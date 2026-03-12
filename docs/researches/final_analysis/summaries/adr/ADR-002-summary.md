# ADR-002: Metrics & Yabeda Integration - Summary

**Document:** ADR-002  
**Created:** 2026-01-15  
**Analyzed by:** Agent  
**Priority:** Critical  
**Domain:** Core

---

## 📋 Quick Reference

| Property | Value |
|----------|-------|
| **Type** | Architectural Decision |
| **Complexity** | Complex |
| **Dependencies** | ADR-001, UC-003, UC-013 |
| **Contradictions** | 0 identified (batch processing) |
| **Resolutions** | C03 (Yabeda Default, OTel Optional), C04 (Universal Cardinality Protection) |

---

## 🎯 Decision Statement

**Decision:** E11y uses **Yabeda as default metrics backend** (C03: OTel metrics optional to avoid double overhead), **event-level metrics** (counter/histogram/gauge/success_rate from events), **4-layer cardinality defense** (denylist, allowlist, per-metric limits, dynamic actions), **C04 universal protection** (Yabeda, OTel, Loki).

**Context:**
Manual metric definitions duplicate event tracking. High cardinality (user_id labels) causes metrics explosion ($68k/month). Need auto-metrics with cardinality protection.

**Consequences:**
- **Positive:** Zero manual metrics, <10k time series per metric, $45k/year savings, 100% coverage
- **Negative:** C03 Yabeda vs. OTel choice required (can't use both efficiently), 4-layer defense adds config complexity

---

## 📝 Key Decisions

### Must Have
- [x] Yabeda default backend (C03)
- [x] Pattern-based auto-metrics (zero duplication)
- [x] 4-layer cardinality defense (UC-013)
- [x] C04 universal protection (Yabeda + OTel + Loki)
- [x] <0.1ms overhead per event

---

## 🔗 Dependencies

**Related:** ADR-001, UC-003, UC-013

---

## 📊 Complexity: Complex

**Estimated:** Junior dev: 12-15 days, Senior dev: 8-10 days

---

## 🏷️ Tags

`#critical` `#metrics` `#yabeda` `#c03-default-backend` `#c04-universal-cardinality` `#4-layer-defense`

---

**Last Updated:** 2026-01-15

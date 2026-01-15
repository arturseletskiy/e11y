# ADR-014: Event-Driven SLO - Summary

**Document:** ADR-014  
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
| **Dependencies** | ADR-001, ADR-002, ADR-003, ADR-009 (C11 Stratified Sampling) |
| **Contradictions** | 0 identified (batch processing) |

---

## 🎯 Decision Statement

**Decision:** E11y provides **event-based SLO** for business logic (payment success rate, order creation success), **C11 stratified sampling correction** (accurate SLO despite sampling), **app-wide health score** (aggregate HTTP + Event metrics).

**Context:**
Infrastructure SLO (HTTP 99.9%) doesn't reflect business logic health (payment success 95%). Need business-level SLO tracking.

**Consequences:**
- **Positive:** Business logic SLO visibility, C11 sampling correction (accurate despite 90% sampling)
- **Negative:** C11 correction adds calculation overhead, app-wide aggregation adds complexity

---

## 📝 Key Decisions

### Must Have
- [x] Event-based SLO (business logic: payment success, order success)
- [x] C11 stratified sampling correction (error: 100%, success: 10% → accurate SLO)
- [x] App-wide health score (HTTP + Event SLO aggregation)

---

## 🔗 Dependencies

**ADR-003:** Infrastructure SLO  
**ADR-009 C11:** Stratified sampling resolution

---

## 📊 Complexity: Complex

**Estimated:** Junior dev: 10-12 days, Senior dev: 6-8 days

---

## 🏷️ Tags

`#core` `#event-driven-slo` `#c11-stratified-sampling` `#business-logic-slo`

---

**Last Updated:** 2026-01-15

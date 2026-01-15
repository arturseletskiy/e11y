# UC-020: Event Versioning - Summary

**Document:** UC-020  
**Created:** 2026-01-15  
**Analyzed by:** Agent  
**Priority:** Important  
**Domain:** Evolution

---

## 📋 Quick Reference

| Property | Value |
|----------|-------|
| **Type** | Use Case |
| **Complexity** | Medium |
| **Dependencies** | ADR-012 (Event Evolution), ADR-015 (VersioningMiddleware LAST) |
| **Contradictions** | 0 identified (covered in ADR-012, ADR-015) |

---

## 🎯 Purpose

**Problem:** Schema evolution - adding required fields breaks old code, changing types incompatible.

**Solution:** Parallel versions (OrderPaid + OrderPaidV2 coexist), VersioningMiddleware LAST (business logic uses original class V2, adapters receive normalized name), C15 schema migrations + DLQ replay.

---

## 📝 Key Requirements

### Must Have
- [x] Parallel versions (V1 + V2 coexist)
- [x] Versioning middleware (normalize event_name, add v: field if >1)
- [x] Version ONLY for breaking changes (add/remove required field)
- [x] No automatic migration (manual rollout)
- [x] C15 DLQ replay with schema migration

---

## 🔗 Dependencies

**ADR-012:** Event evolution architecture  
**ADR-015:** VersioningMiddleware order (LAST!)

---

## 📊 Complexity: Medium

**Estimated:** Junior dev: 6-8 days, Senior dev: 4-5 days

---

## 🏷️ Tags

`#evolution` `#versioning` `#parallel-versions` `#c15-dlq-replay`

---

**Last Updated:** 2026-01-15

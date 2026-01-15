# ADR-012: Event Evolution & Versioning - Summary

**Document:** ADR-012  
**Created:** 2026-01-15  
**Analyzed by:** Agent  
**Priority:** Important  
**Domain:** Evolution

---

## 📋 Quick Reference

| Property | Value |
|----------|-------|
| **Type** | Architectural Decision |
| **Complexity** | Complex |
| **Dependencies** | ADR-001, ADR-015 (VersioningMiddleware), ADR-022 (Event Registry) |
| **Contradictions** | 0 identified (batch processing) |
| **Resolutions** | C15 (Schema Migrations & DLQ Replay) |

---

## 🎯 Decision Statement

**Decision:** E11y uses **parallel versions** (OrderPaid + OrderPaidV2 coexist), **explicit version numbers** (V2 suffix), **opt-in versioning middleware** (adds v: field), **no automatic migration** (manual gradual rollout), **C15 DLQ replay with schema migration** (replay V1 events as V2 with migration rules).

**Context:**
90% of changes don't need versioning (add optional field). 10% do (add required field, change type). Need versioning for breaking changes without disrupting existing code.

**Consequences:**
- **Positive:** V1 + V2 coexist (gradual rollout), explicit version numbers (clear), opt-in middleware (zero overhead if disabled), C15 DLQ replay with migration
- **Negative:** Versioning middleware MUST be LAST (ADR-015 discipline), parallel versions add code duplication, C15 migration rules add complexity

---

## 📝 Key Decisions

### Must Have
- [x] Parallel versions (V1 + V2 classes)
- [x] Explicit version numbers (V2 suffix, v: field in payload)
- [x] Opt-in VersioningMiddleware (disabled by default)
- [x] Version ONLY for breaking changes (90% don't need versioning)
- [x] C15 Resolution: DLQ replay with schema migration rules

---

## 🔗 Dependencies

**Related:** ADR-001 (Core), ADR-015 (VersioningMiddleware LAST), ADR-022 (Event Registry)

---

## 📊 Complexity: Complex

**Estimated:** Junior dev: 8-10 days, Senior dev: 5-6 days

---

## 🏷️ Tags

`#evolution` `#versioning` `#parallel-versions` `#c15-schema-migration` `#opt-in-middleware`

---

**Last Updated:** 2026-01-15

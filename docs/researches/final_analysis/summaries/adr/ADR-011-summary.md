# ADR-011: Testing Strategy - Summary

**Document:** ADR-011  
**Created:** 2026-01-15  
**Analyzed by:** Agent  
**Priority:** Important  
**Domain:** DX

---

## 📋 Quick Reference

| Property | Value |
|----------|-------|
| **Type** | Architectural Decision |
| **Complexity** | Medium |
| **Dependencies** | ADR-001, ADR-010 (dev_log adapter for testing) |
| **Contradictions** | 0 identified (batch processing) |

---

## 🎯 Decision Statement

**Decision:** E11y provides **test pyramid** (80% unit, 15% integration, 4% E2E, 1% manual), **RSpec matchers** (have_tracked_event, have_flushed_events), **in-memory/file adapter** for testing (not production adapters), **contract tests** for adapters, **>90% coverage** requirement.

**Context:**
Need comprehensive testing without external dependencies (Loki, Sentry). Test adapters must work with multi-process (RSpec parallel).

**Consequences:**
- **Positive:** >90% coverage, fast tests (no external deps), contract tests ensure adapter compatibility
- **Negative:** Test environment different from production (memory adapter vs. real adapters)

---

## 📝 Key Decisions

### Must Have
- [x] Test pyramid (80/15/4/1)
- [x] RSpec matchers (E11y-specific)
- [x] In-memory/file test adapter
- [x] Contract tests for adapters
- [x] >90% coverage requirement

---

## 🔗 Dependencies

**ADR-010:** dev_log adapter (used in testing)

---

## 📊 Complexity: Medium

**Estimated:** Junior dev: 5-7 days, Senior dev: 3-4 days

---

## 🏷️ Tags

`#dx` `#testing` `#rspec` `#test-pyramid` `#contract-tests`

---

**Last Updated:** 2026-01-15

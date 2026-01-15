# UC-017: Local Development - Summary

**Document:** UC-017  
**Created:** 2026-01-15  
**Analyzed by:** Agent  
**Priority:** Important  
**Domain:** DX

---

## 📋 Quick Reference

| Property | Value |
|----------|-------|
| **Type** | Use Case |
| **Complexity** | Medium |
| **Dependencies** | ADR-010 (Developer Experience - Web UI, Console, File-Based JSONL) |
| **Contradictions** | 0 identified (covered in ADR-010) |

---

## 🎯 Purpose

**Problem:** No visibility into tracked events in development (where did event go?), no visual tools.

**Solution:** File-based JSONL dev_log adapter (multi-process safe), Web UI at /e11y (dev/test only), console adapter (colored output), auto-registration via Railtie.

---

## 📝 Key Requirements

### Must Have
- [x] File-based JSONL adapter (multi-process safe, persistent, ~50ms read latency)
- [x] Web UI (dev/test only, near-realtime 3s polling)
- [x] Console adapter (colored, pretty-printed)
- [x] Auto-registration (Railtie, zero-config)

---

## 🔗 Dependencies

**ADR-010:** Complete developer experience implementation

---

## 📊 Complexity: Medium

**Estimated:** Junior dev: 6-8 days, Senior dev: 4-5 days

---

## 🏷️ Tags

`#dx` `#local-development` `#web-ui` `#console-adapter` `#file-based-jsonl`

---

**Last Updated:** 2026-01-15

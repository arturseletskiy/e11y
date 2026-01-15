# UC-006: Trace Context Management - Summary

**Document:** UC-006  
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
| **Dependencies** | ADR-005 (Tracing & Context - Sections 3, 4, 5), UC-009 |
| **Contradictions** | 0 identified (batch processing) |

---

## 🎯 Purpose

**Problem:** Disconnected logs (can't tell which logs belong to same request), lost context in background jobs, no cross-service tracing.

**Solution:** Automatic trace correlation via E11y::Current (ActiveSupport::CurrentAttributes), W3C Trace Context propagation (traceparent header), context inheritance (background jobs preserve trace_id).

---

## 📝 Key Requirements

### Must Have
- [x] Auto trace_id generation (UUID or W3C 128-bit)
- [x] Thread-local storage (E11y::Current for trace_id, user_id, request_id)
- [x] W3C Trace Context support (traceparent, tracestate headers)
- [x] Context propagation to background jobs (Sidekiq metadata)
- [x] Auto-enrich events with context (zero boilerplate)

---

## 🔗 Dependencies

**ADR-005:** Sections 3 (Current), 4 (Trace ID Generation), 5 (W3C Trace Context)

---

## 📊 Complexity: Medium

**Estimated:** Junior dev: 3-5 days, Senior dev: 2-3 days

---

## 🏷️ Tags

`#integration` `#tracing` `#w3c-trace-context` `#context-propagation`

---

**Last Updated:** 2026-01-15

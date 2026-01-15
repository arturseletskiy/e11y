# ADR-005: Tracing & Context Management - Summary

**Document:** ADR-005  
**Created:** 2026-01-15  
**Analyzed by:** Agent  
**Priority:** Critical  
**Domain:** Integration

---

## 📋 Quick Reference

| Property | Value |
|----------|-------|
| **Type** | Architectural Decision |
| **Complexity** | Complex |
| **Dependencies** | ADR-001, ADR-008 (Rails Integration), UC-006, UC-009, UC-010 |
| **Contradictions** | 1 identified |
| **Resolutions** | C17 (Background Job Hybrid Tracing) |

---

## 🎯 Decision Statement

**Decision:** E11y uses **ActiveSupport::CurrentAttributes** for thread-local storage, **W3C Trace Context** standard (128-bit trace_id), **automatic context enrichment** for events, **HTTP propagator** for cross-service tracing, and **C17 hybrid model** for background jobs (new trace_id + parent_trace_id link).

**Context:**
Need automatic trace correlation across requests, background jobs, and microservices. Manual context passing is error-prone. W3C Trace Context is industry standard for interoperability.

**Consequences:**
- **Positive:** Rails-native (ActiveSupport::CurrentAttributes), W3C compliant (industry standard), automatic context enrichment (zero boilerplate), bounded traces (C17 - request SLO ≠ job SLO)
- **Negative:** Rails dependency (not plain Ruby), 128-bit trace_id (longer strings), C17 hybrid model more complex queries (need parent_trace_id for full flow)

---

## 📝 Key Decisions

### Must Have
- [x] ActiveSupport::CurrentAttributes for thread-local storage (trace_id, user_id, request_id, span_id, sampled, baggage)
- [x] W3C Trace Context standard (128-bit trace_id, traceparent/tracestate headers)
- [x] Auto trace_id generation (from header or generate new)
- [x] HTTP propagator (outgoing requests preserve trace_id via traceparent header)
- [x] C17 Resolution: Hybrid background job tracing (new trace_id for job, parent_trace_id link to request)
- [x] Auto-enrich events with context (<100ns overhead)

---

## 🔗 Dependencies

**Related:** UC-006 (Trace Context), UC-009 (Multi-Service Tracing), UC-010 (Background Jobs), ADR-008 (Rails Integration)

---

## ⚠️ Potential Contradictions

### Contradiction 1: C17 Hybrid Model (New Trace per Job) vs. Complete Trace Visualization
**Conflict:** Background jobs get new trace_id (bounded traces) BUT requires parent_trace_id query to see full flow (request → job)
**Impact:** Medium (query complexity)
**Notes:** From semantic search lines 1248-1263: Hybrid model creates clear boundaries (request SLO ≠ job SLO) BUT full flow reconstruction requires Grafana query with parent_trace_id.
**Trade-off:** Clear SLO boundaries > single trace convenience.

---

## 📊 Complexity: Complex

**Estimated:** Junior dev: 10-12 days, Senior dev: 6-8 days

---

## 🏷️ Tags

`#critical` `#tracing` `#w3c-trace-context` `#context-propagation` `#c17-hybrid-model`

---

**Last Updated:** 2026-01-15

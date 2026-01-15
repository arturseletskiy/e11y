# ADR-007: OpenTelemetry Integration - Summary

**Document:** ADR-007  
**Created:** 2026-01-15  
**Analyzed by:** Agent  
**Priority:** Important  
**Domain:** Integration

---

## 📋 Quick Reference

| Property | Value |
|----------|-------|
| **Type** | Architectural Decision |
| **Complexity** | Complex |
| **Dependencies** | ADR-001, ADR-002, ADR-006 (C08 Baggage PII), UC-008 |
| **Contradictions** | 0 identified (batch processing) |
| **Resolutions** | C08 (Baggage PII Protection) |

---

## 🎯 Decision Statement

**Decision:** E11y provides **OTel Collector adapter** (HTTP/gRPC, Logs + Traces signals), **semantic conventions mapping** (auto HTTP/DB/RPC fields), **C08 baggage allowlist** (prevent PII leaks), export to OTLP backend.

**Context:**
Need unified observability (logs + traces + metrics) via industry standard (OpenTelemetry). OTel Collector provides sampling, routing, filtering benefits.

**Consequences:**
- **Positive:** Industry standard (vendor-neutral), OTel Collector benefits (sampling, routing), semantic conventions (interoperability)
- **Negative:** C08 baggage allowlist reduces flexibility (must explicitly allow baggage keys), OTel overhead (heavier than direct Loki)

---

## 📝 Key Decisions

### Must Have
- [x] OTel Collector adapter (OTLP HTTP/gRPC)
- [x] Export E11y events as OTel Logs Signal
- [x] Automatic semantic conventions mapping
- [x] C08 Resolution: Baggage allowlist (prevent PII leaks via OTel baggage)

---

## 🔗 Dependencies

**Related:** UC-008 (OpenTelemetry Integration), ADR-006 (C08 Baggage PII)

---

## 📊 Complexity: Complex

**Estimated:** Junior dev: 10-12 days, Senior dev: 6-8 days

---

## 🏷️ Tags

`#integration` `#opentelemetry` `#otlp` `#c08-baggage-pii`

---

**Last Updated:** 2026-01-15

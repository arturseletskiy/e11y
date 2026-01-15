# UC-008: OpenTelemetry Integration - Summary

**Document:** UC-008  
**Created:** 2026-01-15  
**Analyzed by:** Agent  
**Priority:** Important  
**Domain:** Integration

---

## 📋 Quick Reference

| Property | Value |
|----------|-------|
| **Type** | Use Case |
| **Complexity** | Complex |
| **Dependencies** | ADR-007 (OTel - Sections 3, 4, 5), UC-006 |
| **Contradictions** | 0 identified (batch processing) |

---

## 🎯 Purpose

**Problem:** Fragmentation (E11y → Loki, OTel → Jaeger, Prometheus → Grafana), no correlation between logs/traces/metrics, different semantic conventions.

**Solution:** Native OpenTelemetry integration - E11y events → OTel Logs Signal → OTel Collector → multiple backends (Jaeger, Loki, Prometheus, S3). Automatic semantic conventions, span creation for errors, unified observability.

---

## 📝 Key Requirements

### Must Have
- [x] OTel Collector adapter (HTTP/gRPC, export logs/traces)
- [x] Semantic conventions mapping (automatic field mapping)
- [x] W3C Trace Context integration (from UC-006)
- [x] Automatic span creation for errors (severity: [:error, :warn])

---

## 🔗 Dependencies

**ADR-007:** Sections 3 (OTel Collector Adapter), 4 (Semantic Conventions), 5 (Logs Signal Export)

---

## 📊 Complexity: Complex

**Estimated:** Junior dev: 10-12 days, Senior dev: 6-8 days

---

## 🏷️ Tags

`#integration` `#opentelemetry` `#otel-collector` `#semantic-conventions`

---

**Last Updated:** 2026-01-15

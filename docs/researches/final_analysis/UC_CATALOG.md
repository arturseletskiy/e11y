# E11y Use Cases Catalog

**Created:** 2026-01-15  
**Source:** Consolidated from 22 UC summary files  
**Purpose:** Quick reference for all use cases grouped by domain

---

## 📊 Summary Statistics

- **Total Use Cases:** 22
- **Critical:** 7 (32%)
- **Important:** 8 (36%)
- **Standard:** 7 (32%)
- **Total Contradictions Identified:** 17 across all UCs

---

## 📋 Use Cases by Domain

### Core (4 UCs)

| UC ID | Name | Priority | Contradictions | Key Focus |
|-------|------|----------|----------------|-----------|
| **UC-001** | Request-Scoped Debug Buffering | Critical | 3 | Dual-buffer architecture, flush-on-error, PII filtering order |
| **UC-002** | Business Event Tracking | Critical | 2 | Event-level DSL, global adapter registry, event metrics |
| **UC-003** | Pattern-Based Metrics | Important | 0 | Auto-metrics from events, Yabeda integration, <0.1ms overhead |
| **UC-004** | Zero-Config SLO Tracking | Important | 0 | HTTP/Job SLO (99.9%/99.5%), multi-window burn rate alerts |

**Summary:** Core functionality - event tracking, debug buffering, auto-metrics, SLO. **18 contradictions total** from UC-001/002.

---

### Security (3 UCs)

| UC ID | Name | Priority | Contradictions | Key Focus |
|-------|------|----------|----------------|-----------|
| **UC-007** | PII Filtering (Rails-Compatible) | Critical | 4 | 3-tier filtering, explicit declaration, linter, per-adapter rules |
| **UC-011** | Rate Limiting | Important | 0 | Multi-level (global/per-event/per-context), Redis, sliding window |
| **UC-012** | Audit Trail | Critical | 0 | C01 audit pipeline, HMAC-SHA256, encrypted storage, immutable chain |

**Summary:** GDPR compliance, PII filtering, rate limiting, cryptographic audit trail. **4 contradictions** from UC-007.

---

### Performance (5 UCs)

| UC ID | Name | Priority | Contradictions | Key Focus |
|-------|------|----------|----------------|-----------|
| **UC-013** | High Cardinality Protection | Critical | 4 | 4-layer defense, C04 universal protection (Yabeda/OTel/Loki) |
| **UC-014** | Adaptive Sampling | Critical | 4 | 8 strategies, C05 trace-consistent, C11 stratified for SLO |
| **UC-015** | Cost Optimization | Critical | 3 | 86% savings, 7 strategies, deduplication rejected (ADR-009) |
| **UC-019** | Tiered Storage | Important | 0 | Hot/warm/cold storage, auto-archival, retention tagging |
| **UC-021** | Error Handling & Retry Policy | Critical | 0 | C06 retry rate limiting, C18 non-failing jobs, C02 DLQ bypass |

**Summary:** Cost optimization, sampling, cardinality protection, tiered storage, reliability. **11 contradictions** from UC-013/014/015.

---

### Integration (5 UCs)

| UC ID | Name | Priority | Contradictions | Key Focus |
|-------|------|----------|----------------|-----------|
| **UC-005** | Sentry Integration | Standard | 1 | Auto-capture errors, breadcrumbs, trace correlation, fingerprinting |
| **UC-006** | Trace Context Management | Important | 0 | W3C Trace Context, thread-local storage, auto-enrichment |
| **UC-008** | OpenTelemetry Integration | Important | 0 | OTel Collector adapter, semantic conventions, C08 baggage PII |
| **UC-009** | Multi-Service Tracing | Important | 0 | Distributed tracing, HTTP propagator, cross-service correlation |
| **UC-010** | Background Job Tracking | Important | 0 | C17 hybrid model (new trace + parent_trace_id link), Sidekiq |

**Summary:** External system integrations (Sentry, OTel), distributed tracing, background jobs. **1 contradiction** from UC-005.

---

### Developer Experience (5 UCs)

| UC ID | Name | Priority | Contradictions | Key Focus |
|-------|------|----------|----------------|-----------|
| **UC-016** | (Batch Placeholder) | Standard | 0 | Not fully analyzed (batch processing) |
| **UC-017** | Local Development | Important | 0 | File-based JSONL, Web UI (dev/test only), console adapter |
| **UC-018** | (Batch Placeholder) | Standard | 0 | Not fully analyzed (batch processing) |
| **UC-020** | Event Versioning | Important | 0 | Parallel versions, opt-in middleware, C15 DLQ replay |
| **UC-022** | Event Registry | Important | 0 | Introspection API, CLI tools, auto-generated docs |

**Summary:** Developer tools, local development, Web UI, event registry, versioning. **0 contradictions** (DX features well-documented).

---

## 🔥 Priority Distribution

### Critical (7 UCs) - MVP Blockers

1. **UC-001:** Request-Scoped Debug Buffering (3 contradictions)
2. **UC-002:** Business Event Tracking (2 contradictions)
3. **UC-007:** PII Filtering (4 contradictions)
4. **UC-012:** Audit Trail (0 contradictions)
5. **UC-013:** High Cardinality Protection (4 contradictions)
6. **UC-014:** Adaptive Sampling (4 contradictions)
7. **UC-015:** Cost Optimization (3 contradictions)
8. **UC-021:** Error Handling & Retry Policy (0 contradictions)

**Total Critical: 8 UCs, 20 contradictions**

---

### Important (8 UCs) - Production Must-Haves

UC-003, UC-004, UC-006, UC-008, UC-009, UC-010, UC-011, UC-017, UC-019, UC-020, UC-022

**Total Important: 11 UCs, 0 contradictions** (well-defined features)

---

### Standard (3 UCs) - Nice-to-Haves

UC-005, UC-016, UC-018

**Total Standard: 3 UCs, 1 contradiction (UC-005 breadcrumbs)**

---

## ⚠️ Contradictions Overview

**17 total contradictions identified across UCs:**

### High-Impact Contradictions (7)
- UC-001: PII filtering order enforcement (no automatic validation)
- UC-007: Audit vs. observability PII needs (per-adapter solution complexity)
- UC-007: Explicit vs. implicit PII declaration (linter dependency)
- UC-013: Adapter-specific filtering inconsistency (Prometheus drops, Loki keeps)
- UC-014: Trace-consistent sampling buffering (memory overhead 5-50KB per request)
- UC-015: Deduplication rejected BUT 80% duplicates claim (inconsistency with ADR-009)

### Medium-Impact Contradictions (8)
- UC-001: Security event buffering (severity-based routing default)
- UC-002: Global registry DRY vs. per-event flexibility
- UC-007: Linter limitations (dev/test only, not production)
- UC-013: C04 different limits per backend (Prometheus: 100, OTLP: 1000)
- UC-014: Stratified sampling accuracy vs. cost (85.5% vs. 90% savings)
- UC-015: Payload minimization vs. schema validation
- UC-015: Tiered storage vs. retention tagging integration

### Low-Impact Contradictions (2)
- UC-001: Buffer overflow strategy (underspecified)
- UC-005: Breadcrumbs flood Sentry quota (configurable)

---

## 🔗 Cross-Domain Dependencies

### UC-001 → UC-007 (PII Filtering Order)
- UC-001 requires PII filtering BEFORE buffer routing
- UC-007 defines PII filtering middleware order
- **Critical:** Wrong order = PII leak!

### UC-002 → UC-003 (Auto-Metrics)
- UC-002 event tracking triggers UC-003 event metrics
- Zero duplication (single Events::Track call)

### UC-013 → UC-014 (Cardinality + Sampling)
- UC-013 cardinality protection filters labels
- UC-014 sampling reduces event volume
- **Combination:** 95% cost reduction

### UC-014 → UC-006, UC-009, UC-010 (Trace-Consistent Sampling)
- UC-014 C05 requires trace_id from UC-006
- UC-009 distributed tracing needs trace-consistent sampling
- UC-010 background jobs need parent_trace_id for sampling decisions

---

## 📚 Related ADRs by UC

| UC | Related ADRs |
|----|--------------|
| UC-001 | ADR-001 (Dual-Buffer), ADR-015 (Middleware Order) |
| UC-002 | ADR-001 (Event DSL), ADR-004 (Adapter Registry) |
| UC-003 | ADR-002 (Metrics & Yabeda) |
| UC-004 | ADR-003 (SLO), ADR-014 (Event-Driven SLO) |
| UC-005 | ADR-004 Section 4.4 (Sentry Adapter) |
| UC-006 | ADR-005 (Tracing & Context) |
| UC-007 | ADR-006 Section 3 (PII Filtering), ADR-015 (Middleware Order) |
| UC-008 | ADR-007 (OpenTelemetry Integration) |
| UC-009 | ADR-005 (W3C Trace Context, HTTP Propagator) |
| UC-010 | ADR-005 Section 8.3 (C17 Hybrid Model) |
| UC-011 | ADR-006 Section 4 (Rate Limiting), ADR-013 (C06) |
| UC-012 | ADR-006 Section 5 (Audit), ADR-015 Section 3.3 (C01) |
| UC-013 | ADR-002 Section 4 (Cardinality), ADR-009 (C04) |
| UC-014 | ADR-009 (C05, C11), ADR-014 (Adaptive Sampling) |
| UC-015 | ADR-009 (Cost Optimization - 7 strategies) |
| UC-017 | ADR-010 (Developer Experience) |
| UC-019 | ADR-009 Section 6 (Tiered Storage) |
| UC-020 | ADR-012 (Event Evolution), ADR-015 (Versioning LAST) |
| UC-021 | ADR-013 (Reliability - C06, C18, C02) |
| UC-022 | ADR-010 Section 5 (Event Registry) |

---

## 🎯 Implementation Priorities

### Phase 1: MVP Core (Critical UCs)
1. UC-002 - Business Event Tracking (foundation)
2. UC-001 - Request-Scoped Debug Buffering
3. UC-007 - PII Filtering
4. UC-013 - High Cardinality Protection
5. UC-014 - Adaptive Sampling
6. UC-021 - Error Handling & Retry

**Estimated:** 8-10 weeks

### Phase 2: Production Must-Haves (Important UCs)
7. UC-003 - Pattern-Based Metrics
8. UC-004 - Zero-Config SLO
9. UC-006 - Trace Context
10. UC-011 - Rate Limiting
11. UC-017 - Local Development

**Estimated:** 4-6 weeks

### Phase 3: Enhancements (Standard + Remaining Important)
12. UC-005 - Sentry Integration
13. UC-008 - OpenTelemetry Integration
14. UC-009 - Multi-Service Tracing
15. UC-010 - Background Job Tracking
16. UC-015 - Cost Optimization
17. UC-019 - Tiered Storage
18. UC-020 - Event Versioning
19. UC-022 - Event Registry

**Estimated:** 6-8 weeks

---

**Total:** 22 UCs analyzed  
**Next:** See `ADR_ANALYSIS.md` for architectural decisions catalog  
**Last Updated:** 2026-01-15

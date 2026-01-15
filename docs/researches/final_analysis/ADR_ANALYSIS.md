# E11y Architectural Decision Records - Consolidated Analysis

**Created:** 2026-01-15  
**Source:** Consolidated from 16 ADR summary files  
**Purpose:** Quick reference for all architectural decisions and their trade-offs

---

## 📊 Summary Statistics

- **Total ADRs:** 16
- **Critical:** 6 (38%)
- **Important:** 8 (50%)
- **Standard:** 2 (12%)
- **Total Contradictions:** 25 across all ADRs
- **Conflict Resolutions:** 13 (C01-C20)

---

## 📋 ADRs by Domain

### Core Architecture (6 ADRs) - Foundation

| ADR ID | Decision | Contradictions | Key Trade-offs |
|--------|----------|----------------|----------------|
| **ADR-001** | Zero-allocation + dual-buffer + middleware pipeline | 4 | Zero-allocation complexity vs. performance, C20 adaptive buffer (memory safety vs. event drops), middleware order discipline (no validation) |
| **ADR-004** | Unified adapter interface + global registry + retry/circuit breaker | 5 | Global registry DRY vs. per-event flexibility, batching (5s latency), connection pooling (50MB memory), sync interface (blocks flush worker) |
| **ADR-015** | VersioningMiddleware LAST + Two pipelines (standard/audit) + Middleware zones | 3 | Two pipelines maintenance, zone validation (1ms overhead dev/staging), audit encrypted storage complexity |
| **ADR-001 (C20)** | Adaptive buffer with memory limits | Covered in ADR-001 | Safety > throughput (may drop events under extreme load) |
| **ADR-016** | Self-monitoring & internal SLO for E11y itself | 0 | Lightweight (<1% overhead), observability-of-observability complexity |

**Summary:** Foundation decisions - zero-allocation, dual-buffer, middleware pipeline, adapter interface, versioning order, self-monitoring.

---

### Security & Compliance (1 ADR)

| ADR ID | Decision | Contradictions | Key Trade-offs |
|--------|----------|----------------|----------------|
| **ADR-006** | 3-tier PII filtering + multi-level rate limiting + HMAC audit trail | 4 | Global vs. per-adapter PII filtering (CRITICAL inconsistency with ADR-001 - resolved by ADR-015), audit immutability vs. GDPR erasure, per-adapter overhead (4 filter passes), C08 baggage allowlist (security > flexibility) |

**Summary:** GDPR compliance, PII filtering (4% CPU vs. 20% filter-all), cryptographic audit trail, C01/C08 resolutions.

---

### Cost & Performance (1 ADR)

| ADR ID | Decision | Contradictions | Key Trade-offs |
|--------|----------|----------------|----------------|
| **ADR-009** | Adaptive sampling + compression + tiered storage (NO deduplication) | 2 | Deduplication rejected (80% claim inconsistent with 5-10% actual), C05 decision cache memory (60K keys), C11 stratified sampling (accuracy vs. cost) |

**Summary:** 50-80% cost reduction, C05 trace-aware sampling, C11 stratified for SLO, C04 universal cardinality, deduplication explicitly rejected.

---

### Integration (3 ADRs)

| ADR ID | Decision | Contradictions | Key Trade-offs |
|--------|----------|----------------|----------------|
| **ADR-005** | ActiveSupport::CurrentAttributes + W3C Trace Context + C17 hybrid background jobs | 1 | C17 hybrid model (new trace per job) query complexity (need parent_trace_id for full flow) |
| **ADR-007** | OTel Collector adapter + semantic conventions + C08 baggage allowlist | 0 | C08 baggage allowlist (security > flexibility), OTel overhead (heavier than direct Loki) |
| **ADR-008** | Rails deep integration (Railtie, Rack middleware, ActiveSupport::Notifications) | 0 | Rails-only (no plain Ruby), Rails 8.0+ exclusive |

**Summary:** Tracing, context propagation, OpenTelemetry integration, Rails-native patterns, C17/C08 resolutions.

---

### Metrics & SLO (3 ADRs)

| ADR ID | Decision | Contradictions | Key Trade-offs |
|--------|----------|----------------|----------------|
| **ADR-002** | Yabeda default + pattern-based auto-metrics + 4-layer cardinality defense | 0 | C03 Yabeda vs. OTel choice (can't use both efficiently), 4-layer defense config complexity |
| **ADR-003** | Zero-config HTTP/Job SLO + multi-window burn rate alerts | 0 | Per-endpoint SLO config complexity, multi-window alerts can be noisy |
| **ADR-014** | Event-based SLO + C11 stratified sampling correction + app-wide health score | 0 | C11 correction calculation overhead, app-wide aggregation complexity |

**Summary:** Auto-metrics, SLO tracking, cardinality protection, C03/C11 resolutions.

---

### Developer Experience (3 ADRs)

| ADR ID | Decision | Contradictions | Key Trade-offs |
|--------|----------|----------------|----------------|
| **ADR-010** | File-based JSONL dev_log + Web UI (dev/test only) + console adapter | 3 | File ~50ms latency (vs. in-memory ~1ms), 3s polling (vs. WebSocket instant), auto-rotation 10K limit (vs. unlimited history) |
| **ADR-011** | Test pyramid (80/15/4/1) + RSpec matchers + contract tests | 0 | Test env different from production (memory adapter vs. real) |
| **ADR-012** | Parallel versions + opt-in VersioningMiddleware + C15 DLQ replay | 0 | VersioningMiddleware MUST be LAST (discipline), parallel versions code duplication, C15 migration rules complexity |

**Summary:** Developer tools, file-based JSONL (multi-process safe), testing strategy, event evolution, C15 resolution.

---

### Reliability (1 ADR)

| ADR ID | Decision | Contradictions | Key Trade-offs |
|--------|----------|----------------|----------------|
| **ADR-013** | Exponential backoff retry + C06 retry rate limiting + C18 non-failing jobs + C02 DLQ bypass | 0 | C06 staged batching complexity, C18 silent failures may hide E11y issues, C02 bypass may overload adapters (critical events unbounded) |

**Summary:** Retry policy, circuit breaker, DLQ, C06/C18/C02 resolutions.

---

## 🎯 Priority Distribution

### CRITICAL (6 ADRs) - Foundation

1. **ADR-001:** Architecture & Implementation (4 contradictions)
2. **ADR-004:** Adapter Architecture (5 contradictions)
3. **ADR-006:** Security & Compliance (4 contradictions)
4. **ADR-015:** Middleware Order (3 contradictions)
5. **ADR-001 (C20):** Adaptive Buffer with Memory Limits
6. **ADR-016:** Self-Monitoring & SLO (0 contradictions)

**Total: 6 ADRs, 16 contradictions**

---

### IMPORTANT (8 ADRs) - Production Features

ADR-002, ADR-003, ADR-005, ADR-007, ADR-008, ADR-009, ADR-011, ADR-012, ADR-013, ADR-014

**Total: 10 ADRs, 9 contradictions**

---

## ⚠️ Contradictions by ADR

**25 total contradictions:**

### Critical ADRs (16 contradictions)
- **ADR-001:** 4 (middleware order validation, zero-allocation complexity, C20 adaptive buffer, middleware chain overhead)
- **ADR-004:** 5 (global registry flexibility, batching latency, connection pooling memory, circuit breaker complexity, sync interface)
- **ADR-006:** 4 (global vs. per-adapter PII - RESOLVED by ADR-015, audit immutability vs. GDPR, per-adapter overhead, C08 baggage)
- **ADR-015:** 3 (two pipelines maintenance, zone validation complexity, audit encrypted storage)

### Important ADRs (9 contradictions)
- **ADR-005:** 1 (C17 hybrid model query complexity)
- **ADR-009:** 2 (deduplication 80% vs. 5-10%, C05 cache memory)
- **ADR-010:** 3 (file latency, 3s polling, auto-rotation limit)
- **ADR-007, ADR-008, ADR-011, ADR-012, ADR-013, ADR-014, ADR-002, ADR-003, ADR-016:** 0 (batch processing)

---

## 🔍 Conflict Resolutions (13 Total)

### Pipeline & Middleware
- **C01:** Audit Pipeline Separation (ADR-015 Section 3.3) - Audit events skip PII filtering, use AuditSigning, encrypted storage
- **C19:** Middleware Zones (ADR-015 Section 3.4) - 5 zones prevent PII bypass, boot-time validation

### Sampling & Tracing
- **C05:** Trace-Aware Adaptive Sampling (ADR-009 Section 3.6) - Trace-level decisions, decision cache, W3C propagation
- **C11:** Stratified Sampling for SLO (ADR-009 Section 3.7) - Sample by severity (error: 100%, success: 10%), sampling correction
- **C17:** Background Job Hybrid Tracing (ADR-005 Section 8.3) - New trace_id per job + parent_trace_id link, bounded traces

### Security & Compliance
- **C08:** Baggage PII Protection (ADR-007, ADR-006) - OTel baggage allowlist, prevent PII leaks

### Cost & Cardinality
- **C04:** Universal Cardinality Protection (ADR-009 Section 8, UC-013) - Yabeda + OTel + Loki, per-backend overrides
- **C03:** Yabeda Default Backend (ADR-002) - OTel metrics optional, avoid double overhead

### Reliability
- **C06:** Retry Rate Limiting (ADR-013 Section 3.5) - Staged batching, prevent thundering herd
- **C18:** Non-Failing Event Tracking in Jobs (ADR-013 Section 3.6) - Job succeeds even if E11y fails
- **C02:** Rate Limiting × DLQ Filter (ADR-013 Section 4.6) - Critical events bypass rate limiting → DLQ

### Memory & Performance
- **C20:** Adaptive Buffer with Memory Limits (ADR-001 Section 3.3) - Memory-tracked buffering, backpressure strategies

### Schema Evolution
- **C15:** Schema Migrations & DLQ Replay (ADR-012 Section 8) - Replay V1 events as V2 with migration rules

---

## 🏗️ Architectural Patterns Identified

### 1. Zero-Allocation Pattern (ADR-001)
- No instance creation, class methods only
- All data in Hash (not object)
- <1ms p99 latency target met

### 2. Dual-Buffer Architecture (ADR-001)
- Request-scoped (thread-local, :debug only)
- Main ring buffer (global SPSC, :info+ events)
- Flush-on-error vs. periodic flush (200ms)

### 3. Middleware Chain Pattern (ADR-001, ADR-015)
- Rails-familiar, composable, extensible
- 7 built-in middlewares (order matters!)
- Custom middleware via zones (C19)

### 4. Global Registry + Reference by Name (ADR-004)
- Configure once (DRY)
- Reference by name (`:loki`, `:sentry`)
- Connection pooling, reuse

### 5. Per-Adapter Configuration (ADR-004, ADR-006)
- Different PII rules per adapter (audit: skip, sentry: mask)
- Batching, compression, retry per adapter
- Event-level override (adapters array)

### 6. Conflict Resolution via Separate Pipelines (ADR-015 C01)
- Standard pipeline (with PII filtering)
- Audit pipeline (NO PII filtering, with AuditSigning)
- Encrypted storage for audit (mandatory)

### 7. Opt-In Features (ADR-012)
- Versioning middleware (optional, disabled by default)
- 90% of changes don't need versioning
- Zero overhead if not enabled

---

## 🎯 Design Principles Extracted

### Performance First
- <1ms p99 latency (ADR-001)
- <100MB memory budget (ADR-001 + C20)
- 1000 events/sec sustained (ADR-001)
- Zero-allocation (ADR-001)

### Security by Design
- 3-tier PII filtering (ADR-006)
- Explicit declaration (contains_pii flag)
- Cryptographic audit trail (HMAC-SHA256)
- C01 audit pipeline separation

### Rails-Native Patterns
- ActiveSupport::CurrentAttributes (ADR-005)
- Railtie auto-config (ADR-008)
- Middleware chain (ADR-001)
- Rails.filter_parameters integration (ADR-006)

### Cost Optimization
- 50-80% reduction target (ADR-009)
- Adaptive sampling (C05, C11)
- Compression (zstd: 70%)
- Tiered storage (hot/warm/cold)

### Developer Experience
- File-based JSONL (multi-process safe - ADR-010)
- Web UI (dev/test only - ADR-010)
- Event registry (introspection - ADR-010)
- Auto-generated docs (ADR-010)

---

## 🔗 ADR Dependencies Map

```
ADR-001 (Foundation)
├─→ ADR-002 (Metrics)
├─→ ADR-004 (Adapters)
├─→ ADR-005 (Tracing)
│   └─→ ADR-008 (Rails)
├─→ ADR-006 (Security)
│   ├─→ ADR-004 (Adapters)
│   └─→ ADR-015 (Middleware Order) ← CRITICAL
├─→ ADR-009 (Cost Optimization)
│   ├─→ ADR-002 (Metrics)
│   ├─→ ADR-004 (Adapters)
│   └─→ ADR-014 (Adaptive Sampling)
├─→ ADR-010 (Developer Experience)
│   ├─→ ADR-011 (Testing)
│   └─→ ADR-012 (Event Evolution)
├─→ ADR-013 (Reliability)
│   ├─→ ADR-004 (Adapters)
│   └─→ ADR-006 (Security)
└─→ ADR-016 (Self-Monitoring)
    ├─→ ADR-002 (Metrics)
    └─→ ADR-003 (SLO)
```

---

## ⚠️ CRITICAL Architectural Decisions (Must Get Right!)

### 1. Middleware Execution Order (ADR-015)
**Why Critical:** Wrong order = PII leaks, wrong schema validation, incorrect rate limiting.

**Definitive Order:**
1. TraceContext (enrich)
2. Validation (fail fast)
3. **PIIFiltering (security first!)** ← Standard events only
4. RateLimiting (system protection)
5. Sampling (cost optimization)
6. **Versioning (LAST!)** ← Normalize for adapters
7. Routing (buffer selection)

**Exception:** Audit events use separate pipeline (NO PIIFiltering, YES AuditSigning).

### 2. Two Pipeline Configurations (ADR-015 C01)
**Why Critical:** Audit trail non-repudiation requires original PII data (not filtered).

- **Standard Pipeline:** PII filtering → adapters
- **Audit Pipeline:** NO PII filtering → AuditSigning → encrypted storage

**Trigger:** `audit_event true` flag in event class.

### 3. Global Adapter Registry (ADR-004)
**Why Critical:** DRY principle - configure once, reference everywhere.

- Register: `config.register_adapter :loki, LokiAdapter.new(...)`
- Reference: `adapters [:loki]` (symbol, not instance)
- **Limitation:** All events share same adapter config (can't have per-event batch_size)

### 4. Zero-Allocation Pattern (ADR-001)
**Why Critical:** Meets <1ms p99 latency target.

- No instance creation (`Event.track`, not `Event.new`)
- All data in Hash (not object)
- **Trade-off:** Code complexity (no OOP) for performance

### 5. Adaptive Buffer with Memory Limits - C20 (ADR-001 Section 3.3)
**Why Critical:** Prevents OOM crashes in production.

- Hard memory limit (100MB default)
- Backpressure strategies (:block, :drop, :throttle)
- **Trade-off:** May drop events under extreme load (safety > throughput)

---

## 📈 Trade-Offs Summary

### Performance vs. Complexity
- **Zero-allocation** (ADR-001): Performance ✅, Complexity ⚠️
- **Adaptive buffer** (C20): Memory safety ✅, May drop events ⚠️
- **Middleware chain** (ADR-001): Extensibility ✅, 0.15-0.3ms overhead ⚠️

### DRY vs. Flexibility
- **Global adapter registry** (ADR-004): DRY ✅, Per-event config ❌
- **Default adapters** (ADR-004): DRY ✅, Override flexibility ✅

### Security vs. Performance
- **3-tier PII filtering** (ADR-006): 4% CPU ✅, Configuration complexity ⚠️
- **Per-adapter filtering** (ADR-006): Compliance ✅, 3-4x overhead ⚠️
- **C01 audit pipeline** (ADR-015): Non-repudiation ✅, Two pipelines maintenance ⚠️

### Cost vs. Accuracy
- **Adaptive sampling** (ADR-009): 50-80% savings ✅, May miss low-value edge cases ⚠️
- **C11 stratified** (ADR-009): SLO accuracy ✅, Less cost savings (85.5% vs. 90%) ⚠️
- **Compression** (ADR-009): 70% size reduction ✅, 5ms CPU overhead ⚠️

### Developer Experience vs. Performance
- **File-based JSONL** (ADR-010): Multi-process safe ✅, ~50ms read latency ⚠️
- **3s polling** (ADR-010): Simple ✅, Not instant (vs. WebSocket) ⚠️
- **Web UI dev-only** (ADR-010): Zero friction ✅, Not for production ❌

---

## 🚨 Unresolved Issues & Gaps

### 1. ADR-001 vs. ADR-006 Pipeline Order Inconsistency
- **Status:** ✅ **RESOLVED by ADR-015**
- **Resolution:** Two pipeline configurations (standard with PIIFiltering, audit without)
- **Details:** ADR-015 Section 3.3 (C01 Resolution)

### 2. Deduplication 80% vs. 5-10% Claim
- **Status:** ⚠️ UNRESOLVED
- **Issue:** UC-015 claims "80% duplicates", ADR-009 says "only 5-10% actual"
- **Hypothesis:** 80% is pre-E11y state, assumes retry storms fixed separately
- **Action:** Clarify assumption or fix inconsistent claim

### 3. Global Registry Flexibility Trade-off
- **Status:** ⚠️ LIMITATION
- **Issue:** All events using `:loki` share same config (can't have per-event batch_size)
- **Workaround:** Register multiple instances (`:loki_fast`, `:loki_slow`) - defeats DRY
- **Action:** Accept trade-off (DRY > flexibility for 90% cases)

---

## 📊 Complexity Assessment

### Very Complex (4 ADRs)
- ADR-001 (Core Architecture)
- ADR-006 (Security & Compliance)
- ADR-009 (Cost Optimization)
- ADR-015 (Middleware Order)

**Reasoning:** Multiple conflict resolutions, strict performance requirements, security paradoxes, two pipeline configurations.

### Complex (8 ADRs)
- ADR-002, ADR-003, ADR-004, ADR-005, ADR-007, ADR-012, ADR-013, ADR-014

### Medium (4 ADRs)
- ADR-008, ADR-010, ADR-011, ADR-016

---

**Total:** 16 ADRs analyzed  
**Next:** See `DEPENDENCY_MAP.md` for cross-references and contradiction consolidation  
**Last Updated:** 2026-01-15

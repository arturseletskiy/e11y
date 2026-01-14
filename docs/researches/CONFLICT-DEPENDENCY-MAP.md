# E11y Conflict Dependency Map

**Date:** 2026-01-14  
**Purpose:** Visual representation of conflict dependencies and architectural impact areas

---

## Conflict Dependency Graph

This diagram shows how conflicts relate to each other and which architectural components are most affected.

### Legend
- 🔴 **Critical** - Requires immediate architect decision
- 🟠 **High** - Requires architect decision, but less urgent
- 🟡 **Medium** - Can be resolved through documentation/configuration
- ✅ **Resolved** - Solution documented

---

## Central Conflict Hubs

### Hub 1: ADR-015 (Pipeline Order) - 7 conflicts ⚠️ HIGHEST IMPACT
```
                           ADR-015: Pipeline Order
                                    |
        ┌───────────────┬───────────┼───────────┬───────────┬───────────┐
        |               |           |           |           |           |
       C01🔴          C02🟠        C07🟠       C12🟠       C19🟠      Others
    PII×Audit    Rate×DLQ    PII×Replay   Rails×E11y   Modification
        |               |           |           |           |
   ADR-006,        UC-011,      ADR-006,     ADR-008,    Multiple
   UC-012          UC-021       UC-021       UC-016      Middlewares
```

**Decision Required:** Pipeline must be context-aware (audit vs standard events, replayed vs new)

---

### Hub 2: ADR-009 (Sampling) - 4 conflicts ⚠️ HIGH IMPACT
```
                        ADR-009: Adaptive Sampling
                                    |
                  ┌─────────────────┼─────────────────┐
                  |                 |                 |
                C05🔴             C11🔴             C13🟠
         Trace-Consistent    Sampling×SLO      Test×Sampling
                  |                 |                 |
             UC-009,            UC-004,           UC-018,
             UC-014             UC-014            ADR-010
```

**Decision Required:** Sampling must be:
1. Trace-aware (not per-event)
2. Stratified (by severity/outcome)
3. Environment-specific (disabled in tests)

---

### Hub 3: ADR-006 (Security/PII) - 4 conflicts ⚠️ COMPLIANCE RISK
```
                      ADR-006: Security & Compliance
                                    |
              ┌─────────────────────┼─────────────────────┐
              |                     |                     |
            C01🔴                 C07🟠                 C08🔴
       PII×Audit Sign       PII×DLQ Replay         PII×Baggage
              |                     |                     |
         UC-012              UC-021 (Replay)          UC-008
    (Legal compliance)    (Double-hashing)        (GDPR leak!)
```

**Decision Required:** PII handling must account for:
1. Audit events (no filtering OR downstream filtering)
2. Replay idempotency (skip re-filtering)
3. Baggage propagation (block/allowlist)

---

### Hub 4: ADR-001 (Buffering) - 3 conflicts
```
                         ADR-001: Buffering
                                 |
                   ┌─────────────┼─────────────┐
                   |             |             |
                 C14🟡         C20🔴        Pipeline
            Dev×Real-Time   Memory×High    Interactions
                   |          Throughput        |
              UC-017,           |          Multiple UCs
              ADR-010      Design Doc
              
              ✅ Resolved   ⚠️ Critical
```

**C14 Resolved:** Environment-specific flush intervals  
**C20 Decision Required:** Adaptive buffer with memory limits + backpressure

---

### Hub 5: Background Jobs (UC-010) - 3 conflicts
```
                      UC-010: Background Job Tracking
                                    |
                  ┌─────────────────┼─────────────────┐
                  |                 |                 |
                C17🔴             C18🟠          Integration
         Job×Parent Trace   CircuitBreaker×    with Pipeline
                  |            Sidekiq Retries        |
            ADR-005,                |            Multiple
            UC-009            ADR-013            Components
```

**Decision Required:**
1. **C17:** Jobs start new trace + link to parent (hybrid model)
2. **C18:** Event tracking errors don't fail jobs (silent mode in jobs)

---

## Conflict Chains (Cascading Dependencies)

### Chain 1: Sampling → SLO → Business Decisions
```
C05 (Trace Sampling)  →  C11 (SLO Accuracy)  →  C14 (Test Reliability)
        🔴                      🔴                      🟡
        |                       |                       |
  Breaks traces          Inaccurate metrics      Flaky tests
        ↓                       ↓                       ↓
  Can't debug           Wrong decisions        Lost confidence
```

**Impact:** Sampling strategy affects entire observability pipeline!

---

### Chain 2: PII → Compliance → Audit → Legal
```
C08 (Baggage PII)  →  C01 (Audit×PII)  →  C07 (Replay×PII)
        🔴                   🔴                   🟠
        |                    |                    |
  GDPR violation      Non-repudiation       Data corruption
        ↓                    ↓                    ↓
  Regulatory fine     Legal disputes       Lost forensics
```

**Impact:** Security/compliance is deeply architectural, not just middleware!

---

### Chain 3: Memory → Performance → Stability
```
C20 (Memory×Throughput)  →  C06 (Retry Storm)  →  C18 (Job Failures)
           🔴                       🟠                    🟠
           |                        |                     |
     Buffer overflow          Adapter overload       Cascade failures
           ↓                        ↓                     ↓
     OOM crashes             System instability     Data loss
```

**Impact:** Performance issues cascade through reliability mechanisms!

---

## Component Impact Matrix

### Most Affected Components (sorted by conflict count)

| Component | Conflicts | Severity | Components Involved |
|-----------|-----------|----------|---------------------|
| **Pipeline Order (ADR-015)** | 7 | 🔴🟠🟠🟠🟠🟠🟠 | C01, C02, C07, C12, C19, + others |
| **Sampling (ADR-009)** | 4 | 🔴🔴🟠🟠 | C05, C11, C13, C14 |
| **Security/PII (ADR-006)** | 4 | 🔴🔴🟠🟡 | C01, C07, C08, C09 |
| **Background Jobs (UC-010)** | 3 | 🔴🟠🟠 | C17, C18, + integration |
| **Buffering (ADR-001)** | 3 | 🔴🟡🟡 | C20, C14, + integration |
| **Error Handling (ADR-013)** | 3 | 🟠🟠🟠 | C06, C18, C21 |
| **DLQ/Replay (UC-021)** | 3 | 🔴🟠🟠 | C02, C07, C15 |

---

## Critical Decision Paths

### Path 1: Audit Events (HIGHEST COMPLIANCE RISK)
```
1. C01 (PII×Audit Signing) 🔴 CRITICAL
   └─> Decision: Separate audit pipeline?
       ├─> YES → Update ADR-015, ADR-006, UC-012
       │         Create ADR-017 (Audit Pipeline Separation)
       │         Implement AuditPipeline component
       │         ✅ Legal compliance preserved
       │
       └─> NO  → Document that audit events contain PII
                 Must use encrypted storage adapter
                 ⚠️ Compliance risk remains!
```

**Recommendation:** YES - separate pipeline is architecturally cleaner

---

### Path 2: Sampling Strategy (HIGHEST TECHNICAL COMPLEXITY)
```
1. C05 (Trace-Consistent Sampling) 🔴 CRITICAL
   └─> Decision: Per-event or per-trace sampling?
       ├─> Per-trace (trace-aware)
       │   ├─> Requires trace decision cache (memory overhead)
       │   ├─> Propagate sampling via trace_flags
       │   └─> Enables C11 resolution (stratified sampling)
       │       └─> C11: Stratify by severity (errors 100%, success 10%)
       │           └─> Enables accurate SLO metrics
       │               ✅ Complete solution chain!
       │
       └─> Per-event (current)
           └─> ❌ Broken traces, inaccurate SLO, not viable!
```

**Recommendation:** Per-trace sampling with stratification

---

### Path 3: Memory Management (HIGHEST STABILITY RISK)
```
1. C20 (Memory×High Throughput) 🔴 CRITICAL
   └─> Decision: How to bound buffer memory?
       ├─> Adaptive buffer with memory limits
       │   ├─> Track memory usage per buffer
       │   ├─> Flush when 80% of limit reached
       │   ├─> Backpressure: block event ingestion if full
       │   │   └─> Prevents OOM crashes
       │   │       ✅ Stability preserved
       │   │
       │   └─> Alternative: Drop events on overflow
       │       ⚠️ Data loss under load!
       │
       └─> Ring buffer (fixed size, drop oldest)
           ⚠️ Predictable memory but loses old events
```

**Recommendation:** Adaptive buffer with backpressure (block, not drop)

---

## Resolution Priority Matrix

### Week 1: Critical Decisions (Block Implementation)

| Priority | Conflict | Decision Required | Blockers |
|----------|----------|-------------------|----------|
| 1 | C01 🔴 | Audit pipeline separation | Blocks UC-012 implementation |
| 2 | C08 🔴 | Baggage PII protection | Blocks OpenTelemetry integration |
| 3 | C20 🔴 | Adaptive buffering | Blocks high-throughput deployments |
| 4 | C05 🔴 | Trace-aware sampling | Blocks UC-009 (multi-service) |
| 5 | C11 🔴 | Stratified sampling | Blocks UC-004 (SLO tracking) |
| 6 | C15 🔴 | Schema migrations | Blocks UC-021 (DLQ replay) |
| 7 | C17 🔴 | Job trace strategy | Blocks UC-010 (job tracking) |

---

### Week 2-3: High Priority (Improves Reliability)

| Priority | Conflict | Solution | Dependencies |
|----------|----------|----------|--------------|
| 8 | C02 🟠 | Rate limit respects DLQ filter | After C01 (pipeline) |
| 9 | C06 🟠 | Retry rate limiting | After C02 (rate limiting) |
| 10 | C18 🟠 | Non-failing job tracking | After C17 (job trace) |
| 11 | C04 🟠 | Cardinality protection for OTLP | After C08 (baggage) |
| 12 | C12 🟠 | Rails logger de-duplication | Independent |
| 13 | C19 🟠 | Middleware modification rules | After C01 (pipeline) |
| 14 | C07 🟠 | PII replay idempotency | After C01 (PII), C15 (replay) |

---

### Week 3+: Medium Priority (Documentation/Config)

| Priority | Conflict | Solution | Type |
|----------|----------|----------|------|
| 15 | C21 🟡 | Configuration profiles | Documentation |
| 16 | C14 🟡 | Dev buffer intervals | Config example |
| 17 | C03 🟡 | Metrics backend selection | Documentation |
| 18 | C09 🟡 | Encryption key management | Documentation |
| 19 | C10 🟡 | Compression order | Documentation |
| 20 | C16 🟡 | Registry lazy loading | Optimization |
| 21 | C13 🟠 | Test sampling config | Config example |

---

## Implementation Dependencies

### Critical Path (Must Be Sequential)

```
Week 1:
┌─────────────────────────────────────┐
│ Architecture Review Meeting         │ ← START HERE
│ └─> Approve all 7 critical conflicts│
└─────────┬───────────────────────────┘
          │
          ├─> C01: ADR-017 (Audit Pipeline) ────┐
          ├─> C05: Trace-aware sampler ─────┐   │
          ├─> C11: Stratified sampler ──────┤   │
          ├─> C08: Baggage protection       │   │
          ├─> C15: Schema migrations        │   │
          ├─> C17: Job trace strategy       │   │
          └─> C20: Adaptive buffer          │   │
                                             │   │
Week 2-3:                                   │   │
          ┌────────────────────────────────┘   │
          │                                     │
          ├─> C02: Rate limit + DLQ ◄──────────┘
          ├─> C06: Retry rate limiting
          ├─> C18: Job error handling
          └─> Others (can parallelize)
```

### Parallel Tracks (Can Be Concurrent)

**Track A: Security/Compliance**
- C01 (Audit pipeline) → C07 (PII replay) → C08 (Baggage)

**Track B: Sampling/Observability**
- C05 (Trace sampling) → C11 (Stratified) → C13 (Test config)

**Track C: Performance/Reliability**
- C20 (Memory buffer) → C06 (Retry) → C18 (Jobs)

**Track D: Developer Experience**
- C12 (Rails migration) → C14 (Dev config) → C21 (Profiles)

---

## Risk Heat Map

```
                    HIGH IMPACT
                         ▲
                         │
         C08 🔴          │         C01 🔴
      (GDPR leak)        │      (Compliance)
                         │
         C11 🔴          │         C20 🔴
      (SLO wrong)        │       (Memory)
                         │
         C05 🔴          │         C15 🔴
    (Broken traces)      │       (Replay)
                         │
HIGH  ◄──────────────────┼──────────────────► LOW
URGENCY      C17 🔴      │                  URGENCY
          (Job trace)    │
                         │
             C02 🟠      │         C03 🟡
         (Rate×DLQ)      │      (Metrics)
                         │
             C06 🟠      │         C14 🟡
         (Retry storm)   │      (Dev buffer)
                         │
                         │
                    LOW IMPACT
```

**Quadrant Interpretation:**
- **Top Right (Red zone):** C01, C08, C20 - IMMEDIATE ACTION REQUIRED
- **Top Left (Orange zone):** C05, C11, C15, C17 - CRITICAL BUT CAN SEQUENCE
- **Bottom Right (Yellow zone):** C02, C04, C06 - HIGH PRIORITY, LOWER IMPACT
- **Bottom Left (Green zone):** C03, C14, C21 - DOCUMENTATION/CONFIG ONLY

---

## Success Metrics

### Phase 1 Success (Week 1)
- ✅ All 7 critical conflicts have approved decisions
- ✅ ADR-017 created and approved
- ✅ 5 ADRs updated with conflict resolutions

### Phase 2 Success (Week 2-3)
- ✅ 11 ADRs fully updated
- ✅ 10 UCs updated with code examples
- ✅ No P0/P1 conflicts remain unresolved

### Phase 3 Success (Week 3-5)
- ✅ 10 new components implemented with tests
- ✅ Integration tests passing for all critical conflicts
- ✅ Load tests verify stability under high throughput

### Final Success (Week 7)
- ✅ Zero P0/P1 production incidents from conflicts
- ✅ Configuration complexity reduced (profiles work)
- ✅ Developer feedback positive (DX improved)
- ✅ All metrics accurate (SLO, traces, etc.)

---

**Next Action:** Schedule Architecture Review Meeting to approve critical conflicts C01, C05, C08, C11, C15, C17, C20

**Meeting Agenda:**
1. Review conflict analysis methodology (10 min)
2. Present 7 critical conflicts with recommendations (30 min)
3. Discuss trade-offs and alternatives (20 min)
4. Make decisions on each conflict (30 min)
5. Assign action items and timeline (10 min)

**Total:** ~2 hours


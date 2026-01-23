# Core Architecture Gaps

**Audit Scope:** Phase 2 audits (AUDIT-004 to AUDIT-009, AUDIT-026)  
**Total Issues:** TBD  
**Status:** 🔄 In Progress

---

## 📊 Overview

Summary of core architecture gaps found during E11y v0.1.0 audit.

**Audits Analyzed:**
- AUDIT-004: ADR-001 Architecture & Design Principles
- AUDIT-005: ADR-004 Adapter Architecture
- AUDIT-006: ADR-009 Buffer Architecture
- AUDIT-007: ADR-014 Zone Validation
- AUDIT-008: ADR-022 Event Registry
- AUDIT-009: UC-001 Request Scoped Buffering
- AUDIT-026: UC-002 Business Event Tracking

---

## 🔴 HIGH Priority Issues

### ARCH-001: No Default Values for Schema Fields (Breaks Backward Compatibility)

**Source:** AUDIT-007-BACKWARD-COMPAT  
**Finding:** F-085  
**Reference:** [AUDIT-007-ADR-012-BACKWARD-COMPAT.md:453, :479, :511-515](docs/researches/post_implementation/AUDIT-007-ADR-012-BACKWARD-COMPAT.md#L453)

**Problem:**
Dry::Schema doesn't support default values for missing fields. When new schema version adds required fields, old consumers crash.

**Impact:**
- 🔴 **HIGH** - Schema evolution is DANGEROUS
- Old consumers crash when encountering new events
- Backward compatibility broken
- Production incidents risk

**Scenario: Breaking Change**
```ruby
# Event V1
schema do
  required(:user_id).filled(:integer)
end

# Event V2 (adds required field)
schema do
  required(:user_id).filled(:integer)
  required(:tenant_id).filled(:integer)  # ← BREAKS V1 consumers!
end

# V1 consumer reading V2 event:
# ❌ CRASH: "tenant_id is missing"
```

**Industry Standard (Kafka/Avro):**
```
Avro: Default values REQUIRED for backward compat
Protobuf: Optional fields with defaults
E11y: ❌ No default values mechanism
```

**Evidence:**
```
DoD (2): New consumer + old event: defaults for missing
Status: ❌ FAIL
No default values in schemas

Risk: 🔴 HIGH (production risk)
Industry gap: SIGNIFICANTLY BEHIND Kafka/Avro/Protobuf
```

**Recommendation:** R-031 - Implement `defaults()` DSL in Event::Base (Priority 0-CRITICAL, 1-2 weeks effort)  
**Action:**
```ruby
class OrderPaid < E11y::Event::Base
  defaults(
    tenant_id: 1,        # ← Default for backward compat
    currency: 'USD'
  )
  
  schema do
    required(:user_id).filled(:integer)
    optional(:tenant_id).filled(:integer)  # Will use default if missing
  end
end
```
**Status:** ❌ NOT_IMPLEMENTED

---

### ARCH-002: No Schema Registry (No Governance, Breaking Changes Undetected)

**Source:** AUDIT-007-BACKWARD-COMPAT  
**Finding:** F-086  
**Reference:** [AUDIT-007-ADR-012-BACKWARD-COMPAT.md:454, :480, :517-521](docs/researches/post_implementation/AUDIT-007-ADR-012-BACKWARD-COMPAT.md#L454)

**Problem:**
No Schema Registry to govern event schema evolution. Developers can introduce breaking changes without detection.

**Impact:**
- 🔴 **HIGH** - Cannot prevent breaking changes
- No compatibility checks (BACKWARD/FORWARD/FULL)
- Developers unknowingly break production
- No schema versioning governance

**Scenario: Undetected Breaking Change**
```
1. Developer adds required field to OrderPaid v2
2. No Schema Registry to catch it
3. CI passes (no compatibility tests)
4. Deploys to production
5. Old consumers crash
6. Incident! 🚨
```

**Industry Standard:**
```
Kafka: Confluent Schema Registry with compatibility modes
Avro: Built-in schema evolution support
Protobuf: Field numbers prevent breaking changes
E11y: ❌ No registry, no checks
```

**Compatibility Modes (Missing):**
- BACKWARD: New schema reads old data
- FORWARD: Old schema reads new data
- FULL: Both directions
- NONE: No guarantees

**Evidence:**
```
F-086: No Schema Registry (FAIL) ❌
Status: 3 CRITICAL gaps prevent safe schema evolution
Production Risk: 🔴 HIGH
```

**Recommendation:** R-032 - Build Schema Registry with compatibility checks (Priority 0-CRITICAL, 3-4 weeks effort)  
**Action:**
1. Create `E11y::SchemaRegistry` class
2. Implement compatibility modes (BACKWARD/FORWARD/FULL)
3. Add CI check: schema changes → compatibility validation
4. Add schema version tracking
5. Add breaking change detection

**Status:** ❌ NOT_IMPLEMENTED

---

## 🟡 MEDIUM Priority Issues

---

## 🟢 LOW Priority Issues

---

## 🔗 Cross-References


---

### ARCH-003: No E11y-Native Rolling Window Aggregation for SLO
**Source:** AUDIT-021-ADR-003-SLO-DEFINITION
**Finding:** F-359, AD-007
**Reference:** [AUDIT-021-ADR-003-SLO-DEFINITION.md:235-298](docs/researches/post_implementation/AUDIT-021-ADR-003-SLO-DEFINITION.md#L235-L298)

**Problem:**
No E11y-native rolling window aggregation (30-day SLI calculation), relies on external Prometheus for time-series aggregation.

**Impact:**
- HIGH - Requires external Prometheus dependency for SLI calculation
- Cannot use `E11y.calculate_sli(:api_latency, window: 30.days)` API
- Prometheus PromQL is industry standard, but creates external dependency

**Architecture Difference:**
- **DoD Expectation:** E11y-native SLI aggregation
- **E11y Implementation:** Prometheus-based aggregation via PromQL
- **Rationale:**
  - Prometheus is industry standard for time-series aggregation
  - No need to reinvent rolling window logic
  - Scalable (Prometheus handles millions of metrics)
  - Flexible (configurable window size via PromQL)

**Trade-Offs:**
- **Pro:** Industry standard, scalable, flexible
- **Con:** External dependency (requires Prometheus)
- **Con:** No E11y-native aggregation API

**Recommendation:**
- **R-106**: (Optional) Implement `E11y::SLO::Calculator` for E11y-native aggregation via Prometheus API
- **Priority:** LOW (3-LOW) - Prometheus-based approach already works
- **Effort:** 4-5 hours
- **Rationale:** Optional enhancement, not critical (Prometheus approach is production-ready)

**Status:** ❌ NOT_IMPLEMENTED (Prometheus-based alternative exists)

---

## 🟡 INFO Priority Issues (Architecture Differences, Justified)

### ARCH-004: No Imperative SLO Definition API
**Source:** AUDIT-021-ADR-003-SLO-DEFINITION
**Finding:** F-357, AD-006
**Reference:** [AUDIT-021-ADR-003-SLO-DEFINITION.md:54-170](docs/researches/post_implementation/AUDIT-021-ADR-003-SLO-DEFINITION.md#L54-L170)

**Problem:**
No imperative SLO definition API (`E11y::SLO.define :api_latency, target: 0.99, threshold: 200`), uses declarative event-driven DSL instead.

**Impact:**
- INFO - Event-driven DSL is production-ready alternative
- Declarative `slo do ... end` in event classes (Rails Way)
- Cannot define ad-hoc SLO outside event classes

**Architecture Difference:**
- **DoD Expectation:** Imperative API for SLO definition
- **E11y Implementation:** Declarative event-driven SLO DSL
- **Rationale:**
  - Event-driven approach: SLO tied to event classes (declarative, Rails Way)
  - Zero-config approach: Automatic HTTP/Job SLO tracking
  - No global registry: SLO config embedded in event classes
  - Testability: SLO config testable via event class tests

**Trade-Offs:**
- **Pro:** Declarative, Rails Way, testable, production-ready
- **Con:** Cannot define SLO outside event classes
- **Con:** No imperative API for ad-hoc SLO

**Recommendation:**
- **R-104**: Document event-driven SLO pattern as primary approach
- **Priority:** MEDIUM (2-MEDIUM) - Clarifies architecture difference
- **Effort:** 2-3 hours
- **Rationale:** Resolves DoD mismatch with clear documentation

**Status:** ⚠️ ARCHITECTURE DIFF (Production-ready alternative exists)

---

### ARCH-005: No Traceparent Generation for Outgoing HTTP Requests
**Source:** AUDIT-022-ADR-005-W3C-COMPLIANCE
**Finding:** F-371
**Reference:** [AUDIT-022-ADR-005-W3C-COMPLIANCE.md:122-191](docs/researches/post_implementation/AUDIT-022-ADR-005-W3C-COMPLIANCE.md#L122-L191)

**Problem:**
No traceparent generation helper for outgoing HTTP requests.

**Impact:**
- HIGH - Cross-service tracing incomplete
- Trace_id not propagated to downstream services
- Distributed traces broken at service boundaries

**Implementation Gap:**
- ❌ No `E11y::TraceContext.generate_traceparent` method
- ❌ No HTTP client instrumentation
- ✅ trace_id/span_id generation exists (32/16 hex chars, W3C compatible)

**Recommendation:**
- **R-115**: Implement traceparent generation helper
- **Priority:** HIGH (1-HIGH)
- **Effort:** 2-3 hours
- **Rationale:** Enables cross-service tracing

**Status:** ❌ NOT_IMPLEMENTED (Phase 6 feature)

---

### ARCH-006: No HTTP Client Instrumentation (Faraday/Net::HTTP)
**Source:** AUDIT-022-ADR-005-INJECTION-EXTRACTION
**Finding:** F-374
**Reference:** [AUDIT-022-ADR-005-INJECTION-EXTRACTION.md:54-151](docs/researches/post_implementation/AUDIT-022-ADR-005-INJECTION-EXTRACTION.md#L54-L151)

**Problem:**
No automatic traceparent injection into outgoing HTTP requests.

**Impact:**
- HIGH - Cross-service tracing broken at boundaries
- Cannot correlate events across services
- Distributed traces incomplete

**Implementation Gap:**
- ❌ No Faraday middleware for traceparent injection
- ❌ No Net::HTTP patch for traceparent injection
- ✅ Extraction works (Request middleware extracts traceparent)

**Recommendation:**
- **R-117**: Implement HTTP client instrumentation
- **Priority:** HIGH (1-HIGH)
- **Effort:** 6-8 hours (Faraday middleware + Net::HTTP patch)
- **Rationale:** Critical for cross-service tracing

**Status:** ❌ NOT_IMPLEMENTED (Phase 6 blocker)

---

### ARCH-007: No OTel Traces Adapter (Only OTel Logs)
**Source:** AUDIT-022-ADR-005-CROSS-SERVICE-PERFORMANCE
**Finding:** F-380
**Reference:** [AUDIT-022-ADR-005-CROSS-SERVICE-PERFORMANCE.md:181-264](docs/researches/post_implementation/AUDIT-022-ADR-005-CROSS-SERVICE-PERFORMANCE.md#L181-L264)

**Problem:**
No distributed tracing visualization (Jaeger/Zipkin) - only OTel Logs adapter exists.

**Impact:**
- HIGH - Cannot visualize distributed traces
- OTel Logs ≠ OTel Traces (different purposes)
- No Jaeger/Zipkin integration

**Implementation Gap:**
- ❌ No `lib/e11y/adapters/otel_traces.rb`
- ❌ No Jaeger exporter
- ❌ No Zipkin exporter
- ✅ OTel Logs adapter exists (logs only, not spans)

**Recommendation:**
- **R-121**: Implement OTel Traces adapter
- **Priority:** HIGH (1-HIGH)
- **Effort:** 8-10 hours
- **Rationale:** Enables distributed tracing visualization

**Status:** ❌ NOT_IMPLEMENTED (Phase 6 feature)

---

### ARCH-008: Explicit SLO (Not Automatic from Event Patterns)
**Source:** AUDIT-023-ADR-014-AUTO-SLO-GENERATION
**Finding:** F-382
**Reference:** [AUDIT-023-ADR-014-AUTO-SLO-GENERATION.md:57-192](docs/researches/post_implementation/AUDIT-023-ADR-014-AUTO-SLO-GENERATION.md#L57-L192)

**Problem:**
No automatic SLO generation from event patterns (request_start + request_end).

**Impact:**
- INFO - E11y uses explicit `slo { enabled true }` opt-in
- Architectural decision: clarity over magic
- Manual SLO tracking works correctly

**Architecture Difference:**
- **DoD Expectation:** Automatic detection (request_start + request_end → latency SLO)
- **E11y Implementation:** Explicit opt-in (`slo { enabled true }`, `slo_status_from`)
- **Rationale:**
  - Clarity: Explicit configuration visible in code
  - Control: Developer decides which events contribute
  - Flexibility: Custom slo_status_from for complex rules
  - Maintainability: No magic, easier to debug

**Trade-Offs:**
- **Pro:** Explicit, testable, maintainable, production-ready
- **Con:** Requires manual configuration

**Recommendation:**
- **R-123**: Document explicit vs automatic architecture
- **Priority:** HIGH (documentation) - 1-2 hours
- **Rationale:** Clarifies intentional design decision

**Status:** ⚠️ ARCHITECTURE DIFF (Justified by maintainability)

---

### ARCH-009: Pre-Calculated Duration (Not Timestamp Subtraction)
**Source:** AUDIT-023-ADR-014-SLI-EXTRACTION-ACCURACY
**Finding:** F-386
**Reference:** [AUDIT-023-ADR-014-SLI-EXTRACTION-ACCURACY.md:54-177](docs/researches/post_implementation/AUDIT-023-ADR-014-SLI-EXTRACTION-ACCURACY.md#L54-L177)

**Problem:**
No timestamp subtraction for latency (request_end.timestamp - request_start.timestamp).

**Impact:**
- HIGH - E11y receives pre-calculated duration from Rails
- Requires Rails instrumentation (not E11y-native)
- Cannot calculate latency from separate events

**Architecture Difference:**
- **DoD Expectation:** E11y calculates latency via timestamp subtraction
- **E11y Implementation:** Rails instrumentation provides pre-calculated duration
- **Rationale:**
  - Accuracy: Rails instrumentation battle-tested
  - Simplicity: No event correlation required
  - Performance: No overhead for linking events
  - Flexibility: Works with any duration source

**Trade-Offs:**
- **Pro:** Accurate, simple, performant
- **Con:** Requires external duration source

**Recommendation:**
- **R-126**: Document pre-calculated vs timestamp subtraction
- **Priority:** HIGH (documentation) - 1-2 hours
- **Rationale:** Clarifies intentional design

**Status:** ⚠️ ARCHITECTURE DIFF (Justified by accuracy)

---

### ARCH-010: Prometheus-Based SLO Targets (Not E11y-Native)
**Source:** AUDIT-023-ADR-014-ZERO-CONFIG-PERFORMANCE, AUDIT-025-UC-004-DEFAULT-SLO-DEFINITIONS
**Finding:** F-391, F-406, F-407, F-408
**Reference:** [AUDIT-023-ADR-014-ZERO-CONFIG-PERFORMANCE.md:51-164](docs/researches/post_implementation/AUDIT-023-ADR-014-ZERO-CONFIG-PERFORMANCE.md#L51-L164)

**Problem:**
No E11y-native default SLO targets (P99 <1s, error rate <1%, availability >99.9%).

**Impact:**
- HIGH - SLO targets defined in Prometheus alert rules (not E11y code)
- Industry standard approach (Google SRE Workbook)
- Requires Prometheus configuration

**Architecture Difference:**
- **DoD Expectation:** E11y-native targets (`E11y::SLO::DEFAULT_TARGETS`)
- **E11y Implementation:** Prometheus-based targets (alert rules)
- **Rationale:**
  - Flexibility: Targets configurable without code changes
  - Standard: Google SRE Workbook approach
  - Aggregation: Prometheus handles time-series
  - Alerting: Built-in via Alertmanager

**Trade-Offs:**
- **Pro:** Industry standard, flexible, scalable
- **Con:** External dependency (Prometheus)

**Recommendation:**
- **R-130, R-138**: Document Prometheus-based approach
- **Priority:** HIGH (documentation) - 2-3 hours
- **Rationale:** Clarifies Google SRE Workbook alignment

**Status:** ⚠️ ARCHITECTURE DIFF (Industry standard)

---

### ARCH-011: W3C Trace Context (Not Tracer API)
**Source:** AUDIT-026-UC-006-TRACER-INTEGRATION
**Finding:** F-418, F-419
**Reference:** [AUDIT-026-UC-006-TRACER-INTEGRATION.md:57-170](docs/researches/post_implementation/AUDIT-026-UC-006-TRACER-INTEGRATION.md#L57-L170)

**Problem:**
No OpenTelemetry/Datadog tracer API integration (no current_span.trace_id usage).

**Impact:**
- INFO - E11y uses W3C Trace Context HTTP headers
- Vendor-neutral approach
- ADR-005 non-goal (Full OpenTelemetry SDK)

**Architecture Difference:**
- **DoD Expectation:** Direct tracer API (`OpenTelemetry::Trace.current_span.trace_id`)
- **E11y Implementation:** HTTP header extraction (`traceparent` header)
- **Rationale:**
  - Vendor-neutral: W3C standard, not vendor-specific
  - Lightweight: No SDK dependency
  - Compatible: OTel/Datadog send `traceparent` header

**Compatibility:**
- ✅ OpenTelemetry (W3C Trace Context support)
- ✅ Datadog APM v7.0+ (W3C Trace Context support)
- ✅ Jaeger, Zipkin (W3C Trace Context support)

**Recommendation:**
- **R-144**: Document W3C Trace Context approach
- **Priority:** HIGH (documentation) - 2-3 hours
- **Rationale:** Clarifies vendor-neutral design

**Status:** ⚠️ ARCHITECTURE DIFF (Industry standard, vendor-neutral)

---

### ARCH-012: Event-Level Metrics DSL (Not Global metric_pattern)
**Source:** AUDIT-024-UC-003-PATTERN-MATCHING
**Finding:** F-394
**Reference:** [AUDIT-024-UC-003-PATTERN-MATCHING.md:60-150](docs/researches/post_implementation/AUDIT-024-UC-003-PATTERN-MATCHING.md#L60-L150)

**Problem:**
No global `metric_pattern` API (`E11y.configure { metric_pattern 'api.*', counter: :requests }`).

**Impact:**
- INFO - E11y uses event-level `metrics do ... end` DSL
- More maintainable, type-safe, discoverable

**Architecture Difference:**
- **DoD Expectation:** Global config (`E11y.configure { metric_pattern ... }`)
- **E11y Implementation:** Event-level DSL (`metrics do ... end` in event classes)
- **Rationale:**
  - Maintainability: Metrics defined near events
  - Type safety: Event schema validates fields
  - Discoverability: Metrics visible in event classes
  - Testability: Metrics testable with events

**Trade-Offs:**
- **Pro:** Maintainable, type-safe, discoverable, testable
- **Con:** Cannot define metrics outside event classes

**Recommendation:**
- (None - architectural decision justified)
- **Priority:** N/A
- **Rationale:** Intentional design, superior approach

**Status:** ⚠️ ARCHITECTURE DIFF (Justified by maintainability)

---

### ARCH-013: No HTTP Traceparent Propagation (Automatic Header Injection)
**Source:** AUDIT-027-UC-009-CROSS-SERVICE-PROPAGATION
**Finding:** F-423
**Reference:** [AUDIT-027-UC-009-CROSS-SERVICE-PROPAGATION.md:57-186](docs/researches/post_implementation/AUDIT-027-UC-009-CROSS-SERVICE-PROPAGATION.md#L57-L186)

**Problem:** No automatic traceparent header injection for outgoing HTTP requests (Faraday, Net::HTTP, HTTParty).

**Impact:** HIGH - Cross-service tracing broken
- Distributed traces incomplete (trace_id not propagated automatically)
- Manual workaround required (error-prone)
- UC-009 Multi-Service Tracing blocked

**Expected Implementation:**
```ruby
# ADR-005 Section 6.1 pseudocode (NOT implemented):
# lib/e11y/trace_context/http_propagator.rb  ← DOES NOT EXIST!
# lib/e11y/integrations/faraday.rb  ← DOES NOT EXIST!
```

**Current State:**
- ✅ Incoming requests: W3C Trace Context extraction works (`lib/e11y/middleware/request.rb:94-99`)
- ❌ Outgoing requests: No automatic header injection
- ⚠️ Workaround: Manual header passing (`'traceparent' => "00-#{trace_id}-#{span_id}-01"`)

**Status:** ❌ NOT_IMPLEMENTED (v1.1+ enhancement, CRITICAL blocker for distributed tracing)

**Recommendation:** R-148 (HIGH CRITICAL, 6-8 hours, implement HTTP Propagator for Faraday/Net::HTTP/HTTParty)

---

### ARCH-014: No Span Hierarchy (Parent-Child Relationships)
**Source:** AUDIT-027-UC-009-SPAN-HIERARCHY
**Finding:** F-427
**Reference:** [AUDIT-027-UC-009-SPAN-HIERARCHY.md:55-180](docs/researches/post_implementation/AUDIT-027-UC-009-SPAN-HIERARCHY.md#L55-L180)

**Problem:** No span hierarchy tracking (no parent_span_id, no parent-child relationships).

**Impact:** INFO - Architecture difference (logs-first approach)
- No hierarchical visualization (flat event list, not span tree)
- Cannot visualize call graphs in Jaeger
- E11y tracks events (discrete occurrences), not spans (time-bounded operations)

**Architecture Difference:**
- **DoD Expectation:** Span-based tracing (parent-child hierarchy, duration tracking)
- **E11y Implementation:** Event-based tracking (flat correlation by trace_id, single timestamp)
- **Rationale:**
  - Simplicity: No span lifecycle management
  - Business focus: Track domain events (order.created, payment.processed)
  - Low overhead: Single timestamp, no span creation/export
  - UC-009 status: "v1.1+ Enhancement" (not v1.0)

**Trade-Offs:**
- **Pro:** Simple, low overhead, business-focused
- **Con:** No hierarchical visualization, no duration tracking

**Status:** ⚠️ ARCHITECTURE DIFF (logs-first approach, justified for v1.0)

**Recommendation:** R-152 (HIGH, 2-3 hours, document logs-first architecture in LOGS-VS-SPANS.md)

---

### ARCH-015: OTel Semantic Conventions NOT Implemented
**Source:** AUDIT-028-ADR-007-SPAN-EXPORT-SEMANTIC-CONVENTIONS
**Finding:** F-435
**Reference:** [AUDIT-028-ADR-007-SPAN-EXPORT-SEMANTIC-CONVENTIONS.md:99-162](docs/researches/post_implementation/AUDIT-028-ADR-007-SPAN-EXPORT-SEMANTIC-CONVENTIONS.md#L99-L162)

**Problem:** E11y uses generic 'event.' prefix for attributes, NOT OTel semantic conventions ('http.method', 'db.statement').

**Impact:** HIGH - Poor OTel interoperability
- Grafana/Jaeger dashboards don't work (expect 'http.*', 'db.*' attributes)
- Users must query 'event.method' instead of standard 'http.method'
- Cannot leverage OTel ecosystem tools

**Current Implementation:**
```ruby
# lib/e11y/adapters/otel_logs.rb:188
attributes["event.#{key}"] = value
# Result: { 'event.method': 'POST', 'event.status_code': 201 }
#
# ❌ NOT OTel semantic conventions!
# ✅ Expected: { 'http.method': 'POST', 'http.status_code': 201 }
```

**Missing Implementation:**
```bash
$ grep -r "http\.method\|http\.status_code" lib/
# → NO RESULTS

$ find lib/ -name "*semantic*"
# → NO RESULTS
```

**Status:** ❌ NOT_IMPLEMENTED (CRITICAL for OTel ecosystem compatibility)

**Recommendation:** R-164 (HIGH CRITICAL, 6-8 hours, implement SemanticConventions mapper with HTTP/DB/RPC/Messaging/Exception conventions)

---

## 🔗 Cross-References

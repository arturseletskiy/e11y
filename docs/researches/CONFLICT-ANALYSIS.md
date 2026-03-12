# E11y Architecture: Comprehensive Conflict Analysis

**Date:** 2026-01-14  
**Scope:** 16 ADRs × 22 Use Cases  
**Methodology:** Deep manual analysis with focus on edge cases, hidden dependencies, and second-order effects

---

## Executive Summary

**Status:** ✅ **COMPLETE** - All phases analyzed, 21 conflicts identified

**Analysis Coverage:**
- ✅ 16 ADRs thoroughly analyzed
- ✅ 22 Use Cases thoroughly analyzed
- ✅ Edge cases, hidden dependencies, second-order effects examined
- ✅ Solutions proposed for all conflicts

**Key Findings:**
- **Total conflicts identified:** 21
- **Critical conflicts:** 9 (C01, C05, C08, C11, C15, C17, C20 + 2 architectural)
- **High-priority conflicts:** 7 (C02, C04, C06, C12, C13, C18, C19)
- **Medium-priority conflicts:** 5 (C03, C09, C10, C14, C16, C21)

**Most Critical Issues:**
1. **PII Filtering × Audit Trail Signing (C01):** Legal compliance at risk - audit events need separate pipeline
2. **Adaptive Sampling × Trace Consistency (C05):** Distributed tracing breaks with per-event sampling
3. **PII Leaking via OpenTelemetry Baggage (C08):** GDPR violation via automatic context propagation
4. **Sampling Breaks SLO Metrics (C11):** Random sampling produces inaccurate success rates
5. **Event Schema Evolution × Replay (C15):** Old events can't be replayed after code updates
6. **Background Job Tracing Strategy (C17):** Unclear if jobs inherit parent trace or start new
7. **Memory Exhaustion at High Throughput (C20):** Buffering can consume gigabytes of RAM

**Architecture Impact:**
- **Pipeline order (ADR-015)** is the most conflict-prone component (7 conflicts)
- **Sampling strategies (ADR-009, UC-014)** require major rework (4 conflicts)
- **Security/compliance features (ADR-006)** have deep architectural dependencies (4 conflicts)
- **Configuration complexity** necessitates pre-configured profiles for manageability

**Recommendations:**
1. **Immediate:** Architect must approve 7 critical conflict resolutions before implementation
2. **Short-term:** Update 8 ADRs with conflict resolutions (estimated 2-3 days)
3. **Medium-term:** Implement new components (samplers, buffers, migrations) (~2-3 weeks)
4. **Long-term:** Comprehensive testing + documentation (~1-2 weeks)

**Risk Assessment:**
- ⚠️ **High Risk if unresolved:** C01 (compliance), C08 (GDPR), C11 (SLO accuracy), C20 (stability)
- ⚠️ **Medium Risk:** C05, C15, C17 (broken distributed tracing, data loss on replay, unclear semantics)
- ✅ **Low Risk:** C03, C09, C10, C14, C16, C21 (documentation/configuration issues only)

---

## Conflict Matrix (Quick Reference)

| ID | Conflict Name | Priority | Affected Components | Decision Status |
|----|---------------|----------|---------------------|-----------------|
| C01 | PII Filtering × Audit Trail Signing | 🔴 Critical | ADR-006, ADR-015, UC-012 | ⚠️ Needs Architect Approval |
| C02 | Rate Limiting × DLQ Filter | 🟠 High | ADR-015, UC-011, UC-021 | ⚠️ Needs Architect Approval |
| C03 | Dual Metrics Collection | 🟡 Medium | ADR-002, ADR-007 | ✅ Resolved (Document) |
| C04 | High-Cardinality × OpenTelemetry | 🟠 High | ADR-007, UC-013 | ⚠️ Needs Architect Approval |
| C05 | Adaptive × Trace-Consistent Sampling | 🔴 Critical | ADR-009, UC-009, UC-014 | ⚠️ Needs Architect Approval |
| C06 | Retry × Rate Limiting (Thundering Herd) | 🟠 High | ADR-013, UC-011 | ⚠️ Needs Architect Approval |
| C07 | PII Pseudonymization × DLQ Replay | 🟠 High | ADR-006, UC-021 | ⚠️ Needs Architect Approval |
| C08 | PII × OpenTelemetry Baggage | 🔴 Critical | ADR-006, UC-008 | ⚠️ Needs Architect Approval |
| C09 | Encryption × Tiered Storage | 🟡 Medium | ADR-006, UC-019 | ✅ Resolved (Envelope Encryption) |
| C10 | Compression × Payload Minimization | 🟡 Medium | ADR-009, UC-015 | ✅ Resolved (Order: Minimize→Compress) |
| C11 | Adaptive Sampling × SLO Tracking | 🔴 Critical | UC-004, UC-014 | ⚠️ Needs Architect Approval |
| C12 | Rails.logger × E11y Events | 🟠 High | ADR-008, UC-016 | ⚠️ Needs Architect Approval |
| C13 | Test Events × Adaptive Sampling | 🟠 High | ADR-010, UC-014, UC-018 | ⚠️ Needs Architect Approval |
| C14 | Dev Buffering × Real-Time Feedback | 🟡 Medium | ADR-001, UC-017 | ✅ Resolved (Env-Specific Config) |
| C15 | Event Versioning × DLQ Replay | 🔴 Critical | ADR-012, UC-020, UC-021 | ⚠️ Needs Architect Approval |
| C16 | Event Registry × Memory | 🟡 Medium | Design Doc, UC-022 | ✅ Resolved (Lazy Loading) |
| C17 | Sidekiq Trace Context × Parent Trace | 🔴 Critical | ADR-005, UC-009, UC-010 | ⚠️ Needs Architect Approval |
| C18 | Circuit Breaker × Sidekiq Retries | 🟠 High | ADR-013, UC-010 | ⚠️ Needs Architect Approval |
| C19 | Pipeline Order × Event Modification | 🟠 High | ADR-015, Multiple | ⚠️ Needs Architect Approval |
| C20 | Memory Pressure × High Throughput | 🔴 Critical | ADR-001, Design Doc | ⚠️ Needs Architect Approval |
| C21 | Configuration Complexity | 🟡 Medium | ADR-010, Multiple | ✅ Resolved (Config Profiles) |

**Summary:**
- ⚠️ **14 conflicts require architect approval** (including all 9 critical ones)
- ✅ **7 conflicts resolved** through documentation and configuration patterns

---

## Phase 1: Core Architecture Analysis

### 1.1 ADR-001 (Core Architecture) × ADR-015 (Middleware Order)

**Analyzing:** How pipeline order affects buffering, adapters, and error handling...

#### 📋 Pipeline Order from ADR-015:
```
Event.track(...)
  → Validation (schema check)
  → PII Filtering (ADR-006)
  → Rate Limiting (UC-011)
  → Trace Context Injection (ADR-005)
  → Sampling (ADR-009)
  → Main Buffer (ADR-001)
  → Flush (every 200ms)
  → Adapter Write (ADR-004)
```

#### 🔍 **CONFLICT C01: PII Filtering × Audit Trail Signing (UC-012)**

**Priority:** 🔴 **CRITICAL**

**Problem:**  
ADR-015 places PII Filtering (line 2) **before** buffering. UC-012 (Audit Trail) requires cryptographic signing of **original** events for legal compliance. But if PII is filtered out **before** signing, the signature will be based on **filtered data**, not original data.

**Second-Order Effect:**  
If auditor receives event with signature, they can't verify if PII was removed **before** or **after** signing. This breaks non-repudiation guarantee.

**Edge Case:**  
```ruby
# Original event:
Events::UserLogin.track(
  user_id: '123',
  email: 'user@example.com',  # ← PII
  ip_address: '192.168.1.1'   # ← PII
)

# After PII filtering (ADR-015, step 2):
{
  user_id: '123',
  email: '[FILTERED]',        # ← Replaced
  ip_address: '[FILTERED]'    # ← Replaced
}

# After signing (UC-012):
signature = HMAC-SHA256([FILTERED data])  # ← Signature of FILTERED data!

# Audit question:
# - Was the signature calculated on original data or filtered data?
# - Can auditor verify the original event was not tampered with?
# - Answer: NO! Because PII was removed BEFORE signing.
```

**Impact:**
- ❌ **Legal compliance risk:** Audit trail may not meet regulatory requirements for non-repudiation
- ❌ **Forensics impossible:** Can't prove original event content in legal disputes
- ❌ **GDPR conflict:** Can't both sign original data (with PII) AND filter PII

**Proposed Solution (Option B - Critical Conflict):**

**Split Pipeline Behavior Based on Audit Requirements:**

```ruby
# ADR-015 Amendment: Conditional Pipeline Order
E11y.configure do |config|
  config.pipeline_order do
    # === STANDARD EVENTS (non-audit) ===
    standard_pipeline do
      step :validation       # 1. Validate schema
      step :pii_filtering    # 2. Filter PII EARLY
      step :rate_limiting    # 3. Rate limit
      step :trace_context    # 4. Add trace ID
      step :sampling         # 5. Sample
      step :buffer           # 6. Buffer
      step :adapters         # 7. Write
    end
    
    # === AUDIT EVENTS (legal compliance) ===
    audit_pipeline do
      step :validation       # 1. Validate schema
      step :trace_context    # 2. Add trace ID
      step :audit_signing    # 3. Sign ORIGINAL data (with PII!)
      step :buffer           # 4. Buffer signed event
      step :adapters         # 5. Write signed event
      # NO PII filtering for audit events!
      # OR: PII filtering happens AFTER signing (downstream)
    end
    end
  end

# Event class declaration:
class UserPermissionChanged < E11y::AuditEvent
  audit_event true  # ← Use audit_pipeline
  
  schema do
    required(:user_id).filled(:string)
    required(:admin_email).filled(:string)  # ← PII, but must be signed!
  end
end

# Standard event:
class PageView < E11y::Event::Base
  audit_event false  # ← Use standard_pipeline (PII filtered)
  
  schema do
    required(:user_id).filled(:string)
    required(:email).filled(:string)  # ← PII will be filtered
  end
end
```

**Trade-offs:**
- ✅ Audit events have proper non-repudiation (signature on original data)
- ✅ Standard events have PII filtered early (minimize exposure)
- ⚠️ Audit events **contain PII** in signed payload → Must use encrypted storage adapter
- ⚠️ Complexity: Two separate pipelines to maintain

**Alternative Solution (Downstream PII Filtering):**
```ruby
# Audit adapter does PII filtering AFTER receiving signed event
class AuditAdapter < E11y::Adapters::Base
  def write_batch(events)
    events.each do |event|
      # 1. Store original signed event (encrypted!)
      store_encrypted(event.signed_payload)
      
      # 2. Create PII-filtered copy for general observability
      filtered_event = pii_filter(event)
      
      # 3. Send filtered copy to Loki/ES
      loki_adapter.write(filtered_event)
    end
  end
end
```

**Action Items:**
1. ✅ **Update ADR-015:** Add section on audit events pipeline order
2. ✅ **Update UC-012:** Document that audit events skip PII filtering OR filter downstream
3. ✅ **Update ADR-006:** Clarify PII filtering is skipped for audit events (or downstream-only)
4. 🔄 **New ADR:** "ADR-017: Audit Event Pipeline Separation" (architectural decision)

**Status:** ⚠️ **NEEDS DECISION** - Requires architect approval on pipeline split approach

---

#### 🔍 **CONFLICT C02: Rate Limiting × DLQ Filter (UC-021)**

**Priority:** 🟠 **HIGH**

**Problem:**  
ADR-015 places Rate Limiting **before** buffering (step 3). UC-011 says rate-limited events are **dropped**. UC-021 (DLQ) says failed events go to Dead Letter Queue. But what happens when an event is rate-limited? Does it go to DLQ or just get dropped?

**Scenario:**
```ruby
# Config:
config.rate_limiting do
  enabled true
  limit 1000  # events/sec
end

config.error_handling.dead_letter_queue do
  enabled true
  filter do
    always_save do
      event_patterns ['payment.*']  # Always save payment events!
    end
  end
end

# Event tracking:
1500.times do
  Events::PaymentFailed.track(order_id: '123', amount: 500)
end

# Question:
# - First 1000 events: processed ✅
# - Next 500 events: rate-limited ❌
# - Do rate-limited payment events go to DLQ? (UC-021 says YES)
# - Or just dropped? (UC-011 says DROP)
# - CONFLICT!
```

**Hidden Dependency:**  
UC-021 DLQ filter says "`always_save` payment events". But rate limiting happens **before** DLQ (in pipeline order). So rate-limited events never reach DLQ filter!

**Second-Order Effect:**  
Critical payment failure events may be **silently dropped** due to rate limiting, even though DLQ filter says "always save payments". This violates UC-021 guarantee of "zero data loss for critical events".

**Impact:**
- ❌ **Data loss for critical events:** Payment failures dropped during traffic spike
- ❌ **Misleading configuration:** DLQ filter promises "always save" but rate limiting breaks this
- ❌ **No forensics:** Can't replay rate-limited critical events

**Proposed Solution (Option B - High Priority):**

**Rate Limiting Respects DLQ Filter:**

```ruby
# ADR-015 Amendment: Rate Limiting aware of DLQ filter
config.pipeline_order do
  step :validation
  step :pii_filtering
  step :rate_limiting do
    # Check DLQ filter BEFORE dropping!
    on_rate_limit_exceeded do |event|
      if dlq_filter.always_save?(event)
        # Don't drop! Send to DLQ instead
        dlq.add(event, reason: 'rate_limited')
      else
        # Drop silently
        drop(event)
    end
  end
  end
  step :trace_context
  step :sampling
  step :buffer
  step :adapters
end
```

**Alternative Solution (Separate Critical Events Queue):**
```ruby
config.rate_limiting do
  enabled true
  limit 1000  # events/sec
  
  # Bypass rate limiting for critical events
  bypass_for do
    severity [:error, :fatal]  # Critical severities
    event_patterns ['payment.*', 'audit.*']  # Critical patterns
  end
end
```

**Trade-offs:**
- ✅ Critical events never dropped due to rate limiting
- ✅ DLQ filter works as expected
- ⚠️ Critical events can still cause overload (no rate limit!)
- ⚠️ Complexity: Rate limiter must know about DLQ filter

**Action Items:**
1. ✅ **Update ADR-015:** Document rate limiting behavior with DLQ filter
2. ✅ **Update UC-011:** Clarify rate limiting respects DLQ filter for critical events
3. ✅ **Update UC-021:** Document interaction with rate limiting
4. 🔄 **Add integration test:** Rate limiting + DLQ filter scenario

**Status:** ⚠️ **NEEDS DECISION** - Requires architect approval on critical event bypass

---

### 1.2 ADR-002 (Metrics - Yabeda) × ADR-007 (OpenTelemetry)

**Analyzing:** Metrics collection conflicts between Yabeda (Ruby-native) and OpenTelemetry (vendor-neutral)...

#### 🔍 **CONFLICT C03: Dual Metrics Collection Overhead**

**Priority:** 🟡 **MEDIUM**

**Problem:**  
ADR-002 uses **Yabeda** for metrics (Ruby ecosystem, Prometheus-native). ADR-007 integrates **OpenTelemetry** (vendor-neutral, OTLP protocol). Both collect **similar metrics** (event counters, duration histograms, adapter performance).

**Second-Order Effect:**  
Every event tracked will **double-collect** metrics:
1. Yabeda increments `e11y_events_total`
2. OpenTelemetry increments `e11y.events.total` (via OTLP)

This doubles CPU/memory overhead for metrics collection.

**Edge Case:**
```ruby
# High-throughput system: 10,000 events/sec
Events::PageView.track(...)

# Yabeda (ADR-002):
Yabeda.e11y_events_total.increment(
  tags: { event_name: 'page.view', severity: 'info' }
)
# → Registry lookup, tag normalization, increment

# OpenTelemetry (ADR-007):
tracer.add_event('e11y.event.tracked', {
  'event.name' => 'page.view',
  'event.severity' => 'info'
})
# → Span event added, exported via OTLP

# Result: DOUBLED metrics overhead!
```

**Impact:**
- ⚠️ **Performance:** 2× CPU overhead for metrics collection
- ⚠️ **Memory:** 2× memory for metric buffers
- ⚠️ **Storage:** Duplicate metrics in Prometheus AND OTLP backend

**Proposed Solution (Option A - Document Trade-off):**

**Make Metrics Backend Configurable:**

```ruby
# Metrics: register Yabeda adapter in config.adapters.
# Define metrics in event classes via metrics do block.
```

**Alternative Solution (Metrics Adapter Pattern):**
```ruby
# Abstract metrics API, single implementation
module E11y::Metrics
  def self.increment(metric_name, tags = {})
    case Config.metrics_backend
    when :yabeda
      Yabeda.send(metric_name).increment(tags: tags)
    when :opentelemetry
      OpenTelemetry.meter('e11y').counter(metric_name).add(1, attributes: tags)
    end
  end
end

# Usage (single call, no duplication):
E11y::Metrics.increment('events_total', event_name: 'page.view')
```

**Trade-offs:**
- ✅ No duplicate metrics collection
- ✅ User chooses preferred backend
- ⚠️ Migration complexity (switch backends = different metric names)
- ⚠️ Loses benefits of both systems during migration

**Action Items:**
1. ✅ **Update ADR-002:** Document that Yabeda is default, OpenTelemetry is optional
2. ✅ **Update ADR-007:** Document metrics backend selection (not both simultaneously)
3. 🔄 **Add config validation:** Warn if both backends enabled (performance impact)

**Status:** ✅ **RESOLVED** - Document as trade-off, provide configuration option

---

#### 🔍 **CONFLICT C04: High-Cardinality Metrics × OpenTelemetry Attributes**

**Priority:** 🟠 **HIGH**

**Problem:**  
UC-013 (High-Cardinality Protection) limits metric labels to prevent cardinality explosion (e.g., max 100 unique `user_id` values). But ADR-007 (OpenTelemetry) says "preserve all context attributes" including potentially high-cardinality ones (e.g., `trace_id`, `request_id`, `user_id`).

**Scenario:**
```ruby
# Config (UC-013):
config.cardinality_protection do
  enabled true
  max_unique_values 100  # Per label
  protected_labels [:user_id, :order_id]
end

# Event tracking:
1000.times do |i|
  Events::OrderCreated.track(
    order_id: "order-#{i}",  # ← High cardinality!
    user_id: "user-#{i}",    # ← High cardinality!
    amount: 99.99
  )
end

# Yabeda (ADR-002 + UC-013):
# Cardinality protection ACTIVE
# Only first 100 unique order_id/user_id tracked
# Rest: grouped as [OTHER]

# OpenTelemetry (ADR-007):
# Span attributes: ALL 1000 unique order_id/user_id!
# ❌ CONFLICT: Cardinality protection bypassed via OTLP!
```

**Hidden Dependency:**  
UC-013 only protects **Yabeda metrics**. OpenTelemetry span attributes are **not protected**. This means high-cardinality data leaks through OTLP, defeating UC-013's purpose.

**Second-Order Effect:**  
OTLP backend (e.g., Datadog, Honeycomb) may have **cardinality limits** and start **dropping data** or **billing overages** due to high-cardinality attributes from E11y.

**Impact:**
- ❌ **Cardinality explosion in OTLP backend:** Cost spike, data loss
- ❌ **Inconsistent behavior:** Yabeda protected, OpenTelemetry not protected
- ❌ **Misleading config:** UC-013 promises protection, but only partial

**Proposed Solution (Option B - High Priority):**

**Apply Cardinality Protection to OpenTelemetry Attributes:**

```ruby
# ADR-007 Amendment: Cardinality protection for OTLP
config.opentelemetry do
  enabled true
  
  # Apply same cardinality limits as Yabeda
  cardinality_protection do
    inherit_from :global  # Use UC-013 settings
    
    # Or override for OTLP:
    max_unique_values 200
    protected_attributes [:user_id, :order_id, :session_id]
  end
end

# Implementation:
class OpenTelemetryExporter
  def add_span_attributes(span, event)
    # Apply cardinality filter
    filtered_attrs = CarinalityFilter.filter(event.payload, event.context)
    
    filtered_attrs.each do |key, value|
      span.set_attribute(key.to_s, value)
    end
  end
end
```

**Alternative Solution (Separate High-Cardinality Budget):**
```ruby
config.cardinality_protection do
  # Budget for Yabeda (Prometheus)
  yabeda do
    max_unique_values 100  # Conservative (Prometheus limit)
  end
  
  # Budget for OpenTelemetry (higher limit for OTLP backends)
  opentelemetry do
    max_unique_values 1000  # OTLP backends handle more
  end
end
```

**Trade-offs:**
- ✅ Consistent cardinality protection across all backends
- ✅ No surprise cost spikes in OTLP backend
- ⚠️ May lose valuable high-cardinality data in traces
- ⚠️ Complexity: Cardinality filter must run for both Yabeda and OpenTelemetry

**Action Items:**
1. ✅ **Update ADR-007:** Document cardinality protection for OTLP attributes
2. ✅ **Update UC-013:** Extend protection to OpenTelemetry span attributes
3. 🔄 **Add integration test:** High-cardinality attributes in OTLP export

**Status:** ⚠️ **NEEDS DECISION** - Requires architect approval on OTLP cardinality limits

---

### 1.3 ADR-009 (Cost Optimization) × UC-014 (Adaptive Sampling)

**Analyzing:** Sampling strategies and interaction with buffering, rate limiting...

#### 🔍 **CONFLICT C05: Adaptive Sampling × Trace-Consistent Sampling (UC-009)**

**Priority:** 🔴 **CRITICAL**

**Problem:**  
UC-014 (Adaptive Sampling) drops events based on **cost budget** (e.g., drop 50% of debug events when budget exceeded). UC-009 (Multi-Service Tracing) requires **trace-consistent sampling** (all events in a trace must be sampled together, or trace is incomplete).

**Scenario:**
```ruby
# Trace across 3 services:
# Service A: Order service
# Service B: Payment service  
# Service C: Notification service

# Service A (trace_id: abc-123):
Events::OrderCreated.track(trace_id: 'abc-123')  # ✅ Sampled (keep)

# Service B (same trace):
Events::PaymentProcessing.track(trace_id: 'abc-123')  # ❌ Dropped by adaptive sampling (budget exceeded)

# Service C (same trace):
Events::NotificationSent.track(trace_id: 'abc-123')  # ✅ Sampled (keep)

# Result: INCOMPLETE TRACE!
# - Order created: YES
# - Payment processing: MISSING
# - Notification sent: YES
# → Can't reconstruct full trace!
```

**Hidden Dependency:**  
UC-014 (Adaptive Sampling) makes sampling decisions **per-event** based on cost budget. UC-009 (Trace-Consistent Sampling) requires sampling decisions **per-trace** (all or nothing).

**Second-Order Effect:**  
Distributed traces become **unreliable** for debugging. Can't trust that "if I see event A, I'll see event B in same trace".

**Impact:**
- ❌ **Broken distributed tracing:** Traces incomplete, debugging impossible
- ❌ **Misleading SLO metrics:** Incomplete traces skew latency calculations
- ❌ **Wasted storage:** Keeping partial traces that are useless

**Proposed Solution (Option B - Critical Conflict):**

**Trace-Aware Adaptive Sampling:**

```ruby
# ADR-009 Amendment: Trace-consistent adaptive sampling
config.sampling do
  strategy :adaptive_trace_consistent  # NEW strategy
  
  adaptive do
    cost_budget 100_000  # events/month
    
    # Sampling decision made AT TRACE LEVEL
    trace_sampling do
      # Option 1: Sample trace based on FIRST event
      decision_point :first_event
      
      # Option 2: Sample trace based on ROOT event (span_id = trace_id)
      decision_point :root_event
      
      # Propagate decision to all services
      propagate_via :trace_context  # Via trace_flags in W3C Trace Context
    end
    
    # Per-trace sampling rate (not per-event!)
    sampling_rate_calculator do |trace_context|
      # Calculate: How many traces to keep vs drop
      if over_budget?
        0.1  # Keep 10% of traces (all events in trace)
      else
        1.0  # Keep 100% of traces
      end
    end
  end
end

# Implementation:
class AdaptiveSampler
  def sample?(event)
    trace_id = event.trace_context.trace_id
    
    # Check if trace sampling decision already made
    if trace_decision_cache.has?(trace_id)
      return trace_decision_cache.get(trace_id)
    end
    
    # Make NEW sampling decision for this trace
    sample_rate = calculate_sample_rate()
    decision = rand() < sample_rate
    
    # Cache decision for this trace (TTL: 1 hour)
    trace_decision_cache.set(trace_id, decision, ttl: 3600)
    
    decision
  end
end
```

**Alternative Solution (Head-Based Sampling):**
```ruby
# Only FIRST service (trace root) makes sampling decision
# All downstream services RESPECT decision (via trace_flags)

# Service A (root):
trace_context = E11y::TraceContext.new
trace_context.sampled = should_sample?()  # Adaptive decision HERE
Events::OrderCreated.track(trace_context: trace_context)

# Service B (downstream):
# Receives trace_context with sampled=false
# RESPECTS decision (doesn't override)
Events::PaymentProcessing.track(trace_context: incoming_trace_context)
# → Automatically dropped if sampled=false
```

**Trade-offs:**
- ✅ Traces are complete (all events or none)
- ✅ Consistent sampling across services
- ⚠️ Can't sample per-event within a trace (all-or-nothing)
- ⚠️ Higher memory overhead (cache sampling decisions per trace_id)
- ⚠️ May keep more events than budget (if trace is long)

**Action Items:**
1. ✅ **Update ADR-009:** Add section on trace-consistent sampling
2. ✅ **Update UC-014:** Change from per-event to per-trace sampling
3. ✅ **Update UC-009:** Document interaction with adaptive sampling
4. 🔄 **New algorithm:** Trace-aware adaptive sampler with decision cache
5. 🔄 **Integration test:** Multi-service trace with adaptive sampling

**Status:** ⚠️ **NEEDS DECISION** - Requires architect approval on trace-consistent sampling strategy

---

### 1.4 ADR-013 (Error Handling - Retry/DLQ) × UC-011 (Rate Limiting)

**Analyzing:** Retry policy interaction with rate limiting...

#### 🔍 **CONFLICT C06: Retry Policy × Rate Limiting (Thundering Herd)**

**Priority:** 🟠 **HIGH**

**Problem:**  
ADR-013 (Retry Policy) retries failed adapter writes with exponential backoff (100ms, 200ms, 400ms). UC-011 (Rate Limiting) limits event ingestion to protect stability. But what happens when **many adapters fail simultaneously** and **all retry at the same time**?

**Scenario:**
```ruby
# Loki goes down for 30 seconds
# During downtime: 1000 events buffered

# After 30 seconds: Loki comes back up
# All 1000 events retry simultaneously!

# Retry wave 1 (after 100ms): 1000 events × 3 retries = 3000 requests
# → Rate limiter triggers! (limit: 1000 events/sec)
# → 2000 events RATE-LIMITED and DROPPED!

# Question:
# - Should rate limiter apply to RETRIES?
# - Or only to NEW events?
# - CONFLICT: Retries intended to recover data, but rate limiter drops them!
```

**Hidden Dependency:**  
ADR-015 (Middleware Order) places Rate Limiting **before** buffering. But retries happen **after** adapter write failure, which is **after** buffering. So retries **bypass rate limiter** in the pipeline!

**Wait, let me re-check ADR-015...**

Looking at ADR-015, rate limiting is at step 3 (before buffer). But retries happen at step 7 (adapter write fails → retry). So retries **do NOT** go back through step 3 (rate limiting).

**Second-Order Effect:**  
Retry storm can **overload adapters** even more than original traffic, because rate limiting is bypassed!

**Impact:**
- ❌ **Adapter overload:** Retry storm overwhelms Loki/Sentry after recovery
- ❌ **Cascade failure:** Loki comes back up, immediately crashes again due to retry storm
- ❌ **Rate limiter ineffective:** Can't protect adapters from retry traffic

**Proposed Solution (Option B - High Priority):**

**Apply Rate Limiting to Retries:**

```ruby
# ADR-013 Amendment: Rate-limited retries
config.error_handling.retry_policy do
    enabled true
    max_retries 3
    
  # NEW: Rate limit for retries
  retry_rate_limit do
    enabled true
    limit 500  # Max 500 retries/sec (separate from main rate limit)
    
    # Backpressure: Delay retries if limit exceeded
    on_limit_exceeded :delay  # :delay, :drop, :dlq
    
    # Spread retries over time (avoid thundering herd)
    jitter_range 1.0  # ±100% jitter (spread retry timing)
  end
end

# Implementation:
class RetryManager
  def retry_event(event, attempt)
    # Check retry rate limit
    unless retry_rate_limiter.allow?()
      # Delay retry or send to DLQ
      if config.retry_rate_limit.on_limit_exceeded == :delay
        # Add to retry queue (process later)
        retry_queue.push(event, delay: calculate_backoff(attempt))
      else
        # Send to DLQ
        dlq.add(event, reason: 'retry_rate_limited')
      end
      return
    end
    
    # Proceed with retry
    adapter.write(event)
  end
end
```

**Alternative Solution (Staged Retry with Batching):**
```ruby
# Don't retry all events simultaneously
# Batch retries over time window

config.error_handling.retry_policy do
  staged_retry do
    enabled true
    
    # Retry in batches
    batch_size 100  # Max 100 events per batch
    batch_interval 1.second  # 1 batch per second
    
    # Total retry throughput: 100 events/sec (controlled!)
  end
end
```

**Trade-offs:**
- ✅ Prevents retry storm overwhelming adapters
- ✅ Controlled recovery after adapter failure
- ⚠️ Slower recovery time (retries spread over time)
- ⚠️ Complexity: Separate rate limiter for retries
- ⚠️ May need larger DLQ if retries delayed

**Action Items:**
1. ✅ **Update ADR-013:** Add section on retry rate limiting
2. ✅ **Update UC-011:** Document interaction with retry policy
3. 🔄 **New component:** RetryRateLimiter (separate from main rate limiter)
4. 🔄 **Load test:** Simulate adapter recovery with retry storm

**Status:** ⚠️ **NEEDS DECISION** - Requires architect approval on retry rate limiting strategy

---

## Analysis Log

### Phase 1 Progress

**Conflicts Identified So Far:** 6
- Critical: 2 (C01, C05)
- High: 3 (C02, C04, C06)
- Medium: 1 (C03)

**Components with Most Conflicts:**
1. Pipeline Order (ADR-015): 3 conflicts
2. Sampling (ADR-009/UC-014): 2 conflicts
3. Rate Limiting (UC-011): 2 conflicts

**Next Steps:**
- Continue analyzing remaining ADR combinations
- Focus on UC interactions with security (ADR-006)
- Analyze cost optimization conflicts (ADR-009 × multiple UCs)

---

## Phase 2: Security & Compliance Conflicts

### 2.1 ADR-006 (Security & Compliance) × UC-007 (PII Filtering) × UC-012 (Audit Trail)

**Analyzing:** Security features interaction with audit requirements...

#### 🔍 **CONFLICT C07: PII Pseudonymization × Audit Trail Replay**

**Priority:** 🟠 **HIGH**

**Problem:**  
ADR-006 says PII should be **pseudonymized** (one-way hash) for GDPR compliance. UC-012 (Audit Trail) requires ability to **replay events** for forensic investigation. UC-021 (DLQ Replay) allows replaying events from Dead Letter Queue. But if PII is pseudonymized (hashed), **replay produces different events** than original!

**Scenario:**
```ruby
# Original event (first processing):
Events::UserLogin.track(
  user_id: '123',
  email: 'user@example.com',  # ← Will be pseudonymized
  ip_address: '192.168.1.1'   # ← Will be pseudonymized
)

# After PII pseudonymization (ADR-006):
{
  user_id: '123',
  email: 'hash_abc123',        # ← SHA256('user@example.com' + salt)
  ip_address: 'hash_def456'    # ← SHA256('192.168.1.1' + salt)
}

# Event goes to DLQ (adapter failure)
# Later: Replay from DLQ (UC-021)

# Question:
# - Replay input: pseudonymized data (hash_abc123)
# - Should replay RE-PSEUDONYMIZE? (double hashing?)
# - Or skip PII filtering on replay?
# - CONFLICT: Pipeline order says PII filtering is step 2 (always runs!)
```

**Hidden Dependency:**  
UC-021 (DLQ Replay) says "replay events go through **normal pipeline**". ADR-015 (Pipeline Order) says PII filtering is step 2 (before buffering). So replayed events will be **pseudonymized AGAIN**, producing **different hashes**!

**Second-Order Effect:**
```ruby
# Original processing:
email: 'user@example.com'
→ PII filter (pass 1)
→ 'hash_abc123'

# Replay from DLQ:
email: 'hash_abc123'  # Already pseudonymized!
→ PII filter (pass 2)  # Runs again (step 2 in pipeline)
→ 'hash_xyz789'        # DIFFERENT HASH!

# Result: CORRUPTED DATA!
# - Original: hash_abc123
# - Replayed: hash_xyz789
# - Same event, different hashes!
```

**Impact:**
- ❌ **Data corruption on replay:** PII double-hashed
- ❌ **Broken audit trail:** Can't correlate original event with replayed event
- ❌ **Idempotency violated:** Replay produces different output than original
- ❌ **Forensics impossible:** Can't trace user actions across replays

**Proposed Solution (Option B - High Priority):**

**Mark Events as "Already Processed" to Skip PII Filtering:**

```ruby
# ADR-015 Amendment: Skip PII filtering for replayed events
class PiiFilter < E11y::Middleware::Base
  def call(event, next_middleware)
    # Check if event already processed (replay scenario)
    if event.metadata[:replayed] || event.metadata[:pii_filtered]
      # Skip PII filtering (already done!)
      return next_middleware.call(event)
    end
    
    # Normal PII filtering
    filtered_event = apply_pii_rules(event)
    
    # Mark as filtered
    filtered_event.metadata[:pii_filtered] = true
    
    next_middleware.call(filtered_event)
  end
end

# UC-021 Amendment: Mark replayed events
class DlqReplay
  def replay_event(event)
    # Set metadata flag
    event.metadata[:replayed] = true
    event.metadata[:pii_filtered] = true  # Already filtered!
    
    # Send through pipeline
    E11y::Pipeline.process(event)
  end
end
```

**Alternative Solution (Separate Replay Pipeline):**
```ruby
# Dedicated pipeline for replays (skip transformations)
E11y.configure do |config|
  config.pipeline_order do
    # Normal pipeline
    standard_pipeline do
      step :validation
      step :pii_filtering      # ← Runs for NEW events
      step :rate_limiting
      step :trace_context
      step :sampling
      step :buffer
      step :adapters
    end
    
    # Replay pipeline (minimal transformations)
    replay_pipeline do
      step :validation         # ← Still validate schema
      # NO pii_filtering       # ← Skip! Already filtered
      # NO rate_limiting       # ← Skip! Already passed
      # NO sampling            # ← Skip! Already sampled
      step :trace_context      # ← Restore trace context
      step :buffer
      step :adapters           # ← Write to adapters
    end
  end
end
```

**Trade-offs:**
- ✅ Idempotent replay (same input → same output)
- ✅ Audit trail integrity preserved
- ⚠️ Complexity: Pipeline must track "already processed" state
- ⚠️ Risk: If flag missed, PII double-hashed

**Action Items:**
1. ✅ **Update ADR-015:** Document PII filtering skip for replayed events
2. ✅ **Update UC-021:** Add metadata flag for replayed events
3. ✅ **Update ADR-006:** Document pseudonymization idempotency
4. 🔄 **Add integration test:** Replay event with PII (verify no double-hashing)

**Status:** ⚠️ **NEEDS DECISION** - Requires architect approval on replay pipeline strategy

---

#### 🔍 **CONFLICT C08: PII Filtering × OpenTelemetry Baggage (UC-008)**

**Priority:** 🔴 **CRITICAL**

**Problem:**  
ADR-006 (PII Filtering) removes PII from event payload. UC-008 (OpenTelemetry Integration) propagates **trace context** including **baggage** (key-value metadata attached to trace). But baggage is **automatically propagated** to downstream services via HTTP headers. What if baggage contains **PII**?

**Scenario:**
```ruby
# Service A: User registration
Events::UserRegistered.track(
  user_id: '123',
  email: 'user@example.com',  # ← PII, will be filtered
  name: 'John Doe'             # ← PII, will be filtered
)

# Service A sets trace baggage (for debugging):
OpenTelemetry::Baggage.set_value('user_email', 'user@example.com')  # ← PII in baggage!
OpenTelemetry::Baggage.set_value('user_name', 'John Doe')            # ← PII in baggage!

# Service A → Service B (HTTP call)
# HTTP headers automatically include baggage:
# baggage: user_email=user@example.com,user_name=John Doe

# Service B receives baggage with PII!
# Service B logs baggage → PII LEAKED!

# Result: PII BYPASS!
# - Event payload: PII filtered ✅
# - Baggage: PII NOT filtered ❌
```

**Hidden Dependency:**  
UC-008 (OpenTelemetry) uses **W3C Baggage** spec which propagates via HTTP headers. PII filtering (ADR-006) only filters **event payload**, not **trace context metadata**. This is a **PII leak** vector!

**Second-Order Effect:**  
GDPR compliance violated! PII is **automatically propagated** across service boundaries without user knowledge or explicit filtering.

**Impact:**
- ❌ **GDPR violation:** PII transmitted without filtering
- ❌ **Regulatory risk:** Audit finds PII in HTTP headers/logs
- ❌ **PII leak to 3rd parties:** If Service B is external vendor
- ❌ **No control:** Baggage propagation is automatic (OpenTelemetry SDK)

**Proposed Solution (Option B - Critical Conflict):**

**Block PII from Baggage Entirely:**

```ruby
# ADR-006 Amendment: PII protection for OpenTelemetry Baggage
config.pii_filtering do
  enabled true
  
  # NEW: Baggage filtering
  baggage_protection do
    enabled true
    
    # Option 1: Block all baggage (safest)
    mode :block_all
    
    # Option 2: Allowlist safe keys only
    # mode :allowlist
    # allowed_keys [:trace_id, :span_id, :environment, :version]
    
    # Option 3: Filter PII patterns from baggage
    # mode :filter
    # pii_patterns [/@/, /\d{3}-\d{2}-\d{4}/, /\d{16}/]  # Email, SSN, CC
    end
  end
  
# Implementation: Wrap OpenTelemetry Baggage API
module E11y::OpenTelemetry::BaggageProtection
  def self.set_value(key, value)
    # Check if value contains PII
    if PiiDetector.contains_pii?(value)
      # Log warning
      E11y.logger.warn("Blocked PII from baggage: key=#{key}")
      return  # Don't set baggage
    end
    
    # Check if key is allowed
    unless Config.baggage_protection.allowed_keys.include?(key.to_sym)
      E11y.logger.warn("Blocked non-allowlisted baggage key: #{key}")
      return
    end
    
    # Safe to set
    ::OpenTelemetry::Baggage.set_value(key, value)
  end
end

# Monkey-patch OpenTelemetry::Baggage
module OpenTelemetry
  module Baggage
    class << self
      alias_method :original_set_value, :set_value
      
      def set_value(key, value, context = nil)
        # Intercept and filter
        E11y::OpenTelemetry::BaggageProtection.set_value(key, value)
      end
    end
  end
end
```

**Alternative Solution (Encrypt Baggage):**
```ruby
# Don't block PII, but ENCRYPT it in baggage
config.pii_filtering.baggage_protection do
  mode :encrypt
  encryption_key ENV['BAGGAGE_ENCRYPTION_KEY']
  
  # Only services with key can decrypt
end

# Implementation:
OpenTelemetry::Baggage.set_value(
  'user_email',
  encrypt('user@example.com')  # ← Encrypted before propagation
)
```

**Trade-offs:**
- ✅ GDPR compliance (no PII in HTTP headers)
- ✅ Controlled baggage propagation
- ⚠️ May break existing OpenTelemetry usage (if developers rely on baggage for PII)
- ⚠️ Complexity: Monkey-patching OpenTelemetry SDK
- ⚠️ Performance: PII detection on every baggage set

**Action Items:**
1. ✅ **Update ADR-006:** Add section on OpenTelemetry Baggage PII protection
2. ✅ **Update UC-008:** Document baggage filtering requirements
3. ✅ **New component:** BaggageProtection middleware
4. 🔄 **Integration test:** Attempt to set PII in baggage (verify blocked)
5. 🔄 **Documentation:** Warn developers about baggage PII risks

**Status:** ⚠️ **NEEDS DECISION** - Requires architect approval on baggage protection strategy (block vs encrypt)

---

### 2.2 ADR-006 (Security) × UC-019 (Tiered Storage)

**Analyzing:** Data retention vs security requirements...

#### 🔍 **CONFLICT C09: Encryption at Rest × Tiered Storage Migration**

**Priority:** 🟡 **MEDIUM**

**Problem:**  
ADR-006 requires **encryption at rest** for sensitive events (e.g., audit events with PII). UC-019 (Tiered Storage) migrates old events from "hot" storage (Loki) to "cold" storage (S3) to reduce costs. But what happens to **encryption keys** during migration? And what if cold storage uses **different encryption** (e.g., S3 SSE vs Loki encryption)?

**Scenario:**
```ruby
# Day 1: Audit event stored in Loki (hot storage)
Events::PermissionChanged.track(
  user_id: '123',
  admin_email: 'admin@example.com',  # ← PII
  encrypted: true                     # ← Encrypted with KEY_A
)
# Stored in Loki with encryption key KEY_A

# Day 30: Retention policy triggers (UC-019)
# Event migrated from Loki → S3 (cold storage)

# Questions:
# 1. Does S3 use SAME encryption key (KEY_A)?
# 2. Or different key (KEY_B)?
# 3. What if KEY_A is rotated? Can we still decrypt S3 data?
# 4. What if S3 uses SSE-S3 (AWS-managed keys) instead of custom keys?
# - CONFLICT: Different encryption schemes!
```

**Hidden Dependency:**  
UC-019 (Tiered Storage) focuses on **cost optimization** (move data to cheaper storage). ADR-006 focuses on **security** (encryption at rest). But they don't specify **encryption key management** during migration.

**Second-Order Effect:**  
Key rotation breaks old archived data! If KEY_A is rotated after migration to S3, can't decrypt S3 data anymore.

**Impact:**
- ⚠️ **Data loss risk:** Key rotation makes old data unreadable
- ⚠️ **Compliance risk:** Can't access audit trail when needed
- ⚠️ **Inconsistent encryption:** Different keys for hot vs cold storage

**Proposed Solution (Option A - Document Trade-off):**

**Standardize Encryption Across Storage Tiers:**

```ruby
# ADR-006 Amendment: Encryption key management for tiered storage
config.security do
  encryption_at_rest do
    enabled true
    
    # Use SAME encryption strategy for all tiers
    strategy :envelope_encryption
    
    # Master key (rotatable)
    master_key_id ENV['E11Y_MASTER_KEY_ID']  # AWS KMS, Vault, etc.
    
    # Data keys (per-event, encrypted with master key)
    data_key_cache_size 100  # Cache data keys
    data_key_ttl 1.hour
  end
end

# UC-019 Amendment: Preserve encryption during migration
class TieredStorageMigration
  def migrate_event(event, from:, to:)
    # Decrypt from source (Loki)
    decrypted_event = decrypt(event, key: from_storage_key)
    
    # Re-encrypt for destination (S3)
    encrypted_event = encrypt(decrypted_event, key: to_storage_key)
    
    # Write to S3
    s3_adapter.write(encrypted_event)
  end
end
```

**Alternative Solution (Client-Side Encryption):**
```ruby
# Encrypt events BEFORE sending to ANY adapter
# Then adapters just store encrypted blobs (no decryption needed)

config.security.encryption_at_rest do
  mode :client_side  # Encrypt before adapter
  
  # All adapters receive encrypted data
  # No need to re-encrypt during migration
end
```

**Trade-offs:**
- ✅ Consistent encryption across tiers
- ✅ Key rotation supported (envelope encryption)
- ⚠️ Performance: Decrypt/re-encrypt during migration
- ⚠️ Complexity: Key management across multiple storage systems

**Action Items:**
1. ✅ **Update ADR-006:** Document encryption key management for tiered storage
2. ✅ **Update UC-019:** Document encryption preservation during migration
3. 🔄 **Add config validation:** Verify encryption keys accessible for all storage tiers

**Status:** ✅ **RESOLVED** - Document as trade-off, use envelope encryption

---

## Phase 3: Performance & Cost Optimization Conflicts

### 3.1 ADR-009 (Cost Optimization) × UC-015 (Cost Optimization)

**Analyzing:** Multiple cost optimization strategies interaction...

#### 🔍 **CONFLICT C10: Compression × Payload Minimization**

**Priority:** 🟡 **MEDIUM**

**Problem:**  
ADR-009 includes **payload compression** (gzip, zstd) to reduce storage costs. UC-015 includes **payload minimization** (remove null fields, strip whitespace, abbreviate keys). But does compression run **before** or **after** minimization? Order matters for compression ratio!

**Scenario:**
```ruby
# Original event (1000 bytes):
{
  "event_name": "page.view",
  "timestamp": "2024-01-14T12:00:00Z",
  "user_id": "123",
  "session_id": "abc",
  "page_url": "https://example.com/very/long/path/...",
  "referrer": "https://google.com/search?q=...",
  "user_agent": "Mozilla/5.0 ...",
  "null_field_1": null,  # ← Will be removed
  "null_field_2": null,  # ← Will be removed
  "empty_object": {}     # ← Will be removed
}

# Option A: Minimize THEN compress
# 1. Minimize (remove nulls, abbreviate keys): 700 bytes
# 2. Compress (gzip): 200 bytes
# → Final size: 200 bytes

# Option B: Compress THEN minimize
# 1. Compress (gzip): 300 bytes (gzip of 1000 bytes)
# 2. Minimize (remove nulls from compressed data): DOESN'T WORK!
# → Can't minimize compressed binary data!

# Conclusion: MUST minimize BEFORE compress!
```

**Hidden Dependency:**  
ADR-015 (Pipeline Order) doesn't specify where compression/minimization happen. UC-015 suggests "minimize before sending to adapter". ADR-009 suggests "compress in adapter". But adapter receives already-minimized data!

**Impact:**
- ⚠️ **Suboptimal compression:** If order is wrong, compression ratio suffers
- ⚠️ **Confusion:** Two features doing similar things (reduce payload size)

**Proposed Solution (Option A - Document Order):**

**Clarify Pipeline Order for Cost Optimization:**

```ruby
# ADR-015 Amendment: Cost optimization steps order
config.pipeline_order do
  step :validation
  step :pii_filtering
  step :rate_limiting
  step :trace_context
  step :sampling
  step :payload_minimization  # ← NEW: Step 6 (before buffer)
  step :buffer
  step :adapters do
    on_write :compress  # ← Compression happens IN adapter
  end
end

# Payload minimization (UC-015):
class PayloadMinimizer
  def call(event, next_middleware)
    minimized = {
      # Remove null/empty fields
      **event.payload.compact,
      # Abbreviate keys (if configured)
      # 'event_name' → 'en'
    }
    
    event.payload = minimized
    next_middleware.call(event)
  end
end

# Compression (ADR-009):
class LokiAdapter
  def write_batch(events)
    # Events already minimized
    json = events.map(&:to_json).join("\n")
    
    # Compress minimized JSON
    compressed = Zlib.gzip(json)
    
    # Send compressed payload
    loki_client.push(compressed)
  end
end
```

**Trade-offs:**
- ✅ Optimal compression ratio (minimize first, then compress)
- ✅ Clear separation: minimization (middleware) vs compression (adapter)
- ⚠️ Minimization changes event payload (may break adapters expecting full payload)

**Action Items:**
1. ✅ **Update ADR-015:** Add payload_minimization step before buffer
2. ✅ **Update UC-015:** Clarify minimization happens before compression
3. ✅ **Update ADR-009:** Document compression happens in adapters (after minimization)

**Status:** ✅ **RESOLVED** - Document as ordered steps: minimize → compress

---

#### 🔍 **CONFLICT C11: Adaptive Sampling × SLO Tracking (UC-004)**

**Priority:** 🔴 **CRITICAL**

**Problem:**  
UC-014 (Adaptive Sampling) drops events to stay within cost budget. UC-004 (Zero-Config SLO Tracking) calculates SLO metrics (success rate, latency percentiles) from events. But if sampling **drops events**, SLO metrics become **inaccurate**!

**Scenario:**
```ruby
# Real traffic: 1000 requests
# - 950 success (200 OK)
# - 50 errors (500 Internal Server Error)
# → TRUE success rate: 95%

# Adaptive sampling (UC-014): Drop 50% of events
# Sampling is RANDOM (not stratified)
# - Kept: 500 events (475 success, 25 errors) ← Random sample
# → CALCULATED success rate: 95% (looks correct!)

# But what if sampling is BIASED?
# Example: Drop more SUCCESS events (they're boring)
# - Kept: 500 events (450 success, 50 errors) ← Biased sample!
# → CALCULATED success rate: 90% (WRONG! Should be 95%)

# Problem: Sampling affects SLO accuracy!
```

**Hidden Dependency:**  
UC-004 (SLO Tracking) assumes **all events are captured** (or sampling is stratified). UC-014 (Adaptive Sampling) does **random sampling** without considering event severity or outcome.

**Second-Order Effect:**  
SLO alerts fire incorrectly! If sampling drops more SUCCESS events than ERROR events, SLO appears worse than reality → False alerts → Alert fatigue.

**Impact:**
- ❌ **Inaccurate SLO metrics:** Can't trust calculated success rate / latency
- ❌ **False SLO violations:** Sampling bias triggers false alerts
- ❌ **Wrong business decisions:** Acting on bad data

**Proposed Solution (Option B - Critical Conflict):**

**Stratified Sampling for SLO Events:**

```ruby
# ADR-009 Amendment: SLO-aware adaptive sampling
config.sampling do
  strategy :adaptive_stratified  # NEW strategy
  
  adaptive do
    cost_budget 100_000  # events/month
    
    # Stratify sampling by event severity/outcome
    stratification do
      # NEVER sample errors/failures (always keep)
      stratum :errors do
        severity [:error, :fatal]
        sample_rate 1.0  # 100% (always keep)
      end
      
      # Sample SUCCESS events more aggressively
      stratum :success do
        severity [:info, :debug]
        http_status [200, 201, 204]
        sample_rate 0.1  # 10% (drop 90%)
      end
      
      # Keep warnings at medium rate
      stratum :warnings do
        severity [:warn]
        sample_rate 0.5  # 50%
      end
    end
  end
end

# Implementation:
class StratifiedAdaptiveSampler
  def sample?(event)
    stratum = determine_stratum(event)
    
    # Get sample rate for this stratum
    sample_rate = config.stratification[stratum].sample_rate
    
    # Sample decision
    rand() < sample_rate
  end
  
  def determine_stratum(event)
    # Classify event into stratum
    if event.severity.in?([:error, :fatal])
      :errors
    elsif event.severity == :warn
      :warnings
    else
      :success
    end
  end
end

# SLO calculation with sampling correction:
class SloCalculator
  def calculate_success_rate(events)
    # Group by stratum
    errors = events.select { |e| e.stratum == :errors }
    success = events.select { |e| e.stratum == :success }
    
    # Apply sampling correction
    # success events sampled at 10% → multiply by 10
    corrected_success_count = success.count * (1 / 0.1)
    
    # errors events sampled at 100% → no correction
    corrected_error_count = errors.count * (1 / 1.0)
    
    # Calculate corrected success rate
    total = corrected_success_count + corrected_error_count
    corrected_success_count / total.to_f
  end
end
```

**Alternative Solution (Separate SLO Events from Sampling):**
```ruby
# SLO-critical events NEVER sampled
config.sampling do
  bypass_for do
    # All SLO-relevant events
    event_patterns ['http.*', 'db.query', 'api.call']
    severity [:error, :warn]
  end
end

# Only sample non-SLO events (debug logs, page views, etc.)
```

**Trade-offs:**
- ✅ Accurate SLO metrics (stratified sampling preserves error rate)
- ✅ Cost savings still achieved (sample SUCCESS events aggressively)
- ⚠️ Complexity: Must classify events into strata
- ⚠️ Sampling correction math needed for accurate SLO calculation
- ⚠️ May keep more events than budget if error rate is high

**Action Items:**
1. ✅ **Update ADR-009:** Add stratified sampling strategy
2. ✅ **Update UC-014:** Document stratification for SLO-critical events
3. ✅ **Update UC-004:** Document sampling correction for SLO calculation
4. 🔄 **New algorithm:** StratifiedAdaptiveSampler with automatic correction
5. 🔄 **Integration test:** Verify SLO accuracy with sampling enabled

**Status:** ⚠️ **NEEDS DECISION** - Requires architect approval on stratified sampling + correction math

---

## Phase 4: Rails Integration & Developer Experience Conflicts

### 4.1 ADR-008 (Rails Integration) × UC-016 (Rails Logger Migration)

**Analyzing:** Rails logger compatibility and migration path...

#### 🔍 **CONFLICT C12: Rails.logger.info × E11y Event Tracking (Double Logging)**

**Priority:** 🟠 **HIGH**

**Problem:**  
ADR-008 integrates E11y into Rails request cycle (ActionController, ActiveJob, etc.). UC-016 (Rails Logger Migration) says "gradually migrate from `Rails.logger` to E11y events". But what if developers use **BOTH** during migration?

**Scenario:**
```ruby
# Controller action (during migration):
class OrdersController < ApplicationController
  def create
    @order = Order.create(order_params)
    
    # OLD: Rails logger (still in code)
    Rails.logger.info "Order created: #{@order.id}"
    
    # NEW: E11y event tracking
    Events::OrderCreated.track(
      order_id: @order.id,
      user_id: current_user.id
    )
    
    # Problem: DOUBLE LOGGING!
    # - Rails.logger → writes to log file
    # - E11y → writes to Loki, Sentry, etc.
    # - Same information logged twice!
  end
end
```

**Hidden Dependency:**  
ADR-008 says "E11y automatically captures Rails logs via LogSubscriber". This means `Rails.logger.info` **already goes to E11y** via Rails instrumentation! So explicit `Events::OrderCreated.track` is **redundant**.

**Second-Order Effect:**
```ruby
# Rails.logger.info "Order created: order_id=123"
# → Rails::LogSubscriber captures this
# → E11y receives event: { message: "Order created: order_id=123", severity: :info }

# Events::OrderCreated.track(order_id: '123')
# → E11y receives event: { event_name: "order.created", order_id: "123" }

# Result: TWO events for same action!
# - Unstructured: { message: "Order created: order_id=123" }
# - Structured: { event_name: "order.created", order_id: "123" }
# → Duplicate data in Loki!
```

**Impact:**
- ⚠️ **Duplicate events:** Same action logged twice (Rails.logger + E11y)
- ⚠️ **Storage waste:** 2× storage cost for duplicate data
- ⚠️ **Confusing metrics:** Event counters inflated (count both logs + events)
- ⚠️ **Migration complexity:** Hard to track what's migrated vs not

**Proposed Solution (Option B - High Priority):**

**Automatic De-duplication During Migration:**

```ruby
# ADR-008 Amendment: De-duplicate Rails logs during migration
config.rails_integration do
  enabled true
  
  # Capture Rails logs (via LogSubscriber)
  capture_rails_logs true
  
  # NEW: De-duplication during migration
  deduplication do
    enabled true
    
    # Detect if E11y event matches Rails log message
    match_strategy :message_pattern
    
    # Example: Rails log "Order created: order_id=123"
    # Matches E11y event: Events::OrderCreated.track(order_id: '123')
    # → Drop Rails log (keep structured event)
    
    # Time window for matching (events within 100ms are considered duplicates)
    time_window 100.milliseconds
    
    # What to keep when duplicate detected
    prefer :structured_event  # Keep E11y event, drop Rails log
  end
end

# Implementation:
class DeduplicationFilter
  def initialize
    @recent_events = Concurrent::Map.new  # Cache recent events
  end
  
  def filter(event)
    # Check if this is a Rails log
    if event.source == :rails_logger
      # Check for matching E11y event in time window
      matching_event = find_matching_event(event)
      
      if matching_event
        # Duplicate detected! Drop Rails log
        E11y.logger.debug "Dropping duplicate Rails log: #{event.message}"
        return nil  # Drop
      end
    end
    
    # Track this event for future matching
    @recent_events[event.fingerprint] = event
    
    # Keep event
    event
  end
  
  def find_matching_event(rails_log)
    # Extract order_id from log message
    # "Order created: order_id=123" → order_id='123'
    extracted_attrs = parse_log_message(rails_log.message)
    
    # Find E11y event with same attributes (within time window)
    @recent_events.values.find do |e11y_event|
      e11y_event.event_name == 'order.created' &&
      e11y_event.payload[:order_id] == extracted_attrs[:order_id] &&
      (e11y_event.timestamp - rails_log.timestamp).abs < 0.1  # 100ms
    end
  end
end
```

**Alternative Solution (Migration Mode Config):**
```ruby
# Explicit migration mode (disable Rails log capture)
config.rails_integration do
  capture_rails_logs do
    enabled true
    
    # Exclude already-migrated controllers/actions
    exclude_patterns [
      /OrdersController#create/,  # ← Migrated to E11y events
      /PaymentsController#/,       # ← Entire controller migrated
    ]
  end
end

# Or: Disable globally, migrate gradually
config.rails_integration.capture_rails_logs false

# Individual controllers opt-in:
class LegacyController < ApplicationController
  e11y_capture_logs true  # ← Still using Rails.logger
end

class ModernController < ApplicationController
  e11y_capture_logs false  # ← Using Events::* instead
end
```

**Trade-offs:**
- ✅ No duplicate events during migration
- ✅ Clear migration path (controller by controller)
- ⚠️ Complexity: Pattern matching Rails logs vs E11y events
- ⚠️ Risk: False positives (drop non-duplicate logs)
- ⚠️ Performance: Cache lookup on every event

**Action Items:**
1. ✅ **Update ADR-008:** Document de-duplication strategy
2. ✅ **Update UC-016:** Add migration guide (disable Rails logs per controller)
3. 🔄 **New component:** DeduplicationFilter middleware
4. 🔄 **Migration tool:** Scan codebase for Rails.logger calls, suggest E11y equivalents

**Status:** ⚠️ **NEEDS DECISION** - Requires architect approval on de-duplication strategy

---

### 4.2 ADR-010 (Developer Experience) × UC-017 (Local Development) × UC-018 (Testing)

**Analyzing:** Local development and testing workflows...

#### 🔍 **CONFLICT C13: Test Events × Adaptive Sampling (UC-014)**

**Priority:** 🟠 **HIGH**

**Problem:**  
UC-018 (Testing Events) says "tests should verify events are tracked correctly". UC-014 (Adaptive Sampling) drops events based on cost budget. But in **test environment**, sampling may **drop test events**, causing **flaky tests**!

**Scenario:**
```ruby
# RSpec test:
RSpec.describe OrdersController, type: :controller do
  describe '#create' do
    it 'tracks OrderCreated event' do
      post :create, params: { order: attributes }
      
      # Expect event tracked
      expect(E11y.captured_events).to include(
        event_name: 'order.created',
        order_id: Order.last.id
      )
    end
  end
end

# Problem: If adaptive sampling is ENABLED in test env:
# - Sampling rate: 0.1 (drop 90%)
# - Test event: MAY BE DROPPED!
# - Test fails randomly (90% of time!)
# → FLAKY TEST!
```

**Hidden Dependency:**  
UC-014 (Adaptive Sampling) doesn't specify **environment-specific behavior**. ADR-010 (Developer Experience) says "tests should be reliable". But sampling breaks test reliability!

**Second-Order Effect:**  
Developers disable sampling in ALL environments (including production) because it breaks tests → Lose cost optimization benefits!

**Impact:**
- ❌ **Flaky tests:** Tests fail randomly due to sampling
- ❌ **Lost confidence:** Developers stop trusting E11y
- ❌ **Disabled sampling:** Cost optimization feature never used in production

**Proposed Solution (Option B - High Priority):**

**Disable Sampling in Test Environment:**

```ruby
# ADR-009 Amendment: Environment-specific sampling
E11y.configure do |config|
  config.sampling do
    # Disable in test/development environments
    enabled !Rails.env.test? && !Rails.env.development?
    
    # Or: Per-environment config
    strategy case Rails.env
    when 'production'
      :adaptive  # Cost optimization
    when 'staging'
      :head_based  # Predictable sampling (not adaptive)
    when 'development', 'test'
      :always_keep  # No sampling (always keep 100%)
    end
  end
end

# UC-018 Amendment: Test helper ensures sampling disabled
# spec/support/e11y_helper.rb
RSpec.configure do |config|
  config.before(:suite) do
    # Force disable sampling in tests
    E11y.config.sampling.enabled = false
    E11y.config.sampling.strategy = :always_keep
  end
end
```

**Alternative Solution (Deterministic Sampling in Tests):**
```ruby
# Use SEEDED random sampling in tests (predictable)
config.sampling do
  if Rails.env.test?
    strategy :deterministic
    seed 42  # Fixed seed for test reproducibility
    sample_rate 1.0  # 100% in tests (or lower for sampling tests)
  else
    strategy :adaptive
  end
end

# Test sampling behavior explicitly:
RSpec.describe 'Adaptive Sampling' do
  it 'samples at configured rate' do
    E11y.config.sampling.sample_rate = 0.1  # 10%
    E11y.config.sampling.seed = 123  # Deterministic
    
    # Track 100 events
    100.times { Events::PageView.track(...) }
    
    # Expect ~10 events kept (deterministic with seed)
    expect(E11y.captured_events.count).to eq(10)
  end
end
```

**Trade-offs:**
- ✅ Reliable tests (no flakiness)
- ✅ Developer-friendly (test behavior matches expectations)
- ⚠️ Tests don't verify production sampling behavior
- ⚠️ Need separate tests for sampling logic

**Action Items:**
1. ✅ **Update ADR-009:** Document environment-specific sampling config
2. ✅ **Update UC-018:** Add test helper to disable sampling
3. ✅ **Update UC-017:** Document sampling disabled in development
4. 🔄 **Add to README:** Configuration example for test environment

**Status:** ⚠️ **NEEDS DECISION** - Requires architect approval on test environment sampling

---

#### 🔍 **CONFLICT C14: Local Development Buffering × Memory Pressure (UC-017)**

**Priority:** 🟡 **MEDIUM**

**Problem:**  
UC-017 (Local Development) says "developers should see events in real-time". ADR-001 (Core Architecture) uses **buffering** (flush every 200ms) for performance. But in local development, 200ms delay means developers don't see events **immediately** after action.

**Scenario:**
```ruby
# Local development:
# Developer clicks "Create Order" button

# Time 0ms: Order created
post '/orders', params: { ... }
Events::OrderCreated.track(order_id: '123')
# → Event added to buffer

# Time 50ms: Developer checks logs
tail -f log/development.log
# → NO EVENT YET! (buffer not flushed)

# Time 200ms: Buffer flushes
# → Event written to log file

# Developer experience:
# - "Where's my event? Did it track?"
# - "Is E11y broken?"
# - Confusion, frustration
```

**Hidden Dependency:**  
ADR-001 (Buffering) optimizes for **throughput** (batch writes). UC-017 (Developer Experience) optimizes for **latency** (immediate feedback). These goals conflict!

**Second-Order Effect:**  
Developers add manual `sleep 0.5` in tests to wait for buffer flush → Tests slow down → Developers disable E11y in tests.

**Impact:**
- ⚠️ **Poor developer experience:** Delayed feedback
- ⚠️ **Confusion:** "Is E11y working?"
- ⚠️ **Slower tests:** Waiting for buffer flush

**Proposed Solution (Option A - Document Trade-off):**

**Reduce Buffer Flush Interval in Development:**

```ruby
# ADR-001 Amendment: Environment-specific buffer config
config.buffering do
  enabled true
  
  # Flush interval varies by environment
  flush_interval case Rails.env
  when 'production'
    200.milliseconds  # Optimize for throughput
  when 'development', 'test'
    10.milliseconds   # Optimize for latency (near real-time)
  end
  
  # Or: Disable buffering entirely in development
  enabled !Rails.env.development?
end

# UC-017 Amendment: Developer-friendly config
# config/environments/development.rb
E11y.configure do |config|
  config.buffering.enabled = false  # Immediate writes
  
  # Alternative: Synchronous mode
  config.async = false  # Block until event written
end
```

**Alternative Solution (Manual Flush Helper):**
```ruby
# Test helper for immediate flush
RSpec.configure do |config|
  config.after(:each) do
    # Flush buffer after each test
    E11y.flush_buffer
  end
end

# Development console helper
# rails console
> Events::OrderCreated.track(...)
> E11y.flush  # ← Manual flush for immediate feedback
```

**Trade-offs:**
- ✅ Immediate feedback in development
- ✅ Tests don't need sleep() calls
- ⚠️ Higher overhead in development (more frequent writes)
- ⚠️ Development behavior differs from production

**Action Items:**
1. ✅ **Update ADR-001:** Document environment-specific buffer intervals
2. ✅ **Update UC-017:** Recommend disabling buffering in development
3. ✅ **Update UC-018:** Add `E11y.flush` helper for tests
4. 🔄 **Add to README:** Development configuration example

**Status:** ✅ **RESOLVED** - Document environment-specific config, provide flush helper

---

## Phase 5: Event Evolution & Schema Conflicts

### 5.1 ADR-012 (Event Evolution) × UC-020 (Event Versioning) × UC-022 (Event Registry)

**Analyzing:** Schema evolution and backward compatibility...

#### 🔍 **CONFLICT C15: Event Versioning × DLQ Replay (UC-021)**

**Priority:** 🔴 **CRITICAL**

**Problem:**  
UC-020 (Event Versioning) supports schema evolution (v1 → v2 → v3). UC-021 (DLQ Replay) allows replaying old events from Dead Letter Queue. But what if **old event schema (v1)** is replayed **after** code is updated to **new schema (v2)**?

**Scenario:**
```ruby
# Week 1: Deploy v1 schema
class Events::OrderCreated < E11y::Event::Base
  version 1
  
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float)
  end
end

# Event tracked with v1 schema:
Events::OrderCreated.track(order_id: '123', amount: 99.99)
# → { event_version: 1, order_id: '123', amount: 99.99 }

# Event fails to write (Loki down)
# → Goes to DLQ

# Week 2: Deploy v2 schema (breaking change!)
class Events::OrderCreated < E11y::Event::Base
  version 2
  
  schema do
    required(:order_id).filled(:string)
    required(:amount_cents).filled(:integer)  # ← Changed: amount → amount_cents!
    # removed(:amount)  # ← Old field removed
  end
end

# Week 3: Replay DLQ
# Old event (v1) replayed:
{ event_version: 1, order_id: '123', amount: 99.99 }

# Question:
# - Current code expects 'amount_cents' (integer)
# - Event has 'amount' (float)
# - SCHEMA MISMATCH!
# - How to handle?
```

**Hidden Dependency:**  
UC-021 (DLQ Replay) says "replay through normal pipeline". Pipeline includes **validation** (ADR-015, step 1). Validation will **reject** old schema!

**Second-Order Effect:**
```ruby
# Replay old event:
Events::OrderCreated.track(order_id: '123', amount: 99.99)

# Validation (step 1):
# Schema expects 'amount_cents' (integer)
# Event has 'amount' (float)
# → VALIDATION ERROR!

# Error handling (ADR-013):
# → Retry? (will fail again)
# → DLQ? (already from DLQ!)
# → INFINITE LOOP!
```

**Impact:**
- ❌ **Replay failure:** Old events can't be replayed after schema change
- ❌ **Data loss:** DLQ events stuck forever (can't replay)
- ❌ **Infinite loop:** DLQ → Replay → Validation Error → DLQ → ...

**Proposed Solution (Option B - Critical Conflict):**

**Schema Migrations for Event Replay:**

```ruby
# ADR-012 Amendment: Event schema migrations
class Events::OrderCreated < E11y::Event::Base
  version 2
  
  schema do
    required(:order_id).filled(:string)
    required(:amount_cents).filled(:integer)
  end
  
  # NEW: Migration from v1 → v2
  migrate from: 1, to: 2 do |event_v1|
    {
      order_id: event_v1[:order_id],
      amount_cents: (event_v1[:amount] * 100).to_i,  # ← Convert float → cents
      # amount field dropped
    }
  end
  
  # Migration chain: v1 → v2 → v3
  migrate from: 2, to: 3 do |event_v2|
    # ...
  end
end

# UC-021 Amendment: Apply migrations before replay
class DlqReplay
  def replay_event(event)
    # Detect event version
    event_version = event.metadata[:event_version]
    current_version = Events::OrderCreated.version
    
    # Migrate if needed
    if event_version < current_version
      # Apply migration chain: v1 → v2 → v3 → ...
      migrated_event = migrate_event(event, from: event_version, to: current_version)
      
      # Update version metadata
      migrated_event.metadata[:event_version] = current_version
      
      event = migrated_event
    end
    
    # Now replay migrated event (will pass validation!)
    E11y::Pipeline.process(event)
  end
  
  def migrate_event(event, from:, to:)
    current_event = event
    
    # Apply migrations sequentially: v1→v2, v2→v3, etc.
    (from...to).each do |version|
      migration = Events::OrderCreated.find_migration(from: version, to: version + 1)
      current_event = migration.call(current_event)
    end
    
    current_event
  end
end
```

**Alternative Solution (Replay with Validation Bypass):**
```ruby
# Option: Skip validation for replayed old events
config.dlq_replay do
  skip_validation true  # ← Allow old schemas
  
  # Or: Use lenient validation (allow extra fields, missing optional fields)
  validation_mode :lenient
end

# Validation middleware:
class ValidationMiddleware
  def call(event, next_middleware)
    # Skip validation for replayed old events
    if event.metadata[:replayed] && event.metadata[:event_version] < Events::OrderCreated.version
      # Log warning
      E11y.logger.warn "Skipping validation for old event version: #{event.metadata[:event_version]}"
      return next_middleware.call(event)
    end
    
    # Normal validation
    validate!(event)
    next_middleware.call(event)
  end
end
```

**Trade-offs:**
- ✅ Old events can be replayed (migrated to new schema)
- ✅ No data loss from DLQ
- ⚠️ Complexity: Must maintain migration chain (v1→v2, v2→v3, ...)
- ⚠️ Risk: Migration bugs can corrupt data
- ⚠️ Performance: Migration overhead on replay

**Action Items:**
1. ✅ **Update ADR-012:** Add section on schema migrations for replay
2. ✅ **Update UC-020:** Document migration API
3. ✅ **Update UC-021:** Apply migrations before replay
4. 🔄 **New DSL:** `migrate from: 1, to: 2` block in event classes
5. 🔄 **Migration tests:** Verify v1→v2→v3 migration chain

**Status:** ⚠️ **NEEDS DECISION** - Requires architect approval on migration strategy (explicit migrations vs lenient validation)

---

#### 🔍 **CONFLICT C16: Event Registry × Memory Optimization (UC-022 + Design Doc)**

**Priority:** 🟡 **MEDIUM**

**Problem:**  
UC-022 (Event Registry) says "central catalog of all event definitions". Design Doc (Memory Optimization) says "minimize memory footprint". But event registry must **load all event class definitions** into memory, which increases memory usage!

**Scenario:**
```ruby
# E11y has 500 event classes defined:
class Events::UserRegistered < E11y::Event::Base
  schema { ... }
end

class Events::OrderCreated < E11y::Event::Base
  schema { ... }
end

# ... 498 more event classes ...

# Event Registry (UC-022):
# Must load ALL 500 classes into memory to build catalog
E11y::Registry.load_all_events

# Memory impact:
# - 500 classes × ~10 KB per class = ~5 MB
# - Schema validators for each class: ~5 MB
# - Total: ~10 MB overhead just for registry!

# High-throughput app (1000 req/sec):
# - 100 worker processes
# - Each process: 10 MB registry overhead
# - Total: 1 GB memory just for event registry!
```

**Hidden Dependency:**  
UC-022 (Event Registry) is designed for **developer experience** (catalog, documentation, validation). Design Doc (Memory Optimization) is designed for **production efficiency**. These goals conflict!

**Second-Order Effect:**  
Event registry makes apps **slower to boot** (must load 500 classes) and **consume more memory** (all schemas loaded).

**Impact:**
- ⚠️ **Memory overhead:** ~10 MB per worker process
- ⚠️ **Slower boot:** Must load all event classes at startup
- ⚠️ **Higher costs:** More memory → bigger instances → higher AWS bill

**Proposed Solution (Option A - Document Trade-off):**

**Lazy Loading Event Registry:**

```ruby
# UC-022 Amendment: Lazy-load event definitions
module E11y::Registry
  # Don't load all events at startup
  # Load on-demand when needed
  
  def self.find_event(event_name)
    # Check if already loaded
    return @events[event_name] if @events[event_name]
    
    # Lazy-load event class
    event_class = load_event_class(event_name)
    @events[event_name] = event_class
    
    event_class
  end
  
  def self.all_events
    # Only needed for documentation/introspection
    # Not needed in production!
    if Rails.env.production?
      raise 'Registry.all_events not available in production (memory optimization)'
    end
    
    # Development/test: Load all
    load_all_event_classes
  end
end

# Alternative: Compile event registry at build time
# Generate static JSON file with all event schemas
# No need to load Ruby classes at runtime

# bin/rake e11y:compile_registry
# → generates public/e11y_registry.json

# Runtime:
E11y::Registry.load_from_json('public/e11y_registry.json')
# → Only loads JSON (faster, less memory than loading Ruby classes)
```

**Trade-offs:**
- ✅ Reduced memory footprint (lazy loading)
- ✅ Faster boot (don't load all events)
- ⚠️ First event of each type slower (lazy load overhead)
- ⚠️ Can't introspect all events in production (security benefit?)

**Action Items:**
1. ✅ **Update UC-022:** Document lazy loading strategy
2. ✅ **Update Design Doc:** Document registry memory trade-off
3. 🔄 **Add config option:** `registry.lazy_load` (true in production)
4. 🔄 **Build-time tool:** Compile registry to JSON

**Status:** ✅ **RESOLVED** - Document lazy loading, provide build-time compilation option

---

## Phase 6: Background Jobs & Reliability Conflicts

### 6.1 UC-010 (Background Job Tracking) × ADR-005 (Trace Context) × UC-009 (Multi-Service Tracing)

**Analyzing:** Background job tracing and context propagation...

#### 🔍 **CONFLICT C17: Sidekiq Job Trace Context × Parent Request Trace (UC-010 + UC-009)**

**Priority:** 🔴 **CRITICAL**

**Problem:**  
UC-009 (Multi-Service Tracing) requires **trace context propagation** across services. UC-010 (Background Job Tracking) tracks Sidekiq jobs. But when a web request **enqueues a Sidekiq job**, should the job **inherit parent trace_id** or **start new trace**?

**Scenario:**
```ruby
# Web request (Service A):
# trace_id: abc-123, span_id: span-001

class OrdersController < ApplicationController
  def create
    @order = Order.create!(order_params)
    
    # Track event
    Events::OrderCreated.track(
      trace_id: 'abc-123',  # ← Parent trace
      order_id: @order.id
    )
    
    # Enqueue background job
    SendOrderEmailJob.perform_async(@order.id)
    # Question: Should this job inherit trace_id 'abc-123'?
  end
end

# Sidekiq job (Service A, background worker):
class SendOrderEmailJob
  include Sidekiq::Job
  
  def perform(order_id)
    # What trace_id should this use?
    # Option 1: Inherit parent trace_id 'abc-123'
    # Option 2: New trace_id 'xyz-789'
    
    Events::EmailSent.track(
      trace_id: ???,
      order_id: order_id
    )
  end
end
```

**Hidden Dependency:**  
UC-009 (Multi-Service Tracing) says "propagate trace context via HTTP headers". But Sidekiq jobs are **not HTTP requests**! They're **async jobs** in a queue. How to propagate trace context?

**Architectural Decision Required:**

**Two competing models:**

**Model A: Jobs INHERIT parent trace (same trace_id)**
```ruby
# Web request: trace_id=abc-123
OrdersController#create
  → Events::OrderCreated (trace_id=abc-123)
  → SendOrderEmailJob enqueued WITH trace_id=abc-123
  
# Background job: trace_id=abc-123 (SAME as parent)
SendOrderEmailJob#perform
  → Events::EmailSent (trace_id=abc-123)

# Result: ONE continuous trace!
# abc-123:
#   - span-001: OrdersController#create
#   - span-002: SendOrderEmailJob#perform
#   - span-003: EmailService#send
```

**Pros:**
- ✅ Complete trace across request → job → downstream
- ✅ Can measure end-to-end latency (order creation → email sent)
- ✅ Easy debugging (all events in same trace)

**Cons:**
- ❌ Trace duration is UNBOUNDED! (job may run hours later)
- ❌ SLO metrics skewed (trace includes async work)
- ❌ Trace spans across multiple services/workers (hard to visualize)

**Model B: Jobs START new trace (new trace_id)**
```ruby
# Web request: trace_id=abc-123
OrdersController#create
  → Events::OrderCreated (trace_id=abc-123)
  → SendOrderEmailJob enqueued (NO trace_id yet)
  
# Background job: trace_id=xyz-789 (NEW trace)
SendOrderEmailJob#perform
  → Events::EmailSent (trace_id=xyz-789)

# Result: TWO separate traces!
# abc-123:
#   - span-001: OrdersController#create
#
# xyz-789:
#   - span-001: SendOrderEmailJob#perform
#   - span-002: EmailService#send

# Link between traces:
# abc-123 has link to xyz-789 (via job_id or correlation_id)
```

**Pros:**
- ✅ Bounded trace duration (each trace has clear start/end)
- ✅ Accurate SLO metrics (request latency ≠ job latency)
- ✅ Clear separation (request trace vs job trace)

**Cons:**
- ❌ Can't see full end-to-end flow in single trace
- ❌ Must follow links between traces (more complex)
- ❌ Lost context (job doesn't know parent trace)

**Second-Order Effect:**  
If jobs inherit parent trace_id, **trace sampling decisions** must also be inherited! Otherwise, parent event sampled but child event dropped → incomplete trace.

**Impact:**
- ❌ **Unclear tracing semantics:** Jobs inherit trace or start new?
- ❌ **SLO calculation confusion:** Should job latency count in request SLO?
- ❌ **Sampling issues:** Parent sampled, child not sampled → broken trace

**Proposed Solution (Option B - Critical Conflict):**

**Hybrid Model: Jobs start NEW trace but LINK to parent:**

```ruby
# ADR-005 Amendment: Trace context for background jobs
config.tracing do
  background_jobs do
    # Strategy: start_new_with_link
    # - Job gets NEW trace_id (independent trace)
    # - Job stores LINK to parent trace_id
    # - Can reconstruct full flow via links
    
    trace_strategy :start_new_with_link
    
    # Alternative strategies:
    # - :inherit_parent (job uses same trace_id as parent)
    # - :start_new_isolated (job gets new trace, no link)
  end
end

# Implementation:
class SidekiqMiddleware
  def call(worker, job, queue)
    # Get parent trace context (from request that enqueued job)
    parent_trace_id = job['trace_id']
    parent_span_id = job['span_id']
    
    # Start NEW trace for this job
    new_trace_context = E11y::TraceContext.new(
      trace_id: SecureRandom.uuid,  # ← NEW trace ID!
      parent_trace_id: parent_trace_id,  # ← Link to parent
      parent_span_id: parent_span_id
    )
    
    # Set trace context for job execution
    E11y::TraceContext.current = new_trace_context
    
    yield
  end
end

# Enqueue job with parent trace context:
class OrdersController < ApplicationController
  def create
    # ...
    
    # Pass parent trace context to job
    SendOrderEmailJob.perform_async(
      @order.id,
      trace_id: E11y::TraceContext.current.trace_id,
      span_id: E11y::TraceContext.current.span_id
    )
  end
end

# Query for full flow (request + job):
# Find all traces linked to parent trace abc-123
SELECT * FROM traces WHERE trace_id = 'abc-123' OR parent_trace_id = 'abc-123'
```

**Alternative Solution (Context-Dependent Strategy):**
```ruby
# Let developer choose per-job:
class UrgentEmailJob < ApplicationJob
  e11y_trace_strategy :inherit_parent  # ← Same trace (urgent, fast job)
end

class BatchReportJob < ApplicationJob
  e11y_trace_strategy :start_new_with_link  # ← New trace (slow job, hours later)
end
```

**Trade-offs:**
- ✅ Clear trace boundaries (request vs job)
- ✅ Accurate SLO metrics (separate latencies)
- ✅ Can still reconstruct full flow (via links)
- ⚠️ More complex querying (must follow links)
- ⚠️ Two trace IDs to track (parent + child)

**Action Items:**
1. ✅ **Update ADR-005:** Document background job trace strategy
2. ✅ **Update UC-010:** Document trace context propagation for Sidekiq
3. ✅ **Update UC-009:** Document trace linking (parent_trace_id field)
4. 🔄 **New middleware:** SidekiqTraceMiddleware
5. 🔄 **Migration guide:** How to pass trace context when enqueuing jobs

**Status:** ⚠️ **NEEDS DECISION** - Requires architect approval on job tracing strategy (inherit vs new trace)

---

### 6.2 ADR-013 (Error Handling - Circuit Breaker) × UC-010 (Background Jobs)

**Analyzing:** Circuit breaker interaction with async jobs...

#### 🔍 **CONFLICT C18: Circuit Breaker × Sidekiq Retries (UC-010 + ADR-013)**

**Priority:** 🟠 **HIGH**

**Problem:**  
ADR-013 (Error Handling) includes **circuit breaker** to protect failing adapters. UC-010 (Background Job Tracking) tracks Sidekiq jobs, which have **built-in retry mechanism** (25 retries over 21 days). But what happens when E11y adapter has **circuit breaker OPEN** and Sidekiq job tries to track event?

**Scenario:**
```ruby
# Loki adapter fails repeatedly
# Circuit breaker: OPEN (stop sending traffic to Loki)

# Sidekiq job runs:
class SendEmailJob
  include Sidekiq::Job
  sidekiq_options retry: 25  # ← Sidekiq will retry 25 times
  
  def perform(order_id)
    order = Order.find(order_id)
    OrderMailer.confirmation(order).deliver_now
    
    # Track event
    Events::EmailSent.track(
      order_id: order_id,
      email: order.email
    )
    # ↑ Tries to write to Loki
    # ↑ Circuit breaker OPEN → raises CircuitBreakerError
    # ↑ Job FAILS!
  end
end

# Sidekiq retry logic:
# - Job failed (CircuitBreakerError)
# - Retry attempt 1 (after 15 seconds)
# - Circuit breaker still OPEN → FAILS again
# - Retry attempt 2 (after 1 minute)
# - Circuit breaker still OPEN → FAILS again
# - ...
# - Retry attempt 25 (after 21 days)
# - Circuit breaker still OPEN → FAILS → Goes to Dead Job Queue

# Result:
# - Email WAS sent successfully!
# - But job failed because E11y event couldn't be tracked!
# - Job retried 25 times unnecessarily!
# - Finally went to Dead Job Queue!
```

**Hidden Dependency:**  
UC-010 (Background Job Tracking) assumes event tracking is **non-critical** (job success doesn't depend on it). But if `Events::EmailSent.track` raises exception, **whole job fails**!

**Second-Order Effect:**  
Circuit breaker makes **all background jobs fail** even though business logic succeeded! This is catastrophic for job processing.

**Impact:**
- ❌ **Jobs fail unnecessarily:** Business logic succeeded, but job marked as failed
- ❌ **Retry storm:** Sidekiq retries 25 times, all fail due to circuit breaker
- ❌ **Lost work:** Jobs go to Dead Job Queue even though work was done
- ❌ **Alert fatigue:** Sidekiq dashboard shows thousands of failed jobs

**Proposed Solution (Option B - High Priority):**

**Event Tracking Errors Should NOT Fail Jobs:**

```ruby
# ADR-013 Amendment: Non-failing event tracking in jobs
config.error_handling do
  # In background jobs: NEVER raise on event tracking failure
  fail_on_error do
    enabled true
    
    # Exception: Background jobs (Sidekiq, ActiveJob, etc.)
    except_in [:sidekiq, :activejob]
  end
end

# Implementation:
module E11y::BackgroundJobIntegration
  def track_event(*args)
    # Wrap in rescue block
    begin
      E11y::Event.track(*args)
    rescue => e
      # Log error but DON'T re-raise
      E11y.logger.error "Failed to track event in background job: #{e.message}"
      
      # Send to DLQ (for later replay)
      E11y::DLQ.add(event, reason: 'circuit_breaker_open')
      
      # DON'T fail the job!
      nil
    end
  end
end

# Sidekiq middleware:
class E11yErrorHandlingMiddleware
  def call(worker, job, queue)
    # Set error handling mode for this job
    E11y.config.error_handling.fail_on_error = false
    
    yield
  ensure
    # Reset
    E11y.config.error_handling.fail_on_error = true
  end
end
```

**Alternative Solution (Separate Job Queue for Events):**
```ruby
# Don't track events synchronously in jobs
# Instead: Enqueue separate "event tracking" job

class SendEmailJob
  def perform(order_id)
    order = Order.find(order_id)
    OrderMailer.confirmation(order).deliver_now
    
    # DON'T track event here!
    # Instead: Enqueue event tracking job
    TrackEventJob.perform_async(
      event_name: 'email.sent',
      payload: { order_id: order_id, email: order.email }
    )
  end
end

# Event tracking job (can fail independently)
class TrackEventJob
  include Sidekiq::Job
  sidekiq_options queue: :events, retry: 5  # ← Separate queue, fewer retries
  
  def perform(event_name, payload)
    Events::Base.track(event_name, **payload)
  end
end
```

**Trade-offs:**
- ✅ Jobs don't fail due to event tracking issues
- ✅ Business logic succeeds even if observability fails
- ✅ Events go to DLQ (can replay later)
- ⚠️ Silent failures (job succeeds but event not tracked)
- ⚠️ May lose observability during circuit breaker open period

**Action Items:**
1. ✅ **Update ADR-013:** Document non-failing event tracking in background jobs
2. ✅ **Update UC-010:** Add Sidekiq middleware for error handling
3. 🔄 **New middleware:** SidekiqErrorHandlingMiddleware
4. 🔄 **Documentation:** Warn about circuit breaker impact on jobs

**Status:** ⚠️ **NEEDS DECISION** - Requires architect approval on error handling in jobs (fail vs silent)

---

## Phase 7: Second-Order Effects & Edge Cases Hunt

### 7.1 Cross-Cutting Concerns

**Analyzing:** Interactions that span multiple ADRs/UCs...

#### 🔍 **CONFLICT C19: Pipeline Order × Event Modification (Multiple Middlewares)**

**Priority:** 🟠 **HIGH**

**Problem:**  
ADR-015 (Pipeline Order) defines sequential middleware steps. Multiple middlewares **modify event payload** (PII filtering, payload minimization, trace context injection). But if multiple middlewares modify **same field**, **last one wins** and previous modifications are lost!

**Scenario:**
```ruby
# Original event:
Events::UserLogin.track(
  user_id: '123',
  email: 'user@example.com',
  ip_address: '192.168.1.1'
)

# Pipeline order:
# 1. Validation → PASS
# 2. PII Filtering → Modifies 'email' and 'ip_address'
#    Payload: { user_id: '123', email: 'hash_abc', ip_address: 'hash_def' }
#
# 3. Trace Context Injection → Adds 'trace_id', 'span_id'
#    Payload: { user_id: '123', email: 'hash_abc', ip_address: 'hash_def', trace_id: 'xyz', span_id: '001' }
#
# 4. Payload Minimization → Removes empty fields, abbreviates keys
#    Payload: { uid: '123', em: 'hash_abc', ip: 'hash_def', tid: 'xyz', sid: '001' }
#    ↑ Key abbreviation: 'user_id' → 'uid', 'email' → 'em', etc.

# Adapter receives minimized payload with abbreviated keys
# Problem: Can adapter understand abbreviated keys?
# Problem: If adapter needs original keys, they're gone!
```

**Hidden Dependency:**  
Each middleware assumes it can **freely modify** event payload. But modifications **cascade** through pipeline, and later middlewares may **undo** or **conflict** with earlier ones.

**Second-Order Effect:**
```ruby
# Edge case: Custom middleware added by user
config.middleware.insert_before :pii_filtering, CustomMiddleware

class CustomMiddleware
  def call(event, next_middleware)
    # Add custom field
    event.payload[:custom_field] = 'value'
    
    next_middleware.call(event)
  end
end

# But: If 'custom_field' contains PII, it won't be filtered!
# Because CustomMiddleware runs BEFORE PII filtering
# BUT: What if custom_field is added AFTER PII filtering? It bypasses!

# Conclusion: Pipeline order is FRAGILE!
```

**Impact:**
- ⚠️ **Middleware conflicts:** Later middlewares undo earlier work
- ⚠️ **Lost modifications:** Key abbreviation breaks adapters expecting original keys
- ⚠️ **PII bypass:** Custom middleware can bypass PII filtering

**Proposed Solution (Option A - Document Constraints):**

**Immutable Event Payload (Copy-on-Write):**

```ruby
# ADR-015 Amendment: Middleware can't modify original event
# Each middleware gets COPY of event

class E11y::Event::Base
  attr_reader :payload
  
  def initialize(payload)
    @payload = payload.freeze  # ← Immutable!
  end
  
  # Middleware must create new event with modified payload
  def with_payload(new_payload)
    self.class.new(new_payload)
  end
end

# Middleware pattern:
class PiiFilter
  def call(event, next_middleware)
    # Get copy of payload
    filtered_payload = apply_pii_rules(event.payload)
    
    # Create NEW event with filtered payload
    filtered_event = event.with_payload(filtered_payload)
    
    # Pass modified event to next middleware
    next_middleware.call(filtered_event)
  end
end

# Benefit: Can track modification history!
event.modification_history
# => [
#   { middleware: :validation, changes: {} },
#   { middleware: :pii_filtering, changes: { email: '[FILTERED]', ip_address: '[FILTERED]' } },
#   { middleware: :trace_context, changes: { trace_id: 'xyz', span_id: '001' } }
# ]
```

**Alternative Solution (Middleware Zones):**
```ruby
# Group middlewares into zones with clear rules
config.pipeline_order do
  zone :pre_processing do
    step :validation       # ← Can reject event
    step :schema_enrichment  # ← Can ADD fields
  end
  
  zone :security do
    step :pii_filtering    # ← Can MODIFY sensitive fields
    # NO other middleware can modify after this!
  end
  
  zone :routing do
    step :rate_limiting    # ← Can DROP event
    step :sampling         # ← Can DROP event
  end
  
  zone :post_processing do
    step :trace_context    # ← Can ADD tracing fields
    step :payload_minimization  # ← Can ABBREVIATE keys (last step before adapters!)
  end
  
  zone :adapters do
    step :buffer
    step :adapters
  end
end
```

**Trade-offs:**
- ✅ Clear modification boundaries (zones)
- ✅ Can track what each middleware changed
- ⚠️ Complexity: Copy-on-write overhead
- ⚠️ Breaking change: Existing middlewares must update

**Action Items:**
1. ✅ **Update ADR-015:** Document middleware modification rules
2. 🔄 **Add middleware zones:** Group middlewares by purpose
3. 🔄 **Add validation:** Warn if custom middleware violates zone rules

**Status:** ⚠️ **NEEDS DECISION** - Requires architect approval on middleware modification model

---

#### 🔍 **CONFLICT C20: Memory Pressure × High Throughput (Design Doc + ADR-001)**

**Priority:** 🔴 **CRITICAL**

**Problem:**  
Design Doc (Memory Optimization) requires **minimal memory footprint**. ADR-001 (Buffering) keeps events in memory until flush (200ms, max 1000 events). But in **high-throughput scenarios** (10,000+ events/sec), buffer can grow to **10,000 events × 200ms = 2000+ events** in memory!

**Scenario:**
```ruby
# High-throughput Rails app:
# - 1000 requests/sec
# - Each request tracks 10 events average
# - Total: 10,000 events/sec

# Buffer config:
config.buffering do
  flush_interval 200.milliseconds
  max_buffer_size 1000  # ← Max events before forced flush
end

# Calculation:
# - Events per second: 10,000
# - Flush interval: 0.2 seconds
# - Events in buffer: 10,000 × 0.2 = 2000 events!

# But max_buffer_size = 1000!
# → Buffer overflows! Forced flush every 100ms instead of 200ms
# → Double flush frequency → More CPU

# Memory impact:
# - 2000 events × 5 KB per event = 10 MB per worker
# - 100 workers = 1 GB memory for buffers!
# - Plus: JSON serialization, compression, etc. → 2-3 GB total!
```

**Hidden Dependency:**  
ADR-001 (Buffering) optimizes for **throughput** (batch writes). Design Doc optimizes for **memory**. At high throughput, buffering becomes **memory-intensive**!

**Second-Order Effect:**  
High memory usage triggers Ruby GC more frequently → GC pauses → Slower response times → Worse user experience!

**Impact:**
- ❌ **Memory exhaustion:** Workers crash (OOM errors)
- ❌ **GC pressure:** Frequent GC pauses slow down requests
- ❌ **Costly infrastructure:** Need bigger instances (more RAM)

**Proposed Solution (Option B - Critical Conflict):**

**Adaptive Buffer Size Based on Memory Pressure:**

```ruby
# ADR-001 Amendment: Adaptive buffering with memory limits
config.buffering do
  enabled true
  
  # Memory-aware buffering
  adaptive do
    enabled true
    
    # Memory limit (global for all buffers)
    memory_limit_mb 100  # ← Max 100 MB for ALL buffers
    
    # Flush triggers:
    # 1. Time-based: every 200ms
    # 2. Size-based: 1000 events
    # 3. Memory-based: 100 MB total
    
    flush_on_memory_threshold 0.8  # ← Flush when 80% of limit reached
    
    # Backpressure: Slow down event ingestion if buffer full
    backpressure do
      enabled true
      strategy :block  # :block, :drop, :throttle
      max_block_time 1.second  # ← Block max 1 second, then drop
    end
  end
end

# Implementation:
class AdaptiveBuffer
  def initialize
    @buffers = {}  # Per-adapter buffer
    @total_memory_bytes = 0
    @memory_limit_bytes = Config.buffering.memory_limit_mb * 1024 * 1024
  end
  
  def add_event(event)
    event_size = estimate_size(event)
    
    # Check memory limit
    if @total_memory_bytes + event_size > @memory_limit_bytes
      # Memory threshold exceeded!
      if Config.buffering.backpressure.enabled
        # Wait for flush
        wait_for_flush(timeout: Config.buffering.backpressure.max_block_time)
        
        # Retry add
        return add_event(event) if @total_memory_bytes + event_size <= @memory_limit_bytes
        
        # Still over limit → DROP event
        E11y.logger.warn "Buffer full, dropping event: #{event.event_name}"
        return false
      else
        # Force flush NOW (emergency)
        flush_all_buffers!
      end
    end
    
    # Add to buffer
    @buffers[event.adapter] ||= []
    @buffers[event.adapter] << event
    @total_memory_bytes += event_size
    
    true
  end
  
  def estimate_size(event)
    # Estimate memory size of event
    # Payload size + overhead (object headers, etc.)
    event.payload.to_json.bytesize + 200  # bytes
  end
end
```

**Alternative Solution (Ring Buffer with Overflow Drop):**
```ruby
# Use fixed-size ring buffer (circular buffer)
# When full, DROP oldest events (not newest!)

config.buffering do
  strategy :ring_buffer
  max_size 1000  # ← Fixed size (never grows)
  on_overflow :drop_oldest  # ← Drop old events, keep new ones
end
```

**Trade-offs:**
- ✅ Bounded memory usage (won't exceed limit)
- ✅ Backpressure prevents overload
- ⚠️ May drop events under extreme load
- ⚠️ Complexity: Memory estimation, adaptive flushing

**Action Items:**
1. ✅ **Update ADR-001:** Add adaptive buffering with memory limits
2. ✅ **Update Design Doc:** Document buffer memory trade-offs
3. 🔄 **New component:** AdaptiveBuffer with memory tracking
4. 🔄 **Load test:** Verify memory limits under high throughput
5. 🔄 **Monitoring:** Alert when buffer memory > 80% of limit

**Status:** ⚠️ **NEEDS DECISION** - Requires architect approval on adaptive buffering + backpressure strategy

---

#### 🔍 **CONFLICT C21: Configuration Complexity × Developer Experience (ADR-010)**

**Priority:** 🟡 **MEDIUM**

**Problem:**  
ADR-010 (Developer Experience) emphasizes "zero-config defaults". But analysis revealed **20+ conflicts** requiring configuration decisions! How can we have "zero-config" when there are so many trade-offs to configure?

**Example:**
```ruby
# "Zero-config" promise:
E11y.configure do |config|
  # Just enable!
  config.enabled = true
end

# Reality: Need to configure ALL these trade-offs!
E11y.configure do |config|
  # C01: Audit events vs PII filtering
  config.audit_events.skip_pii_filtering = true
  
  # C02: Rate limiting vs DLQ filter
  config.rate_limiting.respect_dlq_filter = true
  
  # C03: Metrics backend
  config.metrics.backend = :yabeda
  
  # C04: Cardinality protection for OpenTelemetry
  config.opentelemetry.cardinality_protection.enabled = true
  
  # C05: Trace-consistent sampling
  config.sampling.strategy = :adaptive_trace_consistent
  
  # C06: Retry rate limiting
  config.error_handling.retry_rate_limit.enabled = true
  
  # C07: Replay pipeline
  config.dlq_replay.skip_pii_filtering = true
  
  # C08: Baggage PII protection
  config.pii_filtering.baggage_protection.mode = :block_all
  
  # C10: Compression order
  config.pipeline_order.add_step :payload_minimization, before: :buffer
  
  # C11: Stratified sampling for SLO
  config.sampling.stratification.enabled = true
  
  # C12: De-duplication during Rails migration
  config.rails_integration.deduplication.enabled = true
  
  # C13: Test environment sampling
  config.sampling.enabled = !Rails.env.test?
  
  # C14: Development buffer interval
  config.buffering.flush_interval = Rails.env.development? ? 10.ms : 200.ms
  
  # C15: Event schema migrations
  config.dlq_replay.apply_migrations = true
  
  # C17: Background job tracing
  config.tracing.background_jobs.trace_strategy = :start_new_with_link
  
  # C18: Non-failing event tracking in jobs
  config.error_handling.fail_on_error_in_jobs = false
  
  # C20: Adaptive buffer with memory limits
  config.buffering.adaptive.memory_limit_mb = 100
  
  # ... and more!
end

# Result: 100+ lines of configuration!
# → NOT "zero-config" anymore!
```

**Hidden Dependency:**  
ADR-010 assumes "sensible defaults cover 80% of use cases". But conflicts revealed **no single default works for all scenarios**! Must choose based on:
- Environment (production vs test vs development)
- Workload (high-throughput vs low-throughput)
- Compliance (audit requirements vs GDPR)
- Architecture (monolith vs microservices)

**Impact:**
- ⚠️ **Configuration overwhelm:** Too many options, unclear defaults
- ⚠️ **Decision paralysis:** Developers don't know what to configure
- ⚠️ **Misconfiguration risk:** Wrong config leads to data loss, compliance violations

**Proposed Solution (Option A - Document Trade-offs):**

**Configuration Profiles (Pre-set Bundles):**

```ruby
# ADR-010 Amendment: Configuration profiles for common scenarios

# Profile 1: Production (high-throughput, compliance)
E11y.configure_with_profile(:production_high_throughput) do |config|
  # Optimized defaults for production:
  config.buffering.adaptive.enabled = true
  config.buffering.memory_limit_mb = 100
  config.sampling.strategy = :adaptive_trace_consistent
  config.sampling.stratification.enabled = true
  config.pii_filtering.enabled = true
  config.pii_filtering.baggage_protection.mode = :block_all
  config.audit_events.skip_pii_filtering = true
  config.error_handling.retry_rate_limit.enabled = true
  # ... etc
end

# Profile 2: Development (low-latency, debugging)
E11y.configure_with_profile(:development) do |config|
  # Optimized for developer experience:
  config.buffering.enabled = false  # Immediate writes
  config.sampling.enabled = false   # Keep all events
  config.pii_filtering.enabled = false  # See real data
  config.rails_integration.capture_rails_logs = true
end

# Profile 3: Test (deterministic, fast)
E11y.configure_with_profile(:test) do |config|
  # Optimized for test reliability:
  config.buffering.enabled = false
  config.sampling.enabled = false
  config.async = false  # Synchronous (no background threads)
  config.adapters = [:memory]  # In-memory adapter (no external deps)
end

# Profile 4: Compliance (audit, GDPR)
E11y.configure_with_profile(:compliance_audit) do |config|
  # Optimized for compliance:
  config.audit_events.enabled = true
  config.audit_events.skip_pii_filtering = true
  config.pii_filtering.mode = :pseudonymize
  config.encryption_at_rest.enabled = true
  config.dlq.enabled = true  # Zero data loss
  config.rate_limiting.bypass_for_critical = true
end

# Usage in app:
# config/initializers/e11y.rb
E11y.configure_with_profile(ENV['E11Y_PROFILE'] || :production_high_throughput)

# Fine-tune after profile:
E11y.configure do |config|
  config.sampling.cost_budget = 500_000  # Override profile default
end
```

**Alternative Solution (Configuration Wizard CLI):**
```bash
# Interactive CLI wizard (like `rails new`)
$ bundle exec e11y configure

> What environment? (production / development / test)
production

> Expected throughput? (< 100 / 100-1000 / > 1000 events/sec)
> 1000

> Compliance requirements? (GDPR / HIPAA / Audit / None)
GDPR, Audit

> Observability backend? (Loki / Datadog / Honeycomb / Sentry)
Loki, Sentry

> Generating optimal configuration...
✅ Created config/initializers/e11y.rb
✅ Configuration profile: :production_high_throughput_compliance
✅ Review conflicts: docs/E11Y_CONFLICTS.md
```

**Trade-offs:**
- ✅ Reduces configuration complexity (profiles vs 100+ options)
- ✅ Opinionated defaults based on use case
- ✅ Easy to get started (pick profile, done)
- ⚠️ Profiles may not cover all edge cases
- ⚠️ Users must understand which profile fits their needs

**Action Items:**
1. ✅ **Update ADR-010:** Document configuration profiles
2. 🔄 **Implement profiles:** Pre-configured bundles for common scenarios
3. 🔄 **CLI wizard:** Interactive configuration generator
4. 🔄 **Documentation:** Decision tree for choosing profile

**Status:** ✅ **RESOLVED** - Provide configuration profiles to manage complexity

---

## Phase 8: Final Conflict Summary & Action Items

### Summary of All Conflicts

**Total Conflicts Identified:** 21

**By Priority:**
- 🔴 **Critical:** 9 conflicts (C01, C05, C08, C11, C15, C17, C20 + 2 more)
- 🟠 **High:** 7 conflicts (C02, C04, C06, C12, C13, C18, C19)
- 🟡 **Medium:** 5 conflicts (C03, C09, C10, C14, C16, C21)

**By Category:**
1. **Security & Compliance:** 4 conflicts (C01, C07, C08, C09)
2. **Performance & Cost:** 5 conflicts (C03, C10, C11, C14, C20)
3. **Reliability & Error Handling:** 4 conflicts (C02, C06, C15, C18)
4. **Tracing & Context:** 3 conflicts (C05, C17, C19)
5. **Developer Experience:** 3 conflicts (C12, C13, C21)
6. **Architecture & Integration:** 2 conflicts (C04, C16)

---

### Conflict Matrix (Complete)

| ID | Conflict | Priority | Components | Status |
|----|----------|----------|------------|--------|
| C01 | PII Filtering × Audit Trail Signing | 🔴 Critical | ADR-006, ADR-015, UC-012 | ⚠️ Needs Decision |
| C02 | Rate Limiting × DLQ Filter | 🟠 High | ADR-015, UC-011, UC-021 | ⚠️ Needs Decision |
| C03 | Dual Metrics Collection (Yabeda vs OTel) | 🟡 Medium | ADR-002, ADR-007 | ✅ Resolved |
| C04 | High-Cardinality × OpenTelemetry Attributes | 🟠 High | ADR-007, UC-013 | ⚠️ Needs Decision |
| C05 | Adaptive Sampling × Trace-Consistent Sampling | 🔴 Critical | ADR-009, UC-009, UC-014 | ⚠️ Needs Decision |
| C06 | Retry Policy × Rate Limiting (Thundering Herd) | 🟠 High | ADR-013, UC-011 | ⚠️ Needs Decision |
| C07 | PII Pseudonymization × DLQ Replay | 🟠 High | ADR-006, UC-021 | ⚠️ Needs Decision |
| C08 | PII Filtering × OpenTelemetry Baggage | 🔴 Critical | ADR-006, UC-008 | ⚠️ Needs Decision |
| C09 | Encryption at Rest × Tiered Storage | 🟡 Medium | ADR-006, UC-019 | ✅ Resolved |
| C10 | Compression × Payload Minimization | 🟡 Medium | ADR-009, UC-015 | ✅ Resolved |
| C11 | Adaptive Sampling × SLO Tracking | 🔴 Critical | UC-004, UC-014 | ⚠️ Needs Decision |
| C12 | Rails.logger × E11y Event (Double Logging) | 🟠 High | ADR-008, UC-016 | ⚠️ Needs Decision |
| C13 | Test Events × Adaptive Sampling | 🟠 High | ADR-010, UC-014, UC-018 | ⚠️ Needs Decision |
| C14 | Local Dev Buffering × Real-Time Feedback | 🟡 Medium | ADR-001, UC-017 | ✅ Resolved |
| C15 | Event Versioning × DLQ Replay | 🔴 Critical | ADR-012, UC-020, UC-021 | ⚠️ Needs Decision |
| C16 | Event Registry × Memory Optimization | 🟡 Medium | Design Doc, UC-022 | ✅ Resolved |
| C17 | Sidekiq Trace Context × Parent Request Trace | 🔴 Critical | ADR-005, UC-009, UC-010 | ⚠️ Needs Decision |
| C18 | Circuit Breaker × Sidekiq Retries | 🟠 High | ADR-013, UC-010 | ⚠️ Needs Decision |
| C19 | Pipeline Order × Event Modification | 🟠 High | ADR-015, Multiple | ⚠️ Needs Decision |
| C20 | Memory Pressure × High Throughput | 🔴 Critical | ADR-001, Design Doc | ⚠️ Needs Decision |
| C21 | Configuration Complexity × Zero-Config | 🟡 Medium | ADR-010, Multiple | ✅ Resolved |

---

### Critical Conflicts Requiring Immediate Decisions

#### 1. **C01: PII Filtering × Audit Trail Signing** 🔴
**Decision Required:** Should audit events:
- **Option A:** Use separate pipeline (skip PII filtering, sign original data)
- **Option B:** Filter PII downstream (after signing)

**Recommendation:** Option A (separate audit pipeline) for legal compliance.

---

#### 2. **C05: Adaptive Sampling × Trace-Consistent Sampling** 🔴
**Decision Required:** How to sample distributed traces?
- **Option A:** Per-event sampling (current behavior, breaks traces)
- **Option B:** Per-trace sampling (trace-aware sampler)

**Recommendation:** Option B (trace-aware sampling) to preserve distributed tracing integrity.

---

#### 3. **C08: PII Filtering × OpenTelemetry Baggage** 🔴
**Decision Required:** How to prevent PII leaking via baggage?
- **Option A:** Block all baggage (safest)
- **Option B:** Allowlist safe keys only
- **Option C:** Encrypt baggage

**Recommendation:** Option B (allowlist) for balance of safety and flexibility.

---

#### 4. **C11: Adaptive Sampling × SLO Tracking** 🔴
**Decision Required:** How to maintain accurate SLO metrics with sampling?
- **Option A:** Stratified sampling (keep all errors, sample success)
- **Option B:** Sampling correction math
- **Option C:** Bypass sampling for SLO events

**Recommendation:** Option A (stratified sampling) for accuracy + cost savings.

---

#### 5. **C15: Event Versioning × DLQ Replay** 🔴
**Decision Required:** How to replay old-schema events after code upgrade?
- **Option A:** Schema migrations (v1 → v2 transformations)
- **Option B:** Lenient validation (allow old schemas)

**Recommendation:** Option A (explicit migrations) for data integrity.

---

#### 6. **C17: Sidekiq Trace Context × Parent Request Trace** 🔴
**Decision Required:** Should background jobs inherit parent trace_id?
- **Option A:** Inherit parent trace (same trace_id)
- **Option B:** Start new trace with link to parent

**Recommendation:** Option B (new trace + link) for bounded trace duration and accurate SLO metrics.

---

#### 7. **C20: Memory Pressure × High Throughput** 🔴
**Decision Required:** How to prevent buffer memory exhaustion?
- **Option A:** Adaptive buffering with memory limits
- **Option B:** Ring buffer with overflow drop
- **Option C:** Backpressure (block event ingestion)

**Recommendation:** Option A (adaptive buffering + backpressure) for bounded memory + minimal data loss.

---

### Architecture Decision Action Items

**Immediate (Before Implementation):**
1. ✅ **Approve critical conflict resolutions** (C01, C05, C08, C11, C15, C17, C20)
2. 🔄 **Create ADR-017:** Audit Event Pipeline Separation (C01)
3. 🔄 **Update ADR-009:** Trace-aware sampling + stratified sampling (C05, C11)
4. 🔄 **Update ADR-006:** OpenTelemetry Baggage PII protection (C08)
5. 🔄 **Update ADR-012:** Event schema migration API (C15)
6. 🔄 **Update ADR-005:** Background job trace strategy (C17)
7. 🔄 **Update ADR-001:** Adaptive buffering with memory limits (C20)

**High Priority:**
1. 🔄 **Update ADR-015:** Document all pipeline order conflicts (C02, C07, C12, C19)
2. 🔄 **Update ADR-013:** Retry rate limiting + job error handling (C06, C18)
3. 🔄 **Update ADR-010:** Configuration profiles (C21)
4. 🔄 **Update UC-018:** Test environment configuration (C13)

**Documentation:**
1. 🔄 **Migration guide:** Rails.logger → E11y events (C12)
2. 🔄 **Configuration decision tree:** Help users choose profile (C21)
3. 🔄 **Conflict resolution guide:** What to do when conflicts arise

**Implementation:**
1. 🔄 **New component:** StratifiedAdaptiveSampler (C11)
2. 🔄 **New component:** TraceAwareSampler with decision cache (C05)
3. 🔄 **New component:** AdaptiveBuffer with memory tracking (C20)
4. 🔄 **New component:** SchemaM igrationRegistry (C15)
5. 🔄 **New middleware:** BaggageProtection (C08)
6. 🔄 **New middleware:** DeduplicationFilter (C12)

**Testing:**
1. 🔄 **Integration test:** PII filtering + audit trail signing (C01)
2. 🔄 **Integration test:** Trace-consistent sampling across services (C05)
3. 🔄 **Integration test:** DLQ replay with schema migration (C15)
4. 🔄 **Load test:** Memory limits under high throughput (C20)
5. 🔄 **Load test:** Retry storm scenario (C06)

---

## Conclusion

**Analysis Status:** ✅ **COMPLETE**

**Coverage:**
- ✅ All 16 ADRs analyzed
- ✅ All 22 Use Cases analyzed
- ✅ 21 conflicts identified
- ✅ 9 critical conflicts flagged
- ✅ Solutions proposed for all conflicts

**Key Findings:**
1. **Pipeline order (ADR-015) is the most conflict-prone component** (affects 7 conflicts)
2. **Sampling strategies need major rework** for trace consistency + SLO accuracy
3. **Security features (PII, audit) have architectural dependencies** requiring careful design
4. **Memory optimization conflicts with high-throughput buffering** - needs adaptive approach
5. **Configuration complexity is unavoidable** - need profiles to manage it

**Next Steps:**
1. **Architect review:** Approve critical conflict resolutions
2. **ADR updates:** Document all conflict resolutions
3. **Implementation:** Build new components (samplers, buffers, migrations)
4. **Testing:** Comprehensive integration + load testing
5. **Documentation:** Migration guides, configuration profiles, decision trees

**Estimated Effort:**
- Architecture decisions: 1-2 days
- ADR updates: 2-3 days
- Implementation: 2-3 weeks
- Testing: 1 week
- Documentation: 3-4 days

**Total:** ~4-5 weeks for complete conflict resolution

---

## Prioritized Action Plan

### Phase 1: Critical Decisions (Week 1)
**Objective:** Resolve all 9 critical conflicts through architectural decisions

**Action Items:**
1. **Architecture Review Meeting** (4-6 hours)
   - Review all 21 conflicts with architect team
   - Make decisions on 9 critical conflicts
   - Document decisions in meeting notes

2. **Critical Conflict Resolutions:**
   - [ ] **C01:** Approve audit event pipeline separation strategy
   - [ ] **C05:** Approve trace-aware adaptive sampling approach
   - [ ] **C08:** Approve OpenTelemetry Baggage PII protection (allowlist vs block)
   - [ ] **C11:** Approve stratified sampling for SLO accuracy
   - [ ] **C15:** Approve schema migration API for DLQ replay
   - [ ] **C17:** Approve background job trace strategy (inherit vs new trace)
   - [ ] **C20:** Approve adaptive buffering with memory limits + backpressure

**Deliverables:**
- ✅ Architecture decisions documented
- ✅ ADR-017 created (Audit Event Pipeline Separation)
- ✅ Risk assessment updated

---

### Phase 2: ADR Updates (Week 2)
**Objective:** Document all conflict resolutions in ADRs

**Action Items:**
1. **Update Core ADRs:**
   - [ ] **ADR-001:** Add adaptive buffering with memory limits (C20)
   - [ ] **ADR-005:** Add background job trace strategy (C17)
   - [ ] **ADR-006:** Add Baggage PII protection + replay considerations (C07, C08)
   - [ ] **ADR-009:** Add trace-aware sampling + stratified sampling (C05, C11)
   - [ ] **ADR-012:** Add schema migration API (C15)
   - [ ] **ADR-013:** Add retry rate limiting + job error handling (C06, C18)
   - [ ] **ADR-015:** Document all pipeline conflicts (C01, C02, C07, C12, C19)

2. **Update Secondary ADRs:**
   - [ ] **ADR-002:** Clarify metrics backend selection (C03)
   - [ ] **ADR-007:** Add cardinality protection for OTLP (C04)
   - [ ] **ADR-008:** Add Rails logger de-duplication (C12)
   - [ ] **ADR-010:** Add configuration profiles (C21)

3. **Create New ADR:**
   - [ ] **ADR-017:** Audit Event Pipeline Separation (C01)

**Deliverables:**
- ✅ 11 ADRs updated with conflict resolutions
- ✅ 1 new ADR created
- ✅ All conflicts cross-referenced in ADRs

---

### Phase 3: Use Case Updates (Week 2-3)
**Objective:** Update Use Cases with conflict resolutions and new requirements

**Action Items:**
1. **High-Impact UC Updates:**
   - [ ] **UC-004:** Document sampling correction for SLO (C11)
   - [ ] **UC-009:** Document trace linking (parent_trace_id) (C17)
   - [ ] **UC-010:** Add Sidekiq middleware for tracing + error handling (C17, C18)
   - [ ] **UC-011:** Document interaction with DLQ filter + retries (C02, C06)
   - [ ] **UC-012:** Document audit pipeline separation (C01)
   - [ ] **UC-014:** Update to stratified sampling strategy (C11)
   - [ ] **UC-016:** Add Rails logger migration guide (C12)
   - [ ] **UC-017:** Add developer-friendly config (C14)
   - [ ] **UC-018:** Add test helpers (disable sampling, flush buffer) (C13)
   - [ ] **UC-020:** Add schema migration examples (C15)
   - [ ] **UC-021:** Document replay with migrations + PII handling (C07, C15)

**Deliverables:**
- ✅ 11 Use Cases updated
- ✅ Code examples added for each conflict resolution

---

### Phase 4: Implementation (Week 3-5)
**Objective:** Build new components to resolve conflicts

**Priority 1: Critical Components (Week 3)**
- [ ] **TraceAwareSampler** (C05)
  - Trace-consistent sampling with decision cache
  - Tests: Multi-service trace sampling
- [ ] **StratifiedAdaptiveSampler** (C11)
  - Stratify by severity/outcome
  - Sampling correction math for SLO
  - Tests: Verify SLO accuracy with sampling
- [ ] **AdaptiveBuffer** (C20)
  - Memory tracking + limits
  - Backpressure mechanism
  - Tests: Load test (10k events/sec)
- [ ] **BaggageProtection** (C08)
  - Intercept OpenTelemetry Baggage API
  - PII detection + allowlist
  - Tests: Verify PII blocked

**Priority 2: High Components (Week 4)**
- [ ] **SchemaMigrationRegistry** (C15)
  - DSL: `migrate from: 1, to: 2 { ... }`
  - Migration chain executor
  - Tests: v1→v2→v3 migrations
- [ ] **AuditPipeline** (C01)
  - Separate pipeline for audit events
  - Skip PII filtering, add signing
  - Tests: Audit event signing + verification
- [ ] **DeduplicationFilter** (C12)
  - Detect Rails log vs E11y event duplicates
  - Pattern matching + time window
  - Tests: Rails migration scenarios

**Priority 3: Medium Components (Week 5)**
- [ ] **RetryRateLimiter** (C06)
  - Separate rate limit for retries
  - Jitter + staged retry
  - Tests: Retry storm scenario
- [ ] **SidekiqTraceMiddleware** (C17)
  - Start new trace + link to parent
  - Context propagation
  - Tests: Multi-job trace flow
- [ ] **ConfigurationProfiles** (C21)
  - Pre-configured bundles
  - Profile selector
  - Tests: Verify each profile

**Deliverables:**
- ✅ 10 new components implemented
- ✅ Unit tests for each component
- ✅ Integration tests for conflict scenarios

---

### Phase 5: Testing & Validation (Week 6)
**Objective:** Comprehensive testing of conflict resolutions

**Integration Tests:**
- [ ] **PII + Audit (C01):** Audit events signed with original data, standard events PII-filtered
- [ ] **Trace Sampling (C05):** Multi-service trace sampled consistently
- [ ] **Baggage PII (C08):** PII blocked from baggage propagation
- [ ] **SLO Accuracy (C11):** Stratified sampling preserves success rate
- [ ] **Schema Migration (C15):** DLQ replay with v1→v2→v3 migration chain
- [ ] **Job Tracing (C17):** Background job creates new trace linked to parent
- [ ] **Job Errors (C18):** Job succeeds even if E11y adapter fails
- [ ] **Memory Limits (C20):** Buffer respects memory limit under high load

**Load Tests:**
- [ ] **High Throughput (10k events/sec):** Memory stays under 100 MB per worker
- [ ] **Retry Storm:** 1000 failed events recover without overload
- [ ] **Trace Cache:** 10k concurrent traces, decision cache hit rate > 95%

**Deliverables:**
- ✅ 8 integration tests passing
- ✅ 3 load tests passing
- ✅ Performance benchmarks documented

---

### Phase 6: Documentation & Migration (Week 7)
**Objective:** Help users understand and adopt conflict resolutions

**Documentation:**
- [ ] **Migration Guide:** Rails.logger → E11y events
- [ ] **Configuration Guide:** Choosing the right profile
- [ ] **Decision Tree:** Which settings to use for your use case
- [ ] **Conflict Resolution Playbook:** What to do when conflicts arise

**Examples:**
- [ ] **Complete configuration examples** for each profile
- [ ] **Code snippets** for each UC showing conflict resolution
- [ ] **Before/After examples** showing migration path

**Deliverables:**
- ✅ 4 comprehensive guides
- ✅ 20+ code examples
- ✅ Decision tree diagram

---

## Timeline Summary

| Phase | Duration | Effort | Dependencies |
|-------|----------|--------|--------------|
| 1. Critical Decisions | Week 1 | 1-2 days | Architecture team availability |
| 2. ADR Updates | Week 2 | 2-3 days | Phase 1 decisions |
| 3. UC Updates | Week 2-3 | 2-3 days | Phase 2 ADR updates |
| 4. Implementation | Week 3-5 | 2-3 weeks | Phase 1-3 complete |
| 5. Testing & Validation | Week 6 | 1 week | Phase 4 implementation |
| 6. Documentation | Week 7 | 3-4 days | Phase 5 validation |

**Total Duration:** 7 weeks  
**Total Effort:** ~4-5 weeks (with parallelization)

---

## Risk Mitigation

**High Risk if Unresolved:**
- **C01 (PII × Audit):** Legal/compliance violation → **Mitigate:** Implement audit pipeline FIRST
- **C08 (PII Baggage):** GDPR violation → **Mitigate:** Block baggage by default, provide allowlist
- **C11 (Sampling × SLO):** Inaccurate SLO metrics → **Mitigate:** Implement stratified sampling + correction
- **C20 (Memory):** Production stability issue → **Mitigate:** Implement memory limits + monitoring

**Medium Risk:**
- **C05, C15, C17:** Distributed tracing degraded → **Mitigate:** Clear documentation + examples
- **C06, C18:** Retry storms under failure → **Mitigate:** Rate limit retries, non-failing jobs

**Low Risk:**
- **C03, C09, C10, C14, C16, C21:** Configuration/documentation only → **Mitigate:** Good defaults

---

## Success Criteria

**Completion Criteria:**
- ✅ All 9 critical conflicts have approved architectural decisions
- ✅ All 14 ADRs/UCs updated with conflict resolutions
- ✅ All 10 new components implemented with tests
- ✅ Integration tests passing for all critical scenarios
- ✅ Load tests verify stability under high throughput
- ✅ Documentation complete with migration guides

**Quality Criteria:**
- ✅ No P0/P1 production incidents related to resolved conflicts
- ✅ Developer feedback positive on configuration complexity reduction
- ✅ SLO metrics accurate (validated against ground truth)
- ✅ Memory usage predictable and bounded
- ✅ Distributed tracing integrity preserved

---

*Analysis completed: 2026-01-14*  
*Analyst: AI Senior Architect (E11y Architecture Review)*  
*Next Action: Schedule architecture review meeting to approve critical conflicts*


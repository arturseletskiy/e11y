# UC-001: Request-Scoped Debug Buffering - Summary

**Document:** UC-001  
**Created:** 2026-01-15  
**Analyzed by:** Agent  
**Priority:** Critical  
**Domain:** Core

---

## 📋 Quick Reference

| Property | Value |
|----------|-------|
| **Type** | Use Case |
| **Complexity** | Medium |
| **Dependencies** | ADR-001 (Middleware Order), ADR-002 (Self-Monitoring), ADR-015 (Middleware Order), UC-002, UC-010, UC-015 |
| **Contradictions** | 3 identified |

---

## 🎯 Purpose & Problem Statement

**What problem does this solve?**
Eliminates the trade-off between debug visibility and log noise/cost: 99% of requests succeed, making debug logs useless noise, but disabling debug makes production debugging impossible.

**Who is affected?**
DevOps, SRE, Backend Developers

**Expected outcome:**
Debug visibility when needed (on errors), zero noise when not needed (on success). 99% log volume reduction while maintaining full debug context for failures.

---

## 📝 Key Requirements

### Must Have (Critical)
- [x] Dual-buffer architecture: Request-scoped buffer (thread-local) + Main buffer (global SPSC)
- [x] Debug events buffered per-request, discarded on success, flushed on error
- [x] Non-debug events (info/warn/error/success/fatal) go to main buffer with 200ms flush interval
- [x] Thread-local storage for request-scoped buffer isolation
- [x] Middleware order enforcement: PII filtering BEFORE buffer routing
- [x] Buffer limit per request (default: 100 events)
- [x] Multiple flush triggers: error, warn, slow_request, custom conditions
- [x] Buffer overflow strategy (drop_oldest, drop_newest, flush_immediately)

### Should Have (Important)
- [x] Custom flush conditions via flush_if block
- [x] Exclude specific events from buffering (security, audit)
- [x] Slow request detection and flush (configurable threshold)
- [x] Yabeda metrics for buffer monitoring (size, flushes, overflows)

### Could Have (Nice to have)
- [ ] Advanced buffer overflow strategies documentation
- [ ] More granular event pattern exclusion rules

---

## 🔗 Dependencies

### Related Use Cases
- **UC-002: Business Event Tracking** - Defines structured events that UC-001 buffers
- **UC-010: Background Job Tracking** - Buffering in Sidekiq/ActiveJob context
- **UC-015: Local Development** - Testing buffering locally

### Related ADRs
- **ADR-001 Section 4.1:** Middleware Execution Order (CRITICAL) - Defines buffer routing position
- **ADR-001 Section 8.3:** Resource Limits - Buffer capacity and memory limits
- **ADR-002 Section 6:** Self-Monitoring - Yabeda metrics for buffer performance
- **ADR-015:** Middleware Order Reference - Detailed middleware pipeline explanation

### External Dependencies
- Rails/Rack middleware
- Thread.current (Ruby thread-local storage)
- Yabeda (metrics)
- SPSC ring buffer (main buffer)

---

## ⚡ Technical Constraints

### Performance
- **Latency:** <2μs overhead per debug event (buffering only)
- **Non-blocking:** Buffering is synchronous but negligible overhead
- **Flush latency:** 200ms for main buffer, immediate for request buffer on error

### Scalability
- **Memory per request (typical):** ~5KB (10 debug events × 500 bytes)
- **Memory per request (worst case):** ~50KB (100 events buffer limit)
- **Concurrent requests (100):** 500KB typical, 5MB worst case
- **Total memory impact:** <10MB even at high load

### Security
- **CRITICAL:** PII filtering MUST happen BEFORE buffer routing
- **Security events:** MUST NOT be buffered (always sent immediately)
- **Audit events:** MUST NOT be buffered (always sent immediately)

### Compatibility
- Ruby (requires Thread.current)
- Rails/Rack (middleware integration)
- Thread-safe (thread-local storage)

---

## 🎭 User Story

**As a** Backend Developer/SRE  
**I want** debug events buffered per-request and only sent on errors  
**So that** I get full debug context for failures without drowning in logs for 99% successful requests

**Rationale:**
Traditional approaches force a choice: enable debug globally (high cost, noise) or disable debug (blind debugging). Request-scoped buffering eliminates this trade-off by making debug conditional on request outcome.

**Alternatives considered:**
1. **Sampling** - Misses rare errors, doesn't help debug specific failures
2. **Manual toggling** - Requires code deployment, waiting for error reproduction
3. **Always-on debug** - 99% noise, high storage costs ($500/month → $50/month in example)

**Trade-offs:**
- ✅ **Pros:** 99% log reduction, full error context, automatic N+1 detection (slow request flush), zero-cost for successful requests
- ❌ **Cons:** Requires middleware order discipline, thread-local storage overhead (~5KB/request), buffer limit complexity

---

## ⚠️ Potential Contradictions

### Contradiction 1: PII Filtering Order vs. Buffer Routing
**Conflict:** Need to buffer events early (to capture all context) BUT must filter PII before buffering (compliance)
**Impact:** High (GDPR violation risk)
**Related to:** ADR-001 (Middleware Order), ADR-006 (Security & Compliance), UC-007 (PII Filtering)
**Notes:** Document explicitly states "CRITICAL: Middleware Order" warning. PII filtering MUST happen BEFORE buffer routing. If positioned incorrectly, buffered debug events may contain unfiltered PII. However, no automatic enforcement mechanism described - relies on developer discipline.

**Real Evidence:**
```
Lines 216-236: "⚠️ CRITICAL: Middleware Order - Request-scoped buffer middleware MUST be positioned correctly... 
❌ Buffered debug events may contain unfiltered PII → GDPR violation"
```

### Contradiction 2: Security Events Must Not Be Buffered vs. Severity-Based Routing
**Conflict:** Security/audit events must never be buffered (immediate send) BUT default routing is severity-based (:debug → buffer, others → main)
**Impact:** High (security event delay/loss risk)
**Related to:** ADR-006 (Security & Compliance), UC-007 (PII Filtering)
**Notes:** Document shows exclude_from_buffer configuration for event patterns (lines 260-263), but default behavior only checks severity. A security event with severity :debug would be buffered unless explicitly excluded via pattern matching.

**Real Evidence:**
```
Lines 597-607: "❌ BAD: Security events must be sent immediately!
Events::LoginAttempt.track(user_id: user.id, severity: :debug)"

But default routing (lines 322-330) only checks: 
"if event.severity == :debug && E11y.request_scope.active?"
```

### Contradiction 3: Buffer Overflow Strategy Mentioned But Underspecified
**Conflict:** Need buffer overflow protection BUT strategies (drop_oldest, drop_newest, flush_immediately) lack detailed behavior specification
**Impact:** Medium (buffer overflow edge cases)
**Related to:** ADR-001 (Resource Limits)
**Notes:** Line 266 mentions overflow_strategy options but doesn't explain: What happens with drop_oldest during error flush? Does flush_immediately bypass PII filtering? When exactly is overflow detected?

**Real Evidence:**
```
Line 266: "overflow_strategy :drop_oldest  # or :drop_newest, :flush_immediately"
But no further implementation details or edge case handling described.
```

---

## 🔍 Implementation Notes

### Key Components
- **E11y::Middleware::Rack** - Request lifecycle management (lines 337-358)
- **E11y::RequestScope** - Buffer operations (initialize, buffer, flush, discard, cleanup) (lines 361-401)
- **Thread.current[:e11y_buffer]** - Per-request buffer storage
- **E11y::Collector** - Event delivery (receives flushed events)

### Configuration Required
```ruby
E11y.configure do |config|
  # Request-scoped buffer (basic)
  config.request_scope do
    enabled true  # Default: true
    buffer_limit 100  # Max debug events per request
    flush_on :error  # Flush when exception raised
  end
  
  # Advanced (optional)
  config.request_scope do
    flush_on :slow_request, threshold: 500  # ms
    flush_if { |events, request| events.any? { |e| e.name.include?('payment') } }
    exclude_from_buffer do
      severity [:info, :success, :warn, :error, :fatal]  # Only buffer :debug
      event_patterns ['security.*', 'audit.*']  # Never buffer security events
    end
    overflow_strategy :drop_oldest
  end
end
```

### APIs / Interfaces
- `E11y::RequestScope.initialize_buffer!` - Called at request start
- `E11y::RequestScope.buffer_event(event)` - Returns true if buffered, false if sent immediately
- `E11y::RequestScope.flush_buffer!(severity: :error)` - Flush all buffered events with specified severity
- `E11y::RequestScope.discard_buffer!` - Clear buffer without sending (success path)
- `E11y::RequestScope.cleanup!` - Thread-local cleanup

### Data Structures
- **Request Buffer:** Thread-local array (Thread.current[:e11y_buffer])
- **Main Buffer:** Global SPSC ring buffer (capacity: 100,000)
- **Event object:** ~500 bytes each

---

## ❓ Questions & Gaps

### Clarification Needed
1. **Middleware order enforcement:** Is there automatic validation of middleware order, or purely documentation-based?
2. **Buffer overflow timing:** When exactly is overflow_strategy triggered - during event addition or at flush?
3. **Flush_immediately strategy:** Does it bypass the middleware pipeline (PII filtering)?

### Missing Information
1. **Thread pool environments:** How does thread-local storage work with thread pools (Puma workers)? Is cleanup guaranteed?
2. **Buffer limit edge cases:** What happens if buffer reaches limit mid-request and then request fails?
3. **Flush performance:** What's the latency impact of flushing 100 debug events synchronously during error handling?

### Ambiguities
1. **"Security events must not be buffered"** - Is this enforced by default, or requires explicit exclude_from_buffer configuration?
2. **Flush severity override** - Line 385 shows `event.severity = severity if event.severity == :debug` - does this mean all buffered debug events become error severity on flush?

---

## 🧪 Testing Considerations

### Test Scenarios
1. **Happy path:** 100 successful requests with debug events → verify 0 debug events sent, only success events sent
2. **Error path:** 1 failed request with debug events → verify all debug events flushed immediately
3. **Slow request:** Request >500ms → verify debug events flushed
4. **Buffer overflow:** Request with 150 debug events (limit: 100) → verify overflow_strategy behavior
5. **PII in buffer:** Debug event with PII in successful request → verify no PII leaked (discarded)
6. **Security event:** Security event with :debug severity → verify sent immediately, not buffered

### Mocking Needs
- `E11y::Collector.collect` - Spy on event delivery
- `Thread.current` - Verify thread-local isolation
- `SecureRandom.uuid` - Stub request_id generation

---

## 📊 Complexity Assessment

**Overall Complexity:** Medium

**Reasoning:**
- Dual-buffer architecture adds conceptual complexity (2 buffers, different flush logic)
- Thread-local storage requires careful cleanup and thread-safety considerations
- Middleware order discipline is critical but not automatically enforced
- Multiple flush triggers and conditions increase configuration surface
- Performance impact is negligible but memory management requires monitoring

**Estimated Implementation Time:**
- Junior dev: 10-15 days (middleware, thread-local storage, flush logic, testing)
- Senior dev: 6-8 days (familiar with Rack middleware and thread safety)

---

## 📚 References

### Related Documentation
- [UC-002: Business Event Tracking](./UC-002-business-event-tracking.md)
- [UC-010: Background Job Tracking](./UC-010-background-job-tracking.md)
- [UC-015: Local Development](./UC-015-local-development.md)
- [ADR-001 Section 4.1: Middleware Execution Order](../ADR-001-architecture.md#41-middleware-execution-order-critical)
- [ADR-001 Section 8.3: Resource Limits](../ADR-001-architecture.md#83-resource-limits)
- [ADR-002 Section 6: Self-Monitoring](../ADR-002-metrics-yabeda.md#6-self-monitoring)
- [ADR-015: Middleware Order Reference](../ADR-015-middleware-order.md)

### Similar Solutions
- **Sentry Breadcrumbs** - Similar concept but tied to error tracking
- **Lograge** - Log aggregation but no conditional buffering
- **Rails.logger with level toggling** - Requires manual deployment

### Research Notes
- **Quantified benefits (from document):**
  - Log volume reduction: 99% (1M → 10K lines/day)
  - Storage cost savings: 90% ($500 → $50/month)
  - Query performance: 60x speedup (30s → 0.5s)
  - Debugging time saved: 28 minutes per incident (30min → 2min)
- **Production-ready metrics:**
  - Buffer size p99: <20 events (normal), 50-80 (warning), >80 (alert)
  - Flush rate (error): <1% (normal), 1-5% (warning), >5% (alert)
  - Memory impact: <10MB even at high load (100 concurrent requests)

---

## 🏷️ Tags

`#core` `#critical` `#buffering` `#dual-buffer` `#request-scope` `#debug-events` `#middleware` `#performance` `#memory-optimization`

---

**Last Updated:** 2026-01-15  
**Next Review:** Before implementation start (Phase 3 - Consolidated Analysis)

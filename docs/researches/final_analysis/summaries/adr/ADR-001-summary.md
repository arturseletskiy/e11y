# ADR-001: E11y Gem Architecture & Implementation Design - Summary

**Document:** ADR-001  
**Created:** 2026-01-15  
**Analyzed by:** Agent  
**Priority:** Critical  
**Domain:** Core Architecture

---

## 📋 Quick Reference

| Property | Value |
|----------|-------|
| **Type** | Architectural Decision |
| **Complexity** | Complex |
| **Dependencies** | ADR-002, ADR-004, ADR-006, ADR-011, ADR-012, ADR-015 (CRITICAL) |
| **Contradictions** | 4 identified |

---

## 🎯 Decision Statement

**Decision:** E11y uses a **zero-allocation, middleware-based architecture** with dual-buffer system (request-scoped + main ring buffer), adaptive memory management (C20), and strict performance budget (<1ms p99, <100MB memory @ 1000 events/sec).

**Context:**
Modern Rails applications need structured event tracking, debug-on-error capabilities, built-in metrics, multi-adapter routing, GDPR-compliant PII filtering, and high performance (<1ms p99, <100MB memory).

**Consequences:**
- **Positive:** Meets all 22 use cases, <1ms p99 latency target, <100MB memory budget, extensible via middleware, Rails-familiar patterns
- **Negative:** Rails-only (no plain Ruby), no hot config reload, zero-allocation adds code complexity, middleware order discipline required

---

## 📝 Key Architectural Decisions

### Must Have (Critical)
- [x] **Zero-Allocation Pattern:** No instance creation, class methods only (Event.track, no Event.new)
- [x] **Dual-Buffer Architecture:** Request-scoped buffer (thread-local, :debug only) + Main ring buffer (global SPSC, :info+ events)
- [x] **Middleware Chain Pipeline:** Rails-style middleware (composable, extensible, 7 built-in: TraceContext, Validation, PiiFilter, RateLimit, Sampling, Versioning, Routing)
- [x] **Lock-Free SPSC Ring Buffer:** Concurrent::AtomicFixnum for write/read indexes, single producer (app threads), single consumer (flush worker)
- [x] **Adaptive Buffer with Memory Limits (C20):** Track total memory across ALL buffers, enforce global limit (default 100MB), backpressure strategies (:block, :drop, :throttle)
- [x] **Thread-Local Storage:** ActiveSupport::CurrentAttributes for request-scoped buffer, trace context, sampling decision
- [x] **Strict Performance Budget:** <1ms p99 latency @ 1000 events/sec, <100MB memory @ steady state, <5% CPU @ 1000 events/sec
- [x] **Rails 8.0+ Exclusive:** No backwards compatibility with Rails 7.x, uses CurrentAttributes, ActiveSupport::Notifications

### Should Have (Important)
- [x] **Extension Points:** Custom middleware, custom adapters, custom event fields
- [x] **Adapter Contract Tests:** Shared examples for adapter interface validation
- [x] **Configuration Lifecycle:** Freeze config after initialization (thread-safe reads), freeze event registry after boot
- [x] **C4 Diagrams:** System Context, Container, Component, Code levels (4 levels of documentation)
- [x] **Thread Safety Guarantees:** Thread-local (no sync), concurrent (atomic), single-threaded (no contention)

### Could Have (Nice to have)
- [ ] Hot configuration reload (explicitly out of scope)
- [ ] Distributed tracing coordination (only propagation supported)
- [ ] Plain Ruby support (Rails-only decision)

---

## 🔗 Dependencies

### Related ADRs
- **ADR-015: Middleware Order** - CRITICAL reference for pipeline execution order
- **ADR-012: Event Evolution** - Versioning design (why VersioningMiddleware is LAST)
- **ADR-002: Metrics & Yabeda** - Metrics integration, self-monitoring
- **ADR-004: Adapter Architecture** - Adapter design, circuit breakers, retry policy, DLQ
- **ADR-006: Security & Compliance** - PII filtering, GDPR requirements
- **ADR-011: Testing Strategy** - Test pyramid, coverage requirements (>90%)

### External Dependencies (Required)
- Rails >= 8.0.0
- dry-schema ~> 1.13 (schema validation)
- dry-configurable ~> 1.1 (configuration)
- concurrent-ruby ~> 1.2 (AtomicFixnum, TimerTask)

### External Dependencies (Optional)
- yabeda ~> 0.12 (metrics - UC-003)
- sentry-ruby ~> 5.0 (Sentry adapter - UC-005)
- faraday ~> 2.0 (HTTP adapters)
- redis ~> 5.0 (rate limiting - UC-011)

---

## ⚡ Technical Constraints

### Performance Targets (CRITICAL)
| Operation | p50 | p95 | p99 | Max |
|-----------|-----|-----|-----|-----|
| **Event.track()** | <0.1ms | <0.5ms | <1ms | <5ms |
| **Pipeline processing** | <0.05ms | <0.2ms | <0.5ms | <2ms |
| **Buffer write** | <0.01ms | <0.05ms | <0.1ms | <1ms |
| **Adapter write (batch)** | <10ms | <50ms | <100ms | <500ms |

### Throughput Targets
- **Sustained:** 1000 events/sec
- **Burst:** 5000 events/sec (5 seconds)
- **Peak:** 10000 events/sec (1 second)

### Resource Limits
- **Memory:** <100MB @ steady state (adaptive buffer enforces hard limit)
- **CPU:** <5% @ 1000 events/sec
- **GC time:** <10ms per minor GC
- **Threads:** <5 (1 main + 4 workers)

### Memory Budget Breakdown (lines 1666-1716)
1. Ring Buffer (main): ≤50MB (adaptive, memory-limited)
2. Request Buffers (threads): 500KB (10 threads × 100 events × 500 bytes)
3. Event Classes (registry): 1MB (100 classes × 10KB each)
4. Adapters (connections): 10MB (5 adapters × 2MB each)
5. Ruby VM overhead: 35MB (Rails + E11y gem code)

**Total: 96.5MB** ✅ Within <100MB budget

### Scalability
- Lock-free SPSC ring buffer: supports 10K+ events/sec
- Adaptive buffer: prevents memory exhaustion at high throughput (C20)
- Thread-local request buffers: isolated per-thread (no contention)

### Security
- Configuration frozen after initialization (immutable, thread-safe)
- Event registry frozen after boot (no runtime registration)
- PII filtering happens in middleware (before buffering)

### Compatibility
- Ruby >= 3.3.0
- Rails >= 8.0.0 (exclusive, no Rails 7.x support)
- ActiveSupport::CurrentAttributes (Rails 8.0+ feature)

---

## 🎭 Rationale & Alternatives

**As an** E11y Gem Architect  
**We decided** to use zero-allocation + middleware pipeline + dual-buffer architecture  
**So that** we meet strict performance targets (<1ms p99, <100MB memory) while supporting all 22 use cases

**Rationale:**
Performance requirements are non-negotiable: <1ms p99 latency @ 1000 events/sec. Traditional approaches (instance creation, single buffer, synchronous I/O) cannot meet these targets. Zero-allocation + lock-free buffers + middleware chain provide:
- **Zero-allocation:** No instance creation → low memory, fast GC
- **Dual-buffer:** Request-scoped (thread-local) + main ring buffer (SPSC) → no lock contention
- **Middleware chain:** Extensible, familiar to Rails devs, composable
- **Adaptive memory (C20):** Prevents memory exhaustion at high throughput (10K+ events/sec)

**Alternatives considered:**
1. **Actor Model (Concurrent::Actor)** - Rejected: Too complex for Ruby devs, unfamiliar patterns
2. **Evented I/O (EventMachine)** - Rejected: EventMachine unmaintained, blocking calls problematic
3. **Simple Queue (Array + Mutex)** - Rejected: Lock contention @ high load, performance target not met
4. **Sidekiq Jobs** - Rejected: Redis dependency, latency, <1ms p99 impossible with job queuing

**Trade-offs:**
- ✅ **Pros:** Meets all performance targets, extensible, Rails-familiar, supports 22 use cases, memory-safe (C20)
- ❌ **Cons:** Rails-only (smaller audience), zero-allocation adds code complexity, middleware order discipline required, no hot config reload (requires restart), adaptive buffer may drop events under extreme load

---

## ⚠️ Potential Contradictions

### Contradiction 1: Middleware Order MUST Be Correct (Versioning LAST) BUT No Automatic Enforcement
**Conflict:** VersioningMiddleware MUST be last middleware (after validation, PII filtering, rate limiting, sampling) BUT no compile-time or runtime validation
**Impact:** High (incorrect behavior if order wrong)
**Related to:** ADR-015 (Middleware Order - CRITICAL), ADR-012 (Event Evolution), UC-001 (Request-Scoped Buffering), UC-007 (PII Filtering)
**Notes:** Lines 1552-1635 explain why order matters:
- Validation, PII filtering, rate limiting, sampling MUST use ORIGINAL class name (Events::OrderPaidV2)
- Versioning normalizes event_name (Events::OrderPaidV2 → Events::OrderPaid) for adapters
- If versioning happens too early, business logic would use normalized name (wrong schema, wrong PII rules, wrong rate limits)

**Real Evidence:**
```
Lines 1552-1554: "⚠️ CRITICAL: Middleware execution order is critical for correct operation!
See: ADR-015: Middleware Order for detailed reference guide"

Lines 1621-1629: "Key Rule: All business logic (validation, PII filtering, rate limiting, sampling) MUST use the ORIGINAL class name (e.g., Events::OrderPaidV2), not the normalized one.
Why?
- V2 may have different schema than V1
- V2 may have different PII rules than V1
- V2 may have different rate limits than V1
- V2 may have different sample rates than V1

Versioning Middleware is purely cosmetic normalization for external systems (adapters, Loki, Grafana). It MUST be the last middleware before routing."
```

**Problem:** No automatic validation that middleware order is correct. Relies on developer discipline. If developer adds custom middleware in wrong position, system fails silently (wrong PII filtering, wrong validation schema).

**Mitigation:** ADR-015 provides detailed reference guide, but this is documentation-based, not code-enforced.

### Contradiction 2: Zero-Allocation (No Instances) Improves Performance BUT Adds Code Complexity
**Conflict:** Need zero-allocation for <1ms p99 latency target BUT makes code harder to read/maintain (no OOP, only hashes and class methods)
**Impact:** Medium (performance vs. code maintainability)
**Related to:** All implementation
**Notes:** Lines 544-623 show zero-allocation pattern. All data passed as Hash (not object). Benefits: low memory, fast GC. Drawback: less intuitive code, harder to debug (no instance methods, no object identity).

**Real Evidence:**
```
Lines 544-623: Event::Base implementation showing:
- No initialize method
- All methods are class methods (self.track, self.event_name)
- Event data is Hash (lines 590-597), not object instance
- Comment: "Main tracking method (NO INSTANCE CREATED!)"

Lines 625-630: "Key Points:
- ✅ No new calls → zero allocation
- ✅ All data in Hash (not object)
- ✅ Class methods only
- ✅ Thread-safe (@_config frozen after definition)"
```

**Trade-off:** Zero-allocation is necessary for <1ms p99 target (lines 1889-1912). Creating 1000 instances/sec would add GC pressure (minor GC every 100ms instead of every 1000ms).

**Alternative:** Traditional OOP (create Event instances) would fail p99 latency target. Benchmarks would show >2ms p99 due to GC pressure.

### Contradiction 3: Adaptive Buffer (C20) Prevents Memory Exhaustion BUT May Drop Events Under Extreme Load
**Conflict:** Need bounded memory (adaptive buffer with 100MB limit) BUT backpressure may drop events when memory full
**Impact:** High (data loss risk vs. memory safety)
**Related to:** C20 (Memory Pressure), UC-001 (Request-Scoped Buffering)
**Notes:** Lines 819-1237 describe C20 resolution. Adaptive buffer tracks total memory across all buffers, enforces global limit (100MB default). Three backpressure strategies:
- `:block` - Block event ingestion until space available (max 1s wait, then drop)
- `:drop` - Drop new event immediately
- `:throttle` - Trigger immediate flush, then drop if still full

**Real Evidence:**
```
Lines 821-824: "⚠️ CRITICAL: C20 Resolution - Memory Exhaustion Prevention
Problem: At high throughput (10K+ events/sec), fixed-size buffers can exhaust memory (up to 1GB+ per worker)
Solution: Adaptive buffering with memory limits + backpressure mechanism"

Lines 1199-1207: Trade-offs table:
| Aspect | Pro | Con | Mitigation |
| Memory Safety | ✅ Bounded memory usage | ⚠️ May drop events under extreme load | Monitor drop rate, alert if > 1% |
| Backpressure | ✅ Prevents overload | ⚠️ Can slow request processing | Set max_block_time = 1s, then drop |
```

**Trade-off:** Lines 2213 show decision: "Adaptive buffer (C20): Memory safety, prevents exhaustion | May drop events under extreme load | Safety > throughput."

**Monitoring Required:** Lines 1208-1232 show critical metrics:
- `e11y_buffer_memory_bytes` (current usage)
- `e11y_buffer_memory_exhaustion_dropped` (drop counter)
- Alert: Drop rate > 1% of ingestion rate
- Alert: Emergency flushes > 10/min

**Justification:** Memory exhaustion is worse than dropping events. Exhaustion causes:
- OOM crashes (entire worker dies)
- All events lost (not just some)
- Service downtime

Adaptive buffer with backpressure is safer: drops SOME events under extreme load, but keeps service alive.

### Contradiction 4: Middleware Chain Extensibility vs. Performance Overhead
**Conflict:** Middleware chain pattern provides extensibility (custom middleware) BUT adds latency overhead (7 middleware calls per event) compared to direct routing
**Impact:** Low (acceptable overhead for extensibility)
**Related to:** ADR-015 (Middleware Order)
**Notes:** Lines 633-815 describe middleware chain implementation. Each event passes through 7 middlewares sequentially:
1. TraceContextMiddleware (~0.01ms - add trace_id, timestamp)
2. ValidationMiddleware (~0.05ms - schema validation)
3. PiiFilterMiddleware (~0.05-0.2ms - Tier 2/3 filtering)
4. RateLimitMiddleware (~0.02ms - Redis check)
5. SamplingMiddleware (~0.01ms - adaptive sampling decision)
6. VersioningMiddleware (~0.01ms - normalize event_name)
7. RoutingMiddleware (~0.01ms - buffer routing)

**Total overhead:** ~0.15-0.3ms per event (middleware chain overhead)

**Real Evidence:**
```
Lines 1893-1899: Performance targets table shows:
| Operation | p50 | p95 | p99 | Max |
| Event.track() | <0.1ms | <0.5ms | <1ms | <5ms |
| Pipeline processing | <0.05ms | <0.2ms | <0.5ms | <2ms |

Pipeline processing target: p99 <0.5ms
Implies middleware chain overhead must stay under 0.5ms total.
```

**Trade-off:** Lines 2215 show decision: "Middleware chain: Extensible, familiar | Slower than direct | Extensibility > speed."

**Alternative Rejected:** Direct routing (no middleware chain) would be ~0.05ms faster, but loses extensibility (custom middleware, PII filtering, rate limiting would require monolithic changes).

**Justification:** 0.15-0.3ms overhead is acceptable for extensibility. Total Event.track() p99 still <1ms (target met).

---

## 🔍 Implementation Notes

### Key Components
- **E11y::Event::Base** - Zero-allocation event base class (class methods only, no instances)
- **E11y::Pipeline** - Middleware chain builder (Rails-style, Builder pattern)
- **E11y::RingBuffer** - Lock-free SPSC ring buffer (Concurrent::AtomicFixnum, capacity 100k)
- **E11y::AdaptiveBuffer** - C20 resolution: memory-limited buffer (tracks total_memory_bytes, enforces limit)
- **E11y::Current** - Thread-local storage (ActiveSupport::CurrentAttributes: trace_id, user_id, request_buffer, sampled)
- **E11y::Adapters::Base** - Abstract adapter base class (write_batch interface, contract validation)
- **E11y::MainBuffer** - Singleton main buffer (uses AdaptiveBuffer if adaptive.enabled, else RingBuffer)
- **E11y::RequestBuffer** - Request-scoped buffer manager (flush on error, discard on success)

### Configuration Required

**Basic:**
```ruby
E11y.configure do |config|
  # Pipeline order (CRITICAL!)
  config.pipeline.use TraceContextMiddleware    # 1. Enrich first
  config.pipeline.use ValidationMiddleware      # 2. Fail fast
  config.pipeline.use PiiFilterMiddleware       # 3. Security (BEFORE buffer)
  config.pipeline.use RateLimitMiddleware       # 4. Protection
  config.pipeline.use SamplingMiddleware        # 5. Cost optimization
  config.pipeline.use VersioningMiddleware      # 6. Normalize (LAST!)
  config.pipeline.use RoutingMiddleware         # 7. Buffer routing (final)
end
```

**Advanced (C20 Adaptive Buffer):**
```ruby
E11y.configure do |config|
  config.buffering do
    adaptive do
      enabled true
      memory_limit_mb 100  # Hard limit per worker
      
      # Backpressure strategy
      backpressure do
        enabled true
        strategy :block  # Block ingestion when full
        max_block_time 1.second  # Max wait before dropping
      end
    end
    
    # Standard flush triggers
    flush_interval 200.milliseconds
    max_buffer_size 1000
  end
end
```

### APIs / Interfaces
- `E11y.configure(&block)` - Global configuration (frozen after init)
- `E11y::Event::Base.track(**payload)` - Zero-allocation event tracking
- `E11y::Pipeline.use(middleware_class, *args)` - Add middleware to pipeline
- `E11y::Pipeline.process(event_data)` - Execute middleware chain
- `E11y::RingBuffer#push(item)` - Lock-free write (SPSC)
- `E11y::RingBuffer#pop(batch_size)` - Lock-free read (SPSC)
- `E11y::AdaptiveBuffer#add_event(event_data)` - Memory-tracked add (C20)
- `E11y::AdaptiveBuffer#flush` - Flush all buffers, update memory tracking
- `E11y::Current.request_buffer` - Thread-local debug events buffer
- `E11y::Adapters::Base#write_batch(events)` - Adapter interface (abstract method)

### Data Structures
- **event_data (Hash):** `{ event_class: Class, event_name: String, event_version: Integer, payload: Hash, timestamp: Time, context: Hash }`
- **Ring Buffer:** Array (capacity 100k) + AtomicFixnum (write_index, read_index, size)
- **Request Buffer:** Thread-local Array (per-request, max 100 events)
- **AdaptiveBuffer:** Hash of per-adapter buffers + AtomicFixnum (total_memory_bytes) + Mutex (flush_mutex)

---

## ❓ Questions & Gaps

### Clarification Needed
1. **Middleware order validation:** Is there a boot-time check that verifies VersioningMiddleware is LAST? Or purely documentation-based?
2. **Adaptive buffer backpressure:** Does `:block` strategy block the entire request thread (blocking HTTP response)? Or only block event tracking (request continues)?
3. **Memory estimation accuracy:** `estimate_size` uses `payload.to_json.bytesize` (line 969) - what's the accuracy? Does it account for Ruby object overhead correctly?

### Missing Information
1. **SPSC ring buffer correctness:** How is SPSC (Single Producer Single Consumer) guaranteed? What prevents multiple producer threads from concurrent push?
2. **Event registry freezing:** Lines 1801-1811 show registry freeze after boot. What happens if a new event class is loaded dynamically (e.g., via autoloading)?
3. **GC optimization impact:** Lines 1718-1746 show StringPool and object reuse. Are there benchmarks showing actual GC reduction?

### Ambiguities
1. **"Lock-free SPSC"** (line 826) - Is this truly lock-free, or does Concurrent::AtomicFixnum use CAS (Compare-And-Swap) which can spin under contention?
2. **"Configuration frozen after initialization"** (line 1779) - Can configuration be unfrozen/reconfigured, or is it permanently frozen for application lifetime?

---

## 🧪 Testing Considerations

### Test Scenarios
1. **Zero-allocation:** Track 10,000 events, verify no Event instances created (ObjectSpace.each_object)
2. **Middleware order:** Add VersioningMiddleware before PiiFilterMiddleware, verify validation error (wrong schema used)
3. **Ring buffer SPSC:** Multiple producer threads write concurrently, verify SPSC assumption holds (no data corruption)
4. **Adaptive buffer (C20):** Generate 10K events/sec for 60s (memory limit 100MB), verify memory stays under limit
5. **Backpressure (:block):** Fill buffer to 100MB, track new event, verify blocks for max 1s then drops
6. **Request buffer flush:** HTTP request with error, verify debug events flushed to main buffer
7. **Performance benchmarks:** Run spec/performance/event_tracking_spec.rb, verify p99 <1ms

### Mocking Needs
- `Concurrent::AtomicFixnum` - Spy on increment/decrement calls (verify lock-free)
- `Time.now.utc` - Stub for testing timestamp consistency
- `GC.stat` - Mock for testing memory benchmarks
- `Faraday` - Mock HTTP calls for adapter testing

---

## 📊 Complexity Assessment

**Overall Complexity:** Complex

**Reasoning:**
- Zero-allocation pattern is non-intuitive (no OOP, only hashes and class methods)
- Dual-buffer architecture adds conceptual complexity (request-scoped vs. main buffer, different flush logic)
- Middleware chain requires understanding of order discipline (Versioning LAST, PiiFilter BEFORE buffer)
- Lock-free SPSC ring buffer requires understanding of atomic operations, memory barriers
- Adaptive buffer (C20) adds memory tracking, backpressure strategies, early flush logic
- Thread safety requires understanding of thread-local, concurrent, and single-threaded components
- Performance requirements are strict (<1ms p99, <100MB memory) - no room for errors
- Testing requires performance benchmarks, concurrency testing, memory profiling

**Estimated Implementation Time:**
- Junior dev: 40-50 days (zero-allocation, middleware chain, ring buffer, adaptive buffer, thread safety, testing)
- Senior dev: 25-30 days (familiar with concurrency, lock-free algorithms, performance optimization)

---

## 📚 References

### Related Documentation
- [ADR-015: Middleware Order](../ADR-015-middleware-order.md) - **CRITICAL** - Complete reference for pipeline execution order
- [ADR-012: Event Evolution](../ADR-012-event-evolution.md) - Versioning design (why VersioningMiddleware is LAST)
- [ADR-002: Metrics & Yabeda](../ADR-002-metrics-yabeda.md) - Metrics integration, self-monitoring
- [ADR-004: Adapter Architecture](../ADR-004-adapter-architecture.md) - Adapter design, circuit breakers, DLQ
- [ADR-006: Security & Compliance](../ADR-006-security-compliance.md) - PII filtering, GDPR
- [ADR-011: Testing Strategy](../ADR-011-testing-strategy.md) - Test pyramid, >90% coverage requirement
- [COMPREHENSIVE-CONFIGURATION.md](../COMPREHENSIVE-CONFIGURATION.md) - Complete configuration examples
- [CONFLICT-ANALYSIS.md](../researches/CONFLICT-ANALYSIS.md) - C20 memory pressure conflict

### Similar Solutions
- **Semantic Logger** - Structured logging, but no zero-allocation, no dual-buffer
- **Yabeda** - Metrics only, no event tracking
- **OpenTelemetry Ruby** - Tracing/metrics, but higher overhead (not <1ms p99)

### Research Notes
- **Performance targets (lines 1889-1912):**
  - Event.track() p99: <1ms (CRITICAL)
  - Throughput: 1000 events/sec sustained, 10K peak
  - Memory: <100MB @ steady state (C20 enforced)
  - CPU: <5% @ 1000 events/sec
- **Memory budget breakdown (lines 1666-1716):**
  - Ring buffer: ≤50MB (adaptive)
  - Request buffers: 500KB
  - Event registry: 1MB
  - Adapters: 10MB
  - Ruby VM: 35MB
  - Total: 96.5MB (within <100MB budget)
- **C20 resolution (lines 819-1237):**
  - Problem: Fixed-size buffers can exhaust memory (1GB+ at 10K events/sec)
  - Solution: Adaptive buffer with hard memory limit (100MB default)
  - Backpressure: block → wait → drop (safety > throughput)

---

## 🏷️ Tags

`#critical` `#core-architecture` `#zero-allocation` `#dual-buffer` `#middleware-pipeline` `#lock-free-spsc` `#adaptive-buffer-c20` `#performance-budget` `#rails-8-exclusive` `#thread-safety`

---

**Last Updated:** 2026-01-15  
**Next Review:** Before implementation start (Phase 3 - Consolidated Analysis)

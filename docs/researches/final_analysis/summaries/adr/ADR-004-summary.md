# ADR-004: Adapter Architecture - Summary

**Document:** ADR-004  
**Created:** 2026-01-15  
**Analyzed by:** Agent  
**Priority:** Critical  
**Domain:** Core Architecture

---

## 📋 Quick Reference

| Property | Value |
|----------|-------|
| **Type** | Architectural Decision |
| **Complexity** | Medium |
| **Dependencies** | ADR-001 (Core Architecture), ADR-002 (Metrics) |
| **Contradictions** | 5 identified |

---

## 🎯 Decision Statement

**Decision:** E11y uses a **unified adapter interface** with global adapter registry, abstract base class (write/write_batch contract), built-in error handling (retry policy + circuit breaker), connection pooling, and adaptive batching.

**Context:**
Applications need to send events to multiple destinations (Loki, Sentry, Elasticsearch, File) without tight coupling, configuration duplication, or inconsistent error handling.

**Consequences:**
- **Positive:** Configure once (DRY), unified interface (contract-based), built-in resilience (retry + circuit breaker), resource efficiency (connection pooling), easy testing (in-memory adapter)
- **Negative:** Less flexibility (global registry vs. per-event config), batching adds latency (~200ms), connection pooling adds memory overhead, circuit breaker adds complexity

---

## 📝 Key Architectural Decisions

### Must Have (Critical)
- [x] **Unified Adapter Interface:** Abstract base class `E11y::Adapters::Base` with contract:
  - `write(event_data)` - Single event (synchronous)
  - `write_batch(events)` - Batch write (preferred for performance)
  - `healthy?` - Health check
  - `close` - Cleanup connections/buffers
  - `capabilities` - Feature flags (batching, compression, async, streaming)
- [x] **Global Adapter Registry:** Configure once at boot, reference by name (`:loki`, `:sentry`, `:file`), validate adapter interface, cleanup on exit
- [x] **Built-in Adapters (5):**
  - Stdout: Console output (colorized, pretty-print, development/debugging)
  - File: Local files with rotation (daily/hourly/size-based, gzip compression on rotate)
  - Loki: Grafana Loki (HTTP POST /loki/api/v1/push, gzip compression, batching)
  - Sentry: Error tracking (Sentry SDK, breadcrumbs, severity threshold)
  - Elasticsearch: Search & analytics (bulk API /_bulk, index rotation daily/monthly/yearly)
- [x] **Error Handling & Retry:** RetryHandler with exponential backoff (max 3 retries, base delay 1s, max delay 30s), retriable errors (Timeout, ECONNREFUSED, HTTP 429/503), non-retriable errors (HTTP 400) → DLQ
- [x] **Circuit Breaker:** 3 states (closed, open, half-open), failure threshold (5 failures → open), timeout (60s before half-open), success threshold (2 successes → closed)
- [x] **Connection Pooling:** Pool size (default 5), acquire/release pattern, auto-create if pool exhausted, cleanup on close
- [x] **Adaptive Batching:** Min size (10 events), max size (1000 events), timeout (5s), flush timer (background thread)

### Should Have (Important)
- [x] **Per-Event Adapter Overrides:** Event classes can specify custom adapter list (override global)
- [x] **In-Memory Test Adapter:** For unit testing (stores events in array, supports pattern search, event count)
- [x] **Contract Validation:** Registry validates adapter implements required interface (write, write_batch)
- [x] **Cleanup Hooks:** `at_exit` hook to close adapters gracefully

### Could Have (Nice to have)
- [ ] Async adapters (background thread writes) - not implemented (all adapters are sync)
- [ ] Real-time guarantees (at-least-once delivery) - explicitly out of scope (line 76)
- [ ] Distributed tracing coordination - out of scope (only propagation)

---

## 🔗 Dependencies

### Related ADRs
- **ADR-001:** Core Architecture (pipeline, buffers, middleware chain)
- **ADR-002:** Metrics & Yabeda (self-monitoring for adapter performance)

### Related Use Cases
- **UC-005:** Sentry Integration (Sentry adapter implementation)
- All adapters mentioned: Loki, File, Stdout, Elasticsearch

### External Dependencies (Required)
- None (base adapter has no external dependencies)

### External Dependencies (Optional, per adapter)
- `sentry-ruby ~> 5.0` (Sentry adapter)
- `elasticsearch ~> 8.0` (Elasticsearch adapter)
- `faraday ~> 2.0` (Loki adapter HTTP client alternative to Net::HTTP)

---

## ⚡ Technical Constraints

### Performance Targets
| Metric | Target | Critical? |
|--------|--------|-----------|
| **Adapter overhead** | <0.5ms per event | ✅ Yes |
| **Connection reuse** | 100% | ✅ Yes |
| **Retry success rate** | >95% | ✅ Yes |
| **Test coverage** | 100% for base | ✅ Yes |

### Batching Performance
- **Min batch size:** 10 events (avoid too-small batches)
- **Max batch size:** 1000 events (avoid too-large payloads)
- **Batch timeout:** 5 seconds (avoid infinite wait)
- **Flush timer:** Background thread checks every 5s

### Connection Pooling
- **Pool size:** 5 connections per adapter (default)
- **Memory overhead:** ~2MB per adapter × 5 = 10MB per adapter (e.g., Loki, Sentry, ES)

### Retry Policy
- **Max retries:** 3 attempts
- **Base delay:** 1.0 second
- **Max delay:** 30.0 seconds
- **Backoff:** Exponential (1s → 2s → 4s → 8s, capped at 30s)
- **Jitter:** Random 10% (prevent thundering herd)

### Circuit Breaker
- **Failure threshold:** 5 failures → open
- **Timeout:** 60 seconds (open → half-open)
- **Success threshold:** 2 successes → closed (from half-open)

### Scalability
- Connection pooling: supports concurrent requests (acquire/release pattern)
- Batching: reduces HTTP requests (100 events → 1 HTTP POST)
- Circuit breaker: prevents cascade failures to backends

### Security
- HTTPS support (Loki, Elasticsearch via Net::HTTP use_ssl)
- Tenant isolation (Loki X-Scope-OrgID header)
- PII filtering happens in pipeline (before adapters - see ADR-001, UC-007)

### Compatibility
- Ruby >= 3.3.0
- Rails >= 8.0.0 (for ActiveSupport)
- Net::HTTP (built-in Ruby, no extra dependencies for Loki/ES)
- Sentry SDK (sentry-ruby gem required for Sentry adapter)

---

## 🎭 Rationale & Alternatives

**As an** E11y Gem Architect  
**We decided** to use unified adapter interface + global registry + retry/circuit breaker  
**So that** developers configure once (DRY), get consistent error handling across all adapters, and built-in resilience (retry, circuit breaker)

**Rationale:**
Without adapter abstraction:
- ❌ Every event hardcodes destinations (tight coupling)
- ❌ Inconsistent retry logic across adapters
- ❌ Configuration duplication (same adapter configured multiple times)
- ❌ Testing complexity (can't mock adapters easily)

Unified adapter architecture solves this:
- ✅ Global registry: configure once, reference by name (`:loki`, `:sentry`)
- ✅ Contract-based: all adapters implement same interface (write, write_batch)
- ✅ Built-in resilience: retry (exponential backoff) + circuit breaker (prevent cascade failures)
- ✅ Easy testing: in-memory adapter for unit tests (no external services)

**Alternatives considered:**
1. **No adapter abstraction** - Rejected: Every event hardcodes destinations, tight coupling
2. **Adapter instances in events** - Rejected: Duplication, no connection reuse (100% reuse target)
3. **Async by default** - Rejected: Complexity, hard to test, buffering already provides async behavior

**Trade-offs:**
- ✅ **Pros:** DRY (configure once), consistent error handling, built-in resilience (>95% retry success), easy testing (in-memory adapter)
- ❌ **Cons:** Less flexibility (global registry), batching adds latency (~200ms), connection pooling adds memory (10MB per adapter), circuit breaker adds complexity (state machine)

---

## ⚠️ Potential Contradictions

### Contradiction 1: Global Registry (DRY) vs. Per-Event Adapter Flexibility
**Conflict:** Global adapter registry encourages "configure once" (DRY) BUT reduces flexibility for per-event adapter customization (different configs for different events)
**Impact:** Medium (DRY vs. flexibility)
**Related to:** ADR-001 (Core Architecture)
**Notes:** Lines 1054-1171 show adapter registry implementation. Adapters registered globally at boot (lines 1092-1098). Events can override adapter list (lines 1149-1169) but NOT adapter configuration.

**Real Evidence:**
```
Lines 383-389: "E11y.configure do |config|
  config.adapters do
    register :stdout, E11y::Adapters::Stdout.new(
      colorize: true,
      pretty_print: true
    )
  end
end"

Lines 1149-1169: "class OrderPaid < E11y::Event::Base
  # Override global adapters
  adapters [:loki, :file, :sentry]
end"
```

**Problem:** If Event A needs Loki with `batch_size: 100` and Event B needs Loki with `batch_size: 10`, they must use the SAME Loki instance (same config). No per-event adapter config.

**Workaround:** Register multiple Loki instances with different names (`:loki_fast`, `:loki_slow`), but this defeats DRY principle.

**Trade-off (line 1694):** "Global registry: Configure once, reuse | Less flexibility | DRY principle" - Decision favors DRY over flexibility (90% use cases don't need per-event config).

### Contradiction 2: Batching Improves Performance BUT Adds Latency (~200ms)
**Conflict:** Batching reduces HTTP requests (100 events → 1 POST) and improves throughput BUT adds latency (events wait in buffer up to 5s timeout)
**Impact:** Low (acceptable latency for most use cases)
**Related to:** ADR-001 (Performance Requirements)
**Notes:** Lines 1424-1494 describe adaptive batching. Events buffered until:
- Max size reached (1000 events) → flush immediately
- Min size + timeout (10 events + 5s) → flush
- Timer expires (background thread, 5s interval) → flush

**Real Evidence:**
```
Lines 1430-1434: "def initialize(adapter, min_size: 10, max_size: 1000, timeout: 5.seconds)
  @adapter = adapter
  @min_size = min_size
  @max_size = max_size
  @timeout = timeout"

Lines 1472-1478: "def should_flush?
  @buffer.size >= @max_size ||
    (@buffer.size >= @min_size && timeout_expired?)
end

def timeout_expired?
  (Time.now - @last_flush) >= @timeout
end"
```

**Trade-off (line 1695):** "Batching by default: Better performance | Slight latency | 99% use cases benefit"

**Implication:** Events may wait up to 5 seconds in buffer before flush. For real-time use cases (e.g., security alerts), this is unacceptable.

**Mitigation:** Not described in ADR-004. UC-007 (PII Filtering) mentions "security events MUST be sent immediately", but ADR-004 doesn't describe how to bypass batching for critical events.

### Contradiction 3: Connection Pooling is Resource Efficient BUT Adds Memory Overhead
**Conflict:** Connection pooling (pool size 5) enables connection reuse (100% target) BUT adds memory overhead (10MB per adapter × 5 adapters = 50MB)
**Impact:** Medium (resource efficiency vs. memory budget)
**Related to:** ADR-001 (Memory Budget <100MB)
**Notes:** Lines 1176-1243 describe connection pooling. Pool size: 5 connections per adapter. Each connection consumes ~2MB (HTTP connections, buffers, state).

**Real Evidence:**
```
Lines 1182-1189: "def initialize(adapter_class, config, pool_size: 5)
  @adapter_class = adapter_class
  @config = config
  @pool_size = pool_size
  @pool = []
  @mutex = Mutex.new
  
  initialize_pool!
end"

ADR-001 lines 1694-1698 (from previous read): "Adapters (connections):
- Adapters: 5 (Loki, File, Sentry, etc.)
- Connection overhead: ~2MB each
- Total: 5 × 2MB = 10MB"
```

**Trade-off (line 1696):** "Connection pooling: Resource efficient | Memory overhead | Critical for scale"

**Memory Impact:** 5 adapters × 5 connections × 2MB = 50MB (out of 100MB total budget). This is 50% of memory budget for connection pooling alone.

**Clarification Needed:** Is pool size configurable per adapter? If so, not documented in ADR-004.

### Contradiction 4: Circuit Breaker Prevents Cascade Failures BUT Adds State Machine Complexity
**Conflict:** Circuit breaker prevents cascade failures (adapter down → don't keep trying) BUT adds state machine complexity (closed, open, half-open states, timeouts, thresholds)
**Impact:** Medium (reliability vs. complexity)
**Related to:** ADR-001 (Adapter Layer)
**Notes:** Lines 1311-1417 describe circuit breaker implementation. Three states:
- Closed: Normal operation (allow all requests)
- Open: Adapter failed (reject all requests for 60s)
- Half-open: Testing recovery (allow 2 success → closed, any failure → open)

**Real Evidence:**
```
Lines 1321-1330: "def initialize(failure_threshold: 5, timeout: 60, success_threshold: 2)
  @failure_threshold = failure_threshold
  @timeout = timeout
  @success_threshold = success_threshold
  
  @state = CLOSED
  @failure_count = 0
  @success_count = 0
  @last_failure_time = nil
  @mutex = Mutex.new
end"

Lines 1398-1412: "def transition_to_open
  @state = OPEN
  warn '[E11y] Circuit breaker opened (#{@failure_count} failures)'
end

def transition_to_half_open
  @state = HALF_OPEN
  @success_count = 0
  warn '[E11y] Circuit breaker half-open (testing)'
end"
```

**Trade-off (line 1697):** "Circuit breaker: Prevents cascades | Complexity | Reliability critical"

**Implication:** Every adapter write goes through circuit breaker state check. Adds overhead (~0.01ms per event for state check, mutex synchronization).

**Justification:** Complexity is acceptable for reliability. Without circuit breaker, one adapter failure (Loki down) could cascade to entire system (retry storms, timeouts, buffer exhaustion).

### Contradiction 5: Synchronous Interface is Simple BUT Blocks Thread (Mitigated by Buffering)
**Conflict:** Adapter interface is synchronous (`write`, `write_batch`) which is simple to reason about BUT blocks calling thread (HTTP I/O can take 10-100ms)
**Impact:** Low (mitigated by buffering)
**Related to:** ADR-001 (Buffering & Batching)
**Notes:** Lines 219-232 show synchronous write interface. All adapters (Loki, File, Sentry, ES) are synchronous (blocking I/O).

**Real Evidence:**
```
Lines 219-232: "# Write a single event (synchronous)
def write(event_data)
  raise NotImplementedError, 'Adapters must implement #write'
end

# Write a batch of events (preferred for performance)
def write_batch(events)
  # Default: call write for each event
  events.all? { |event| write(event) }
end"

Lines 1698: "Sync interface: Simple to reason | Blocks thread | Buffering mitigates"
```

**Mitigation:** ADR-001 describes flush worker (Concurrent::TimerTask) that calls adapters in background thread (every 200ms). Application threads don't block on adapter I/O - they only write to buffer (non-blocking).

**Trade-off:** Synchronous interface is simpler (no callback hell, no async complexity) at the cost of blocking flush worker thread. Since flush worker is single-threaded (not application threads), this is acceptable.

**Clarification Needed:** If flush worker is blocked on slow adapter (e.g., Loki takes 1 second to respond), does it delay flush for other adapters? Or are adapters flushed in parallel?

---

## 🔍 Implementation Notes

### Key Components
- **E11y::Adapters::Base** - Abstract adapter base class (write, write_batch, healthy?, close, capabilities)
- **E11y::Adapters::Registry** - Global adapter registry (register, resolve, validate)
- **E11y::Adapters::Stdout** - Console output (colorized, pretty-print)
- **E11y::Adapters::File** - Local files (rotation daily/hourly/size, gzip compression)
- **E11y::Adapters::Loki** - Grafana Loki (HTTP POST, gzip, batching, streaming)
- **E11y::Adapters::Sentry** - Error tracking (Sentry SDK, breadcrumbs, severity threshold)
- **E11y::Adapters::Elasticsearch** - Search & analytics (bulk API, index rotation)
- **E11y::Adapters::InMemory** - Test adapter (stores events in array)
- **E11y::Adapters::ConnectionPool** - Connection pooling (pool size 5, acquire/release)
- **E11y::Adapters::RetryHandler** - Exponential backoff retry (3 retries, 1s base delay)
- **E11y::Adapters::CircuitBreaker** - Failure protection (3 states, 5 failure threshold, 60s timeout)
- **E11y::Adapters::AdaptiveBatcher** - Adaptive batching (min 10, max 1000, 5s timeout)

### Configuration Required

**Basic:**
```ruby
E11y.configure do |config|
  config.adapters do
    # Register adapters
    register :stdout, E11y::Adapters::Stdout.new(colorize: true)
    register :file, E11y::Adapters::File.new(
      path: Rails.root.join('log', 'e11y.log'),
      rotation: :daily,
      compress: true
    )
    register :loki, E11y::Adapters::Loki.new(
      url: ENV['LOKI_URL'],
      labels: { app: 'my_app', env: Rails.env },
      batch_size: 100
    )
  end
end
```

**Per-Event Adapter Override:**
```ruby
class Events::OrderPaid < E11y::Event::Base
  # Override global adapters for this event
  adapters [:loki, :file, :sentry]
end

class Events::DebugEvent < E11y::Event::Base
  # Only log to file in development
  adapters [:file, :stdout]
end
```

### APIs / Interfaces
- `E11y::Adapters::Base#write(event_data)` - Synchronous single event write (returns boolean)
- `E11y::Adapters::Base#write_batch(events)` - Synchronous batch write (preferred, returns boolean)
- `E11y::Adapters::Base#healthy?` - Health check (returns boolean)
- `E11y::Adapters::Base#close` - Cleanup connections/buffers (no return value)
- `E11y::Adapters::Base#capabilities` - Feature flags hash (batching, compression, async, streaming)
- `E11y::Adapters::Registry.register(name, adapter_instance)` - Register adapter globally
- `E11y::Adapters::Registry.resolve(name)` - Resolve adapter by name (raises AdapterNotFoundError if not found)
- `E11y::Adapters::Registry.resolve_all(names)` - Resolve multiple adapters (returns array)
- `E11y::Adapters::RetryHandler#with_retry(adapter_name, &block)` - Retry with exponential backoff
- `E11y::Adapters::CircuitBreaker#call(&block)` - Execute with circuit breaker protection

### Data Structures
- **Adapter config:** Hash with adapter-specific options (url, labels, batch_size, rotation, etc.)
- **Registry:** `{ adapter_name => adapter_instance }` (immutable after boot)
- **Circuit breaker state:** `:closed`, `:open`, `:half_open`
- **Connection pool:** Array of adapter instances (pool_size 5)

---

## ❓ Questions & Gaps

### Clarification Needed
1. **Flush worker parallelism:** If flush worker calls multiple adapters (Loki, Sentry, ES), are they flushed serially or in parallel? If serial and one adapter is slow (Loki 1s), does it block others?
2. **Connection pool size:** Is pool size configurable per adapter? Lines 1182 show `pool_size: 5` hardcoded in initialize signature, but is this customizable?
3. **Batching bypass for critical events:** UC-007 mentions "security events MUST be sent immediately", but ADR-004 doesn't describe how to bypass batching. Is there a `flush_immediately` option?

### Missing Information
1. **Adapter capabilities enforcement:** If adapter declares `batching: false`, does E11y skip calling write_batch and use write instead? Or is capabilities purely informational?
2. **Retry policy per adapter:** Can different adapters have different retry policies (e.g., Loki 3 retries, Sentry 5 retries)?
3. **DLQ integration:** Lines 147 and 1459 mention DLQ, but ADR-004 doesn't describe DLQ architecture. Where is DLQ implemented?

### Ambiguities
1. **"Synchronous interface" vs. "async capability"** - Sentry adapter declares `async: true` (line 775) but interface is synchronous (write method). Does this mean Sentry SDK is async internally, or adapter should be async?
2. **"Release lock before I/O"** (lines 638-645, 960-966) - Is this safe? If another thread calls flush while first flush is in progress, what happens?

---

## 🧪 Testing Considerations

### Test Scenarios
1. **Contract validation:** Register adapter without write method, verify error raised
2. **Adapter registry:** Register 3 adapters, resolve by name, verify correct instance returned
3. **Per-event override:** Event with `adapters [:loki]` override, verify only Loki receives event (not Sentry)
4. **Retry policy:** Adapter raises Timeout::Error 2 times, verify 2 retries with exponential backoff (1s, 2s)
5. **Circuit breaker:** Adapter fails 5 times, verify circuit opens (rejects requests for 60s)
6. **Connection pooling:** Acquire 10 connections concurrently (pool size 5), verify pool exhausted → creates new connection
7. **Adaptive batching:** Buffer 5 events (min: 10), wait 5s, verify flush triggered by timeout
8. **In-memory adapter:** Track 100 events, verify all stored in test adapter, clear, verify empty

### Mocking Needs
- `Net::HTTP` - Mock HTTP requests for Loki/ES adapters
- `Sentry` - Mock Sentry SDK for Sentry adapter
- `File` - Mock file I/O for File adapter
- `Time.now` - Stub for testing timeouts, circuit breaker, batching timer

---

## 📊 Complexity Assessment

**Overall Complexity:** Medium

**Reasoning:**
- Abstract base class pattern is familiar to Ruby devs (standard OOP)
- Global registry is simple (hash lookup by name)
- Error handling (retry + circuit breaker) adds state machine complexity
- Connection pooling adds acquire/release pattern (mutex synchronization)
- Adaptive batching adds timer thread, timeout logic, flush triggers
- Per-adapter implementation (Loki, Sentry, ES, File) requires understanding of external APIs
- Testing requires contract tests (shared examples) and in-memory adapter

**Estimated Implementation Time:**
- Junior dev: 12-15 days (base class, registry, 5 adapters, retry, circuit breaker, connection pooling, testing)
- Senior dev: 7-10 days (familiar with adapter pattern, HTTP clients, circuit breaker)

---

## 📚 References

### Related Documentation
- [ADR-001: Core Architecture](../ADR-001-architecture.md) - Pipeline, buffers, middleware chain
- [ADR-002: Metrics & Yabeda](../ADR-002-metrics-yabeda.md) - Self-monitoring for adapter performance
- [UC-005: Sentry Integration](../use_cases/UC-005-sentry-integration.md) - Sentry adapter implementation details

### Similar Solutions
- **Semantic Logger adapters** - Similar pattern but no circuit breaker, no retry
- **Rails ActiveSupport::LogSubscriber** - Similar concept but log-only (not multi-adapter)
- **OpenTelemetry exporters** - Similar abstraction but higher overhead (not <0.5ms target)

### Research Notes
- **Performance targets (lines 79-85):**
  - Adapter overhead: <0.5ms per event (CRITICAL)
  - Connection reuse: 100% (via connection pooling)
  - Retry success rate: >95% (exponential backoff)
  - Test coverage: 100% for base class (contract tests)
- **Trade-offs (line 1692-1698):**
  - Global registry: DRY principle (configure once, reuse everywhere)
  - Batching: 99% use cases benefit (better performance, slight latency acceptable)
  - Connection pooling: Critical for scale (100% connection reuse)
  - Circuit breaker: Reliability critical (prevent cascade failures)
  - Sync interface: Simple to reason about (buffering mitigates blocking)

---

## 🏷️ Tags

`#critical` `#core-architecture` `#adapter-pattern` `#global-registry` `#error-handling` `#retry-policy` `#circuit-breaker` `#connection-pooling` `#batching`

---

**Last Updated:** 2026-01-15  
**Next Review:** Before implementation start (Phase 3 - Consolidated Analysis)

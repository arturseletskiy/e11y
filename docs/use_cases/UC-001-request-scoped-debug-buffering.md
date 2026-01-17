# UC-001: Request-Scoped Debug Buffering

**Status:** Core Feature (MVP)  
**Complexity:** Intermediate  
**Setup Time:** 15-30 minutes  
**Target Users:** DevOps, SRE, Backend Developers

---

## 📋 Overview

### Problem Statement

**Current Pain Points:**
1. **Debug logs in production = noise**
   - 99% of requests succeed → debug logs useless
   - Searching through millions of debug lines for 1% errors
   - High cost (storage, indexing, querying)

2. **No debug = blind debugging**
   - Production errors lack context
   - Can't reproduce: "What SQL ran before error?"
   - Need to deploy debug code → restart → wait for error → repeat

3. **Trade-off dilemma:**
   - Enable debug → drown in logs + high costs
   - Disable debug → can't debug production issues
   - Current "solutions": sampling, manual toggling (not good enough)

### E11y Solution

**Request-scoped buffering (dual-buffer architecture):**
- **Debug events:** Buffered in thread-local storage (per-request)
  - Happy path (99%): Buffer discarded → zero debug events sent
  - Error path (1%): Buffer flushed → all debug context available
- **Other events (info/warn/error/success):** Go to main buffer → flush every 200ms
- **No conflict:** Two separate buffers, different flush logic

**Result:** Debug visibility when needed, zero noise when not. Fast delivery for important events.

---

## 🎯 Use Case Scenarios

### Scenario 1: API Request Debugging

**Context:** Rails API endpoint processes orders

**Without E11y:**
```ruby
# OrdersController
def create
  Rails.logger.debug "Order validation started"  # → Always logged (noise!)
  Rails.logger.debug "Checking inventory for SKU #{params[:sku]}"  # → Always logged
  Rails.logger.debug "Inventory available: #{inventory.count}"  # → Always logged
  
  order = Order.create!(params)
  Rails.logger.info "Order created: #{order.id}"  # → Always logged
  
  render json: order
rescue => e
  Rails.logger.error "Order creation failed: #{e.message}"  # → Logged
  render json: { error: e.message }, status: 500
end

# Result in logs (for 100 successful + 1 failed request):
# - 303 debug lines (3 per request × 101 requests) ← 297 are useless!
# - 101 info lines
# - 1 error line
# Total: 405 lines (74% noise)
```

**With E11y:**
```ruby
# OrdersController
def create
  Events::OrderValidationStarted.track(severity: :debug)  # → Buffered
  Events::InventoryCheck.track(sku: params[:sku], count: inventory.count, severity: :debug)  # → Buffered
  
  order = Order.create!(params)
  Events::OrderCreated.track(order_id: order.id, severity: :success)  # → Sent immediately
  
  render json: order
rescue => e
  # Exception triggers flush of ALL buffered debug events!
  raise  # E11y middleware catches & flushes buffer
end

# Result in logs (for 100 successful + 1 failed request):
# - 0 debug lines for 100 successful requests ← Discarded!
# - 2 debug lines for 1 failed request ← Flushed!
# - 100 success lines
# - 1 error line
# Total: 103 lines (99% noise reduction!)
```

---

### Scenario 2: Multi-Step Business Flow

**Context:** Payment processing with multiple external API calls

**Code:**
```ruby
class ProcessPaymentJob < ApplicationJob
  def perform(order_id)
    order = Order.find(order_id)
    
    # Step 1: Validate
    Events::PaymentValidationStarted.track(order_id: order.id, severity: :debug)
    validator = PaymentValidator.new(order)
    validator.validate!
    Events::PaymentValidationCompleted.track(order_id: order.id, severity: :debug)
    
    # Step 2: Charge card (external API)
    Events::CardChargeStarted.track(order_id: order.id, amount: order.total, severity: :debug)
    response = StripeClient.charge(order.payment_method, order.total)
    Events::CardChargeCompleted.track(order_id: order.id, charge_id: response.id, severity: :debug)
    
    # Step 3: Update inventory (external API)
    Events::InventoryUpdateStarted.track(order_id: order.id, severity: :debug)
    InventoryService.decrement(order.line_items)
    Events::InventoryUpdateCompleted.track(order_id: order.id, severity: :debug)
    
    # Step 4: Success
    Events::PaymentProcessed.track(order_id: order.id, severity: :success)
    
  rescue PaymentValidationError => e
    # Only 2 debug events flushed (Steps 1-2 didn't run)
    raise
  rescue StripeError => e
    # 4 debug events flushed (Steps 1-2 completed, Step 2 failed)
    raise
  rescue InventoryError => e
    # 6 debug events flushed (all steps before Step 3 failed)
    raise
  end
end

# Result:
# - 99 successful jobs: 0 debug events → only 99 :success events
# - 1 failed job (Stripe error): 4 debug events + 1 error event
# Total: 99 + 5 = 104 events (vs 700 without buffering)
```

**Why This is Powerful:**
- Debug events show **exact step** where failure occurred
- No need to guess: "Did validation run? Did Stripe charge succeed?"
- Full context without manual instrumentation changes

---

### Scenario 3: Debugging Database N+1 Queries

**Context:** Controller action with potential N+1 queries

**Code:**
```ruby
class UsersController < ApplicationController
  def index
    @users = User.all
    
    # Auto-instrumentation (via Rails Instrumentation - ASN → E11y)
    # E11y captures all SQL queries as debug events (unidirectional flow)
    # See: ADR-008 §4.1 for Rails Instrumentation architecture
    
    @users.each do |user|
      # N+1 query! Each iteration triggers SELECT from orders
      Events::UserOrderCount.track(
        user_id: user.id,
        count: user.orders.count,  # ← N+1 query here
        severity: :debug
      )
    end
    
    render json: @users
  end
end

# Result (with N+1 but no error):
# - All SQL query debug events discarded (request succeeded)
# - Zero visibility into N+1 problem :(

# Solution: Force flush for slow requests
E11y.configure do |config|
  config.request_scope do
    flush_on :error  # Default
    flush_on_slow_request threshold: 500  # ms ← NEW!
  end
end

# Now:
# - Fast requests (<500ms): debug events discarded
# - Slow requests (>500ms): debug events flushed
# Result: Automatic N+1 detection! Slow request logs show all SQL queries.
```

---

## 🔧 Configuration

### Basic Setup (Automatic)

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.request_scope do
    enabled true  # Default: true
    buffer_limit 100  # Max debug events per request
    flush_on :error  # Flush when exception raised
  end
end
```

**That's it!** Rails middleware auto-installed by generator.

> ⚠️ **CRITICAL: Middleware Order**  
> Request-scoped buffer middleware MUST be positioned correctly in the E11y pipeline. **If you use custom middleware**, ensure buffer routing happens **after** all business logic (validation, PII filtering, rate limiting, sampling) but **before** adapter delivery.  
> 
> **Why:** Buffer routing needs access to fully processed events (with trace context, validated, filtered). If positioned too early, events may be buffered before PII filtering, creating compliance risks.  
> 
> **Consequences of wrong order:**
> - ❌ Buffered debug events may contain unfiltered PII → GDPR violation
> - ❌ Rate-limited events may still be buffered → memory waste
> - ❌ Invalid events may be buffered → validation bypassed
> 
> **Correct order:**  
> ```ruby
> config.pipeline.use TraceContextMiddleware    # 1. Enrich first
> config.pipeline.use ValidationMiddleware      # 2. Fail fast
> config.pipeline.use PiiFilterMiddleware       # 3. Security (BEFORE buffer)
> config.pipeline.use RateLimitMiddleware       # 4. Protection
> config.pipeline.use SamplingMiddleware        # 5. Cost optimization
> config.pipeline.use RoutingMiddleware         # 6. Buffer routing (LAST!)
> ```
> 
> **See:** [ADR-001 Section 4.1: Middleware Execution Order](../ADR-001-architecture.md#41-middleware-execution-order-critical) and [ADR-015: Middleware Order Reference](../ADR-015-middleware-order.md) for detailed explanation.

---

### Advanced Configuration

```ruby
E11y.configure do |config|
  config.request_scope do
    enabled true
    buffer_limit 200  # Larger buffer for complex requests
    
    # Multiple flush triggers
    flush_on :error         # On exception (default)
    flush_on :warn          # On any :warn event
    flush_on :slow_request, threshold: 1000  # On requests >1s
    
    # Custom flush condition
    flush_if do |events, request|
      # Flush if any event contains "payment" in name
      events.any? { |e| e.name.include?('payment') }
    end
    
    # Exclude certain events from buffer (always send)
    exclude_from_buffer do
      severity [:info, :success, :warn, :error, :fatal]  # Only buffer :debug
      event_patterns ['security.*', 'audit.*']  # Never buffer security events
    end
    
    # Buffer overflow strategy
    overflow_strategy :drop_oldest  # or :drop_newest, :flush_immediately
  end
end
```

---

## 📊 How It Works (Technical Details)

### Dual-Buffer Architecture

**E11y использует ДВА независимых буфера:**

```
┌─────────────────────────────────────────────────────────────────┐
│ Request Thread (Rack/Rails)                                     │
│                                                                 │
│  ┌──────────────────────────────────────┐                      │
│  │ E11y::Middleware::Rack               │                      │
│  │  - Initialize request-scoped buffer  │                      │
│  │  - Store in Thread.current[:e11y_*]  │                      │
│  └──────────────────────────────────────┘                      │
│                 ↓                                               │
│  ┌──────────────────────────────────────┐                      │
│  │ Controller Action                    │                      │
│  │                                      │                      │
│  │  Events::DebugEvent.track(...)       │                      │
│  │          ↓                           │                      │
│  │  severity == :debug?                 │                      │
│  │     YES ──→ Request-Scoped Buffer ───┐                     │
│  │              (Thread-local)           │                     │
│  │              Flush: on error/end      │                     │
│  │                                       │                     │
│  │  Events::InfoEvent.track(...)         │                     │
│  │          ↓                           │                     │
│  │  severity >= :info?                  │                     │
│  │     YES ──→ Main Buffer ─────────────┼──→ Flush: every 200ms │
│  │              (Global, SPSC)           │     (Background Thread) │
│  └──────────────────────────────────────┘                      │
│                 ↓                                               │
│  ┌──────────────────────────────────────┐                      │
│  │ Response / Exception                 │                      │
│  │  - Success → Discard debug buffer    │                      │
│  │  - Error → Flush debug buffer        │                      │
│  └──────────────────────────────────────┘                      │
└─────────────────────────────────────────────────────────────────┘

Background Flush Thread (200ms interval):
  Main Buffer → Adapters (Loki, Sentry, etc.)
```

### Buffer Routing Logic

```ruby
# Pseudo-code для понимания
def track_event(event)
  if event.severity == :debug && E11y.request_scope.active?
    # → Request-scoped buffer (Thread-local)
    Thread.current[:e11y_request_buffer] << event
  else
    # → Main buffer (Global SPSC ring buffer)
    E11y.main_buffer << event
    # Фоновый поток заберет через 200ms (или раньше если батч заполнится)
  end
end
```

### Implementation Pseudocode

```ruby
# lib/e11y/middleware/rack.rb
class E11y::Middleware::Rack
  def call(env)
    # 1. Initialize request-scoped buffer
    E11y::RequestScope.initialize_buffer!
    
    # 2. Call application
    status, headers, body = @app.call(env)
    
    # 3. Success → discard buffer
    E11y::RequestScope.discard_buffer!
    
    [status, headers, body]
    
  rescue => exception
    # 4. Error → flush buffer then re-raise
    E11y::RequestScope.flush_buffer!(severity: :error)
    raise
  ensure
    # 5. Cleanup
    E11y::RequestScope.cleanup!
  end
end

# lib/e11y/request_scope.rb
module E11y::RequestScope
  def self.initialize_buffer!
    Thread.current[:e11y_buffer] = []
    Thread.current[:e11y_request_id] = SecureRandom.uuid
  end
  
  def self.buffer_event(event)
    buffer = Thread.current[:e11y_buffer]
    return false unless buffer  # Not in request scope
    
    if event.severity == :debug
      buffer << event
      true  # Event buffered (not sent yet)
    else
      false  # Non-debug events sent immediately
    end
  end
  
  def self.flush_buffer!(severity: :error)
    buffer = Thread.current[:e11y_buffer]
    return if buffer.nil? || buffer.empty?
    
    # Flush all buffered events with specified severity
    buffer.each do |event|
      event.severity = severity if event.severity == :debug
      E11y::Collector.collect(event)
    end
    
    buffer.clear
  end
  
  def self.discard_buffer!
    Thread.current[:e11y_buffer]&.clear
  end
  
  def self.cleanup!
    Thread.current[:e11y_buffer] = nil
    Thread.current[:e11y_request_id] = nil
  end
end
```

---

## 📈 Performance Impact

> **Implementation:** See [ADR-001 Section 8.3: Resource Limits](../ADR-001-architecture.md#83-resource-limits) for architectural details and [ADR-002 Section 6: Self-Monitoring](../ADR-002-metrics-yabeda.md#6-self-monitoring) for metrics implementation.

### Buffer Metrics

**E11y automatically tracks request buffer performance:**

```ruby
# Exposed via Yabeda (auto-configured)
Yabeda.e11y_request_buffer_size  # Gauge: current buffer size per request
Yabeda.e11y_request_buffer_flushes_total  # Counter: buffer flushes by trigger

# Accessible via Prometheus metrics endpoint
# Example queries:

# 1. Average buffer size
avg(e11y_request_buffer_size)

# 2. Buffer flush rate by trigger
rate(e11y_request_buffer_flushes_total{trigger="error"}[5m])

# 3. Buffer overflow alerts
e11y_request_buffer_size >= 100  # Alert if buffer limit reached
```

**Monitoring Examples:**

```ruby
# Grafana dashboard panels:

# Panel 1: Buffer Size Distribution
histogram_quantile(0.99, 
  sum(rate(e11y_request_buffer_size[5m])) by (le)
)
# Shows p99 buffer size

# Panel 2: Flush Triggers Breakdown
sum by (trigger) (
  rate(e11y_request_buffer_flushes_total[5m])
)
# Shows why buffers flush (error vs. slow_request vs. custom)

# Panel 3: Memory Impact Estimate
avg(e11y_request_buffer_size) * 500  # bytes per event
# Estimates per-request memory usage
```

**What to Monitor:**

| Metric | Normal | Warning | Alert |
|--------|--------|---------|-------|
| **Buffer Size (p99)** | <20 events | 50-80 events | >80 events |
| **Flush Rate (error)** | <1% of requests | 1-5% | >5% |
| **Flush Rate (slow)** | <5% of requests | 5-10% | >10% |
| **Buffer Overflows** | 0 | >0 | >10/min |

### Memory

```ruby
# Per-request memory usage

# Typical request (10 debug events):
# - Event object: ~500 bytes
# - Buffer array: ~100 bytes
# Total: ~5KB per request

# Worst case (100 debug events, limit reached):
# Total: ~50KB per request

# Concurrent requests (100):
# - Typical: 100 × 5KB = 500KB
# - Worst: 100 × 50KB = 5MB

# Conclusion: Negligible memory impact (<10MB even at high load)
```

### Latency

```ruby
# Overhead per track() call

# Buffered event (debug):
# - Check Thread.current: ~1μs
# - Append to array: ~0.5μs
# Total: ~1.5μs

# Non-buffered event (info/success):
# - No buffering: 0μs
# - Send to collector: ~20μs (async, non-blocking)

# Conclusion: <2μs overhead for debug events (negligible)
```

---

## 🧪 Testing

### Test Request-Scoped Buffering

```ruby
# spec/requests/orders_spec.rb
RSpec.describe 'Orders API' do
  it 'discards debug events on successful request' do
    # Spy on E11y collector
    allow(E11y::Collector).to receive(:collect)
    
    post '/orders', params: { sku: 'ABC123' }
    
    expect(response).to be_successful
    
    # Verify: only :success event sent, no :debug events
    expect(E11y::Collector).to have_received(:collect).once
    expect(E11y::Collector).to have_received(:collect).with(
      have_attributes(severity: :success)
    )
  end
  
  it 'flushes debug events on error' do
    allow(E11y::Collector).to receive(:collect)
    
    # Trigger error (invalid SKU)
    post '/orders', params: { sku: 'INVALID' }
    
    expect(response).to have_http_status(500)
    
    # Verify: debug events flushed
    expect(E11y::Collector).to have_received(:collect).at_least(2).times
    expect(E11y::Collector).to have_received(:collect).with(
      have_attributes(severity: :debug)
    ).at_least(:once)
  end
end
```

---

## 💡 Best Practices

### ✅ DO

**1. Use :debug for diagnostic events**
```ruby
Events::SqlQuery.track(sql: query, duration: duration, severity: :debug)
Events::CacheHit.track(key: key, severity: :debug)
Events::ApiCallStarted.track(service: 'stripe', severity: :debug)
```

**2. Use :success for business events**
```ruby
Events::OrderPaid.track(order_id: order.id, severity: :success)
Events::UserRegistered.track(user_id: user.id, severity: :success)
```

**3. Set reasonable buffer limits**
```ruby
config.request_scope do
  buffer_limit 100  # Typical: 10-50 debug events per request
end
```

**4. Flush on custom conditions**
```ruby
config.request_scope do
  flush_on :slow_request, threshold: 500  # ms
  flush_if { |events| events.any? { |e| e.name =~ /payment|security/ } }
end
```

---

### ❌ DON'T

**1. Don't buffer non-debug events**
```ruby
# ❌ BAD: Buffering :info events (defeats purpose)
Events::OrderCreated.track(order_id: order.id, severity: :info)  # Should be :success

# ✅ GOOD:
Events::OrderCreated.track(order_id: order.id, severity: :success)
```

**2. Don't set buffer limits too high**
```ruby
# ❌ BAD: Huge buffer (memory risk)
config.request_scope { buffer_limit 10_000 }

# ✅ GOOD: Reasonable limit
config.request_scope { buffer_limit 100 }
```

**3. Don't buffer security events**
```ruby
# ❌ BAD: Security events must be sent immediately!
Events::LoginAttempt.track(user_id: user.id, severity: :debug)

# ✅ GOOD:
Events::LoginAttempt.track(user_id: user.id, severity: :info)
# OR explicitly exclude from buffer:
config.request_scope do
  exclude_from_buffer { event_patterns ['security.*', 'audit.*'] }
end
```

---

## 🔄 Взаимодействие с Flush Interval (200ms)

### Вопрос: Не конфликтуют ли буферы?

**Ответ: НЕТ. Они независимы.**

### Детальная Логика

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  # === Main Buffer (Global) ===
  config.buffer do
    capacity 100_000  # Ring buffer size
    flush_interval 200  # ms - for :info/:warn/:error/:success/:fatal
    flush_batch_size 500
  end
  
  # === Request-Scoped Buffer (Thread-local) ===
  config.request_scope do
    enabled true
    buffer_limit 100  # Per-request limit for :debug only
    flush_on :error  # Flush on exception
  end
end
```

### Поток Событий

**Scenario 1: Обычный запрос (успешный)**
```ruby
# Request starts
Events::DebugEvent.track(...)          # → Request buffer (thread-local)
Events::DebugEvent.track(...)          # → Request buffer (thread-local)
Events::OrderCreated.track(severity: :success)  # → Main buffer → flush in 200ms
Events::DebugEvent.track(...)          # → Request buffer (thread-local)
# Request ends successfully
# → Request buffer DISCARDED (debug events lost)
# → Main buffer flushed every 200ms (success event sent)
```

**Scenario 2: Запрос с ошибкой**
```ruby
# Request starts
Events::DebugEvent.track(...)          # → Request buffer
Events::DebugEvent.track(...)          # → Request buffer
Events::PaymentFailed.track(severity: :error)  # → Main buffer → flush in 200ms
Events::DebugEvent.track(...)          # → Request buffer
# Exception raised!
# → Request buffer FLUSHED immediately (all 3 debug events sent)
# → Main buffer continues flush every 200ms (error event sent)
```

**Scenario 3: Высоконагруженный сервис**
```ruby
# 1000 requests/sec, каждый с 5 debug events
# → 5000 debug events/sec в request buffers (thread-local)
# → 99% успешных → 4950 debug events/sec DISCARDED
# → 1% ошибок → 50 debug events/sec FLUSHED
# 
# Параллельно:
# → 1000 info/success events/sec → Main buffer
# → Flush каждые 200ms = 5 batches/sec
# → 200 events per batch (в среднем)
```

### Итого: Никакого Конфликта!

| Event Type | Buffer | Flush Trigger | Latency |
|------------|--------|---------------|---------|
| `:debug` | Request-scoped (Thread-local) | On error or end-of-request | 0ms (discarded) or immediate (on error) |
| `:info` | Main buffer (Global SPSC) | Every 200ms (background thread) | <200ms |
| `:success` | Main buffer (Global SPSC) | Every 200ms (background thread) | <200ms |
| `:warn` | Main buffer (Global SPSC) | Every 200ms (background thread) | <200ms |
| `:error` | Main buffer (Global SPSC) | Every 200ms (background thread) | <200ms |
| `:fatal` | Main buffer (Global SPSC) | Every 200ms (background thread) | <200ms |

**Преимущества двойного буфера:**
1. ✅ Debug события не засоряют main buffer
2. ✅ Важные события (info+) идут быстро (200ms)
3. ✅ Debug события идут мгновенно при ошибке (flush triggered)
4. ✅ 99% debug событий вообще не обрабатываются (discard = zero cost)
5. ✅ Thread-safety: request buffer изолирован в Thread.current

### Визуальная Диаграмма

```
Time: ──────────────────────────────────────────────────>
      0ms    200ms   400ms   600ms   800ms   1000ms

Request Thread 1 (success):
  ┌─────────────────────┐
  │ :debug → [Req Buf]  │ ← Discarded at end
  │ :debug → [Req Buf]  │ ← Discarded at end
  │ :success → [Main]   │ ─┐
  └─────────────────────┘  │
                           │
Request Thread 2 (error):  │
     ┌────────────────────┐│
     │ :debug → [Req Buf] ││ ← Flushed on error!
     │ :error → [Main]    ││ ─┐
     │ EXCEPTION!         ││  │
     │ Flush req buffer ──┼┼──┼──→ Adapters
     └────────────────────┘│  │
                           │  │
Background Flush Thread:   │  │
  Every 200ms: ────────────┴──┴──→ Adapters
                ↑              ↑
              200ms          400ms
```

### Пример с Цифрами

**Нагрузка:**
- 100 requests/sec
- Каждый запрос: 3 debug события + 1 success событие
- Error rate: 1%

**Что происходит:**

| Time | Request Buffer (Thread-local) | Main Buffer (Global) | Flush |
|------|------------------------------|---------------------|-------|
| 0ms | Req1: [D, D, D] | [S1] | - |
| 10ms | Req2: [D, D, D] | [S1, S2] | - |
| 20ms | Req3: [D, D, D] | [S1, S2, S3] | - |
| ... | ... | ... | - |
| 200ms | Req20: [D, D, D] | [S1...S20] | **Flush 20 success events** |
| 210ms | Req21: [D, D, D] ERROR! | [S21, E21, **D, D, D from Req21**] | **Immediate flush debug** |
| 400ms | - | [S21...S40] | **Flush next batch** |

**Результат:**
- Success events: ~100/sec → flush каждые 200ms → latency <200ms ✅
- Debug events (99%): DISCARDED → zero overhead ✅
- Debug events (1% errors): flushed IMMEDIATELY with error context ✅

---

## 🎯 Success Metrics

### Quantifiable Benefits

**1. Log Volume Reduction**
- Before: 1M debug lines/day
- After: 10K debug lines/day (only errors)
- **Reduction: 99%**

**2. Storage Cost Savings**
- Before: $500/month (ELK ingestion)
- After: $50/month
- **Savings: $450/month (90%)**

**3. Query Performance**
- Before: "Search last 1M lines" = 30 seconds
- After: "Search last 10K lines" = 0.5 seconds
- **Speedup: 60x**

**4. Debugging Efficiency**
- Before: "Guess what happened before error" = 30 minutes
- After: "See full context in logs" = 2 minutes
- **Time saved: 28 minutes per incident**

---

## 🚀 Migration Guide

### From Rails.logger (No Buffering)

**Before:**
```ruby
def create
  Rails.logger.debug "Starting order creation"
  # ... logic ...
  Rails.logger.info "Order created: #{order.id}"
end

# Problem: Always logs debug (even on success)
```

**After:**
```ruby
def create
  Events::OrderCreationStarted.track(severity: :debug)
  # ... logic ...
  Events::OrderCreated.track(order_id: order.id, severity: :success)
end

# Solution: Debug events buffered, only flushed on error
```

---

## 📚 Related Use Cases

- **[UC-002: Business Event Tracking](./UC-002-business-event-tracking.md)** - Define structured events
- **[UC-010: Background Job Tracking](./UC-010-background-job-tracking.md)** - Buffering in Sidekiq/ActiveJob
- **[UC-015: Local Development](./UC-015-local-development.md)** - Test buffering locally

---

**Document Version:** 1.0  
**Last Updated:** January 12, 2026  
**Status:** ✅ Complete

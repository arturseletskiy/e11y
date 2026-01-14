# UC-021: Error Handling, Retry Policy & Dead Letter Queue

**Status:** Reliability Feature (MVP)  
**Complexity:** Intermediate  
**Setup Time:** 20-30 minutes  
**Target Users:** DevOps, SRE, Platform Engineers

---

## 📋 Overview

### Problem Statement

**Current Pain Points:**

1. **Events lost on transient failures**
   - Network timeout → event dropped
   - Elasticsearch temporarily down → no retry
   - Loki 503 error → data loss

2. **No retry mechanism**
   - Single attempt to send event
   - If adapter fails → event lost forever
   - No visibility into failed sends

3. **No dead letter queue**
   - Failed events disappear
   - Can't replay failed events
   - No forensics for why events failed

### E11y Solution

**Robust Error Handling Pipeline:**

- **Retry Policy:** Exponential backoff with jitter
- **Dead Letter Queue:** Failed events stored for later analysis/replay
- **Circuit Breaker:** Prevent cascading failures (already covered in UC-011)
- **Observability:** Metrics for failures, retries, DLQ size

**Result:** Zero data loss, resilient to transient failures.

---

## 🎯 Use Case Scenarios

### Scenario 1: Transient Network Failure

**Problem:** Loki temporarily unavailable (30s downtime)

**Without retry (DATA LOSS!):**
```ruby
Events::OrderCreated.track(order_id: '123')
# → Send to Loki
# → Network timeout (30s)
# → ❌ Event dropped! No retry!
```

**With retry (RESILIENT!):**
```ruby
Events::OrderCreated.track(order_id: '123')
# → Send to Loki
# → Network timeout (30s)
# → Retry #1 after 100ms → Still timeout
# → Retry #2 after 200ms → Still timeout
# → Retry #3 after 400ms → Success! ✅
# Event delivered successfully
```

---

### Scenario 2: Persistent Failure → Dead Letter Queue

**Problem:** Elasticsearch down for maintenance (2 hours)

**Without DLQ (DATA LOSS!):**
```ruby
# 1000 events during 2-hour maintenance window
1000.times do
  Events::OrderCreated.track(...)
  # → All retries exhausted
  # → ❌ All 1000 events lost!
end
```

**With DLQ (NO DATA LOSS!):**
```ruby
# Config:
E11y.configure do |config|
  config.error_handling.dead_letter_queue do
    enabled true
    adapter :dlq_file  # Write to local file
  end
end

# During ES maintenance:
1000.times do
  Events::OrderCreated.track(...)
  # → All retries exhausted
  # → ✅ Event written to DLQ!
end

# After ES maintenance:
# Replay DLQ events
E11y::DeadLetterQueue.replay_all
# → All 1000 events successfully sent!
```

---

### Scenario 3: Partial Adapter Failure

**Problem:** Sentry down, but Loki working

```ruby
class CriticalError < E11y::Event::Base
  adapters [:loki, :sentry, :file]
end

Events::CriticalError.track(error: 'Something went wrong')

# Loki: ✅ Success
# Sentry: ❌ Timeout (retries exhausted)
# File: ✅ Success

# Result:
# - Event in Loki ✅
# - Event in File ✅
# - Event in DLQ (for Sentry) ✅
#
# Later: Replay DLQ → Send to Sentry when it's back up
```

---

### Scenario 4: DLQ Filter (Critical vs. Non-Critical Events)

**Problem:** DLQ fills with unimportant events (health checks, metrics).

**Without DLQ filter (BAD!):**
```ruby
# Health checks fill DLQ
1000.times do
  Events::HealthCheck.track(status: 'ok')
  # Loki down → All 1000 health checks in DLQ!
end

# DLQ full of unimportant events 😞
E11y::DeadLetterQueue.size  # => 1000 (mostly garbage)
```

**With DLQ filter (GOOD!):**
```ruby
# Config:
E11y.configure do |config|
  config.error_handling.dead_letter_queue.filter do
    # Don't save health checks to DLQ
    never_save do
      event_patterns ['health_check.*', 'ping.*']
    end
    
    # Always save payments
    always_save do
      event_patterns ['payment.*', 'order.*']
    end
  end
end

# Health checks (not saved to DLQ):
1000.times do
  Events::HealthCheck.track(status: 'ok')
  # Loki down → ❌ Retries exhausted → Dropped (not in DLQ)
end

# Payment (saved to DLQ):
Events::PaymentFailed.track(order_id: '123', amount: 500)
# Loki down → ❌ Retries exhausted → ✅ Saved to DLQ!

# DLQ only contains critical events
E11y::DeadLetterQueue.size  # => 1 (only payment)
```

---

## 🏗️ Architecture

> **Implementation:** See [ADR-013: Reliability & Error Handling](../ADR-013-reliability-error-handling.md) for complete error handling architecture, including retry policy with exponential backoff and jitter, circuit breaker pattern, Dead Letter Queue (DLQ) storage strategies, and self-monitoring metrics.

### Retry Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│ Event Flow with Retry & DLQ                                     │
│                                                                  │
│  Event.track(...)                                                │
│      ↓                                                           │
│  Main Buffer                                                     │
│      ↓                                                           │
│  Flush (every 200ms)                                             │
│      ↓                                                           │
│  ┌────────────────────────────────────────┐                     │
│  │ Try: Send to Adapter                   │                     │
│  └────────────────────────────────────────┘                     │
│      ↓                                                           │
│  Success? ──YES──→ ✅ Done                                      │
│      │                                                           │
│      NO (Error)                                                  │
│      ↓                                                           │
│  ┌────────────────────────────────────────┐                     │
│  │ Retry Policy: Exponential Backoff     │                     │
│  │  - Retry #1 after 100ms                │                     │
│  │  - Retry #2 after 200ms (×2)           │                     │
│  │  - Retry #3 after 400ms (×2)           │                     │
│  │  - Max 3 retries                       │                     │
│  └────────────────────────────────────────┘                     │
│      ↓                                                           │
│  All retries exhausted?                                          │
│      ↓                                                           │
│  ┌────────────────────────────────────────┐                     │
│  │ Dead Letter Queue (DLQ)                │                     │
│  │  - Store failed event                  │                     │
│  │  - Store error details                 │                     │
│  │  - Store retry attempts                │                     │
│  │  - Allow replay later                  │                     │
│  └────────────────────────────────────────┘                     │
│      ↓                                                           │
│  ✅ Event preserved for later replay                            │
└─────────────────────────────────────────────────────────────────┘
```

### Exponential Backoff with Jitter

```
Retry Delays (with jitter):

Retry #1: 100ms + random(0-50ms)   = 100-150ms
Retry #2: 200ms + random(0-100ms)  = 200-300ms
Retry #3: 400ms + random(0-200ms)  = 400-600ms

Max delay: 5 seconds (configurable)

Jitter prevents "thundering herd" problem
```

---

## 🔧 Configuration

### Basic Setup

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.error_handling do
    # === Retry Policy ===
    retry_policy do
      enabled true
      max_retries 3
      initial_delay 0.1.seconds  # 100ms
      max_delay 5.seconds
      multiplier 2  # Exponential: 100ms, 200ms, 400ms
      jitter true   # Add randomness to prevent thundering herd
    end
    
    # === Dead Letter Queue ===
    dead_letter_queue do
      enabled true
      
      # Where to store failed events
      adapter :dlq_file  # Reference to registered adapter
      
      # Or use specific DLQ adapter
      # adapter E11y::Adapters::FileAdapter.new(
      #   path: Rails.root.join('log', 'e11y_dlq'),
      #   rotation: :daily
      # )
      
      # Max events in DLQ before alerting
      max_size 10_000
      
      # Alert when DLQ grows
      alert_on_size 1000  # Alert at 1000 events
    end
    
    # What to do after max_retries exhausted
    on_max_retries_exceeded :send_to_dlq  # :send_to_dlq, :drop, :log
    
    # Which errors are retryable
    retryable_errors [
      Errno::ETIMEDOUT,
      Errno::ECONNREFUSED,
      Errno::ECONNRESET,
      Net::OpenTimeout,
      Net::ReadTimeout,
      HTTP::TimeoutError
    ]
    
    # Which errors are NOT retryable (fail immediately)
    non_retryable_errors [
      E11y::ValidationError,  # Schema validation failed
      E11y::RateLimitError    # Rate limit exceeded
    ]
  end
end
```

### Advanced Configuration

```ruby
E11y.configure do |config|
  config.error_handling do
    retry_policy do
      enabled true
      max_retries 5  # More retries for critical systems
      
      # Adaptive retry delays
      delays [0.1, 0.2, 0.5, 1, 2]  # Custom delays in seconds
      
      # Or exponential with custom params
      initial_delay 0.05.seconds
      max_delay 10.seconds
      multiplier 2.5  # Faster exponential growth
      jitter_range 0.5  # ±50% jitter
      
      # Per-adapter retry configuration
      per_adapter do
        adapter :loki do
          max_retries 3
          initial_delay 0.1
        end
        
        adapter :sentry do
          max_retries 5  # More retries for Sentry
          initial_delay 0.5
        end
      end
      
      # Retry predicate (custom logic)
      retry_if do |error, attempt|
        # Custom logic: retry only for specific errors
        error.is_a?(Net::ReadTimeout) && attempt < 5
      end
    end
    
    dead_letter_queue do
      enabled true
      adapter :dlq_file
      
      # DLQ retention
      retention 7.days  # Auto-delete old DLQ events
      
      # DLQ partitioning (for large volumes)
      partition_by :adapter  # Separate DLQ per adapter
      # log/e11y_dlq/loki/2026-01-12.jsonl
      # log/e11y_dlq/sentry/2026-01-12.jsonl
      
      # Compression
      compression :gzip  # Compress DLQ files
      
      # Metadata
      include_metadata true  # Store error details, retry count
      
      # ===== DLQ FILTER (Critical!) =====
      # Control which events are saved to DLQ vs. dropped
      filter do
        # Always save critical events to DLQ (never drop!)
        always_save do
          severity [:error, :fatal]  # All errors must be preserved
          event_patterns [
            'payment.*',     # Payment events are critical
            'order.*',       # Order events are critical
            'audit.*',       # Audit events must never be lost
            'security.*',    # Security events are critical
            'fraud.*'        # Fraud detection events
          ]
        end
        
        # Never save to DLQ (drop after max retries)
        never_save do
          severity [:debug]  # Debug events can be dropped
          event_patterns [
            'metrics.*',       # Metrics can be dropped (regenerated)
            'health_check.*',  # Health checks not critical
            'ping.*'           # Ping events not important
          ]
        end
        
        # Custom filter function
        save_if do |event|
          # Example: Save high-value payments only
          if event.name.include?('payment') && event.payload[:amount]
            event.payload[:amount] > 100  # Only save payments >$100
          else
            true  # Save all other events by default
          end
        end
      end
    end
    
    # Fallback chain
    fallback_chain do
      # If primary adapter fails after retries:
      # 1. Try fallback adapter
      # 2. If fallback fails → DLQ
      
      adapter :loki do
        fallback :file  # Loki fails → write to file
      end
      
      adapter :sentry do
        fallback nil  # Sentry fails → DLQ directly
      end
    end
  end
end
```

---

## 📝 DLQ Management

### Replay DLQ Events

```ruby
# Replay all DLQ events
E11y::DeadLetterQueue.replay_all

# Replay specific adapter's DLQ
E11y::DeadLetterQueue.replay(adapter: :loki)

# Replay with filtering
E11y::DeadLetterQueue.replay do |event|
  # Only replay events from last hour
  event.timestamp > 1.hour.ago
end

# Replay with rate limiting
E11y::DeadLetterQueue.replay(
  rate_limit: 100,  # 100 events/sec
  batch_size: 50
)
```

### Inspect DLQ

```ruby
# Count events in DLQ
E11y::DeadLetterQueue.size
# => 1234

# Peek at DLQ (first 10 events)
E11y::DeadLetterQueue.peek(limit: 10)
# => [<Event>, <Event>, ...]

# Get DLQ stats
E11y::DeadLetterQueue.stats
# => {
#   total: 1234,
#   by_adapter: { loki: 1000, sentry: 234 },
#   oldest: 2.hours.ago,
#   newest: 5.minutes.ago
# }

# Find specific events
E11y::DeadLetterQueue.find do |event|
  event.name == 'order.paid' && event.payload[:amount] > 1000
end
```

### Clean DLQ

```ruby
# Clear all DLQ events
E11y::DeadLetterQueue.clear!

# Clear old events (older than 7 days)
E11y::DeadLetterQueue.clear_old!(7.days)

# Clear by adapter
E11y::DeadLetterQueue.clear!(adapter: :loki)
```

---

## 💡 Best Practices

### ✅ DO

**1. Enable retry for transient errors**
```ruby
# ✅ GOOD: Retry on network errors
config.error_handling.retry_policy do
  enabled true
  retryable_errors [
    Errno::ETIMEDOUT,
    Net::ReadTimeout,
    HTTP::TimeoutError
  ]
end
```

**2. Use DLQ for critical events**
```ruby
# ✅ GOOD: DLQ enabled for zero data loss
config.error_handling.dead_letter_queue do
  enabled true
  adapter :dlq_file
end
```

**3. Monitor DLQ size**
```ruby
# ✅ GOOD: Alert when DLQ grows
config.error_handling.dead_letter_queue do
  max_size 10_000
  alert_on_size 1000
end

# Set up Prometheus alert:
# alert: DLQSizeHigh
# expr: e11y_dlq_size > 1000
```

**4. Replay DLQ regularly**
```ruby
# ✅ GOOD: Schedule DLQ replay
# config/schedule.rb (whenever gem)
every 10.minutes do
  runner "E11y::DeadLetterQueue.replay_all"
end

# Or Sidekiq job:
class E11yDlqReplayJob
  include Sidekiq::Job
  
  def perform
    E11y::DeadLetterQueue.replay_all
  end
end

# Schedule every 10 minutes
```

---

### ❌ DON'T

**1. Don't retry non-retryable errors**
```ruby
# ❌ BAD: Retrying validation errors (will always fail)
config.error_handling.retry_policy do
  retryable_errors [
    E11y::ValidationError  # ← Will NEVER succeed!
  ]
end

# ✅ GOOD: Skip retry for validation errors
config.error_handling.non_retryable_errors [
  E11y::ValidationError,
  E11y::RateLimitError
]
```

**2. Don't set too many retries**
```ruby
# ❌ BAD: Too many retries (adds latency)
config.error_handling.retry_policy do
  max_retries 20  # ← Too many! Total delay: minutes
end

# ✅ GOOD: Reasonable retry count
config.error_handling.retry_policy do
  max_retries 3  # ← Enough for transient errors
  # Total delay: ~700ms (acceptable)
end
```

**3. Don't ignore DLQ growth**
```ruby
# ❌ BAD: No monitoring, DLQ grows indefinitely
config.error_handling.dead_letter_queue do
  enabled true
  # No max_size, no alerts!
end

# ✅ GOOD: Monitor and alert
config.error_handling.dead_letter_queue do
  enabled true
  max_size 10_000
  alert_on_size 1000
  
  # Auto-cleanup old events
  retention 7.days
end
```

---

## 📊 Monitoring & Metrics

### Self-Monitoring Metrics

```ruby
# E11y automatically exports these metrics:

# Retries
e11y_retries_total{adapter, error_type}  # Counter
e11y_retry_attempts{adapter}  # Histogram (how many retries before success)

# DLQ
e11y_dlq_size{adapter}  # Gauge (current DLQ size)
e11y_dlq_events_added_total{adapter, error_type}  # Counter
e11y_dlq_events_replayed_total{adapter, status}  # Counter (status: success/failure)

# Errors
e11y_adapter_errors_total{adapter, error_type, retryable}  # Counter
e11y_max_retries_exceeded_total{adapter}  # Counter
```

### Prometheus Alerts

```yaml
groups:
  - name: e11y_error_handling
    rules:
      # DLQ growing
      - alert: E11yDLQSizeHigh
        expr: e11y_dlq_size > 1000
        for: 5m
        annotations:
          summary: "E11y DLQ has >1000 events"
          
      # High retry rate
      - alert: E11yHighRetryRate
        expr: rate(e11y_retries_total[5m]) > 10
        for: 5m
        annotations:
          summary: "E11y retrying >10 events/sec"
          
      # Max retries exceeded
      - alert: E11yMaxRetriesExceeded
        expr: rate(e11y_max_retries_exceeded_total[5m]) > 1
        for: 5m
        annotations:
          summary: "E11y events failing after max retries"
```

---

## 🧪 Testing

### RSpec Examples

```ruby
RSpec.describe 'E11y Error Handling' do
  describe 'Retry Policy' do
    it 'retries on transient errors' do
      adapter = instance_double(E11y::Adapters::LokiAdapter)
      
      # First 2 attempts fail, 3rd succeeds
      allow(adapter).to receive(:write_batch)
        .and_raise(Net::ReadTimeout).twice
      allow(adapter).to receive(:write_batch)
        .and_return(E11y::Result.success).once
      
      Events::OrderCreated.track(order_id: '123')
      
      # Should retry twice, then succeed
      expect(adapter).to have_received(:write_batch).exactly(3).times
    end
    
    it 'does not retry non-retryable errors' do
      adapter = instance_double(E11y::Adapters::LokiAdapter)
      
      allow(adapter).to receive(:write_batch)
        .and_raise(E11y::ValidationError)
      
      Events::OrderCreated.track(order_id: '123')
      
      # Should try once, then give up (no retry)
      expect(adapter).to have_received(:write_batch).once
    end
  end
  
  describe 'Dead Letter Queue' do
    it 'sends to DLQ after max retries' do
      adapter = instance_double(E11y::Adapters::LokiAdapter)
      
      # All retries fail
      allow(adapter).to receive(:write_batch)
        .and_raise(Net::ReadTimeout)
      
      expect {
        Events::OrderCreated.track(order_id: '123')
      }.to change { E11y::DeadLetterQueue.size }.by(1)
    end
    
    it 'replays DLQ events' do
      # Add event to DLQ
      E11y::DeadLetterQueue.add(
        event: build_event(name: 'order.created'),
        adapter: :loki,
        error: 'Network timeout'
      )
      
      adapter = instance_double(E11y::Adapters::LokiAdapter)
      allow(adapter).to receive(:write_batch).and_return(E11y::Result.success)
      
      # Replay DLQ
      E11y::DeadLetterQueue.replay_all
      
      # DLQ should be empty
      expect(E11y::DeadLetterQueue.size).to eq(0)
      
      # Event should be sent
      expect(adapter).to have_received(:write_batch).once
    end
  end
end
```

---

## 🔗 Related Use Cases

- **[UC-011: Rate Limiting](./UC-011-rate-limiting.md)** - Protect system from overload
- **[UC-015: Cost Optimization](./UC-015-cost-optimization.md)** - Sampling and compression for cost reduction
- **[CONFLICT-ANALYSIS](../CONFLICT-ANALYSIS.md)** - Circuit Breaker interaction

---

## 🚀 Quick Start Checklist

- [ ] Enable retry policy in config
- [ ] Configure max_retries (recommend: 3)
- [ ] Enable dead letter queue
- [ ] Configure DLQ adapter (file or database)
- [ ] Set up DLQ replay job (every 10 minutes)
- [ ] Configure Prometheus alerts for DLQ size
- [ ] Test retry behavior in staging
- [ ] Monitor retry rate and DLQ growth

---

**Status:** ✅ Reliability Feature  
**Priority:** High (zero data loss)  
**Complexity:** Intermediate

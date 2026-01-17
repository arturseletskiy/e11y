# UC-011: Rate Limiting (DoS Protection)

**Status:** MVP Feature (Critical for Production)  
**Complexity:** Intermediate  
**Setup Time:** 20-30 minutes  
**Target Users:** Security Engineers, SRE, Backend Developers

---

## 📋 Overview

### Problem Statement

**The production incident:**
```ruby
# ❌ NO RATE LIMITING: Infinite retry storm
begin
  process_payment(order)
rescue PaymentError => e
  # Retry immediately (bad idea!)
  3.times do
    Events::PaymentRetry.track(order_id: order.id, attempt: _1)
  end
end

# What happened:
# - 1000 failed payments
# - 3000 retry events
# - × 100 fields per event
# - = 300,000 events in 10 seconds
# → Buffer overflow
# → Loki API rate limit hit (429)
# → All observability lost during incident! 😱
```

**Real incident impact:**
- **09:00 AM**: Payment gateway down
- **09:01 AM**: 50k retry events/sec flooding E11y
- **09:02 AM**: Loki returns 429 (rate limit)
- **09:03 AM**: E11y buffer full, events dropped
- **09:05 AM**: **No observability** - blind during incident
- **09:30 AM**: Incident resolved, but root cause unclear (no logs!)

### E11y Solution

**3-Layer Rate Limiting (Global + Per-Event + Per-Context):**
```ruby
# ✅ PROTECTED: Multi-layer rate limiting
E11y.configure do |config|
  config.rate_limiting do
    # Layer 1: Global limit (protect buffer)
    global limit: 10_000, window: 1.minute
    
    # Layer 2: Per-event limit (prevent retry storms)
    per_event 'payment.retry', limit: 100, window: 1.minute
    
    # Layer 3: Per-context limit (per user/IP)
    per_context :user_id, limit: 1_000, window: 1.minute
    per_context :ip_address, limit: 500, window: 1.minute
    
    # What happens when limit exceeded:
    on_exceeded :sample  # Keep 10%, drop 90%
    sample_rate 0.1
    
    # Alert on rate limiting
    alert_on_limit true
    alert_channel '#observability'
  end
end

# Result during incident:
# - Global limit: 10k/min enforced
# - Payment retry: 100/min enforced
# - Per user: 1k/min enforced
# → Observability maintained ✅
# → Root cause identified quickly ✅
```

---

## 🎯 Event-Level Rate Limiting (NEW - v1.1)

> **🎯 CONTRADICTION_01 Resolution:** Move rate limiting config from global initializer to event classes.

**Event-level rate limiting DSL:**

```ruby
# app/events/payment_retry.rb
module Events
  class PaymentRetry < E11y::Event::Base
    schema do
      required(:order_id).filled(:string)
      required(:attempt).filled(:integer)
    end
    
    # ✨ Event-level rate limiting (right next to schema!)
    rate_limit 100, window: 1.minute  # Max 100 retries/min
    on_exceeded :drop  # Drop retry logs (not critical)
  end
end

# app/events/user_login_failed.rb
module Events
  class UserLoginFailed < E11y::Event::Base
    schema do
      required(:user_id).filled(:string)
      required(:ip_address).filled(:string)
    end
    
    # ✨ Event-level rate limiting
    rate_limit 50, window: 1.minute  # Max 50 failures/min
    on_exceeded :sample  # Keep 20% (flattened syntax!)
    sample_rate 0.2
  end
end
```

**Inheritance for rate limiting:**

```ruby
# Base class with common rate limiting
module Events
  class BaseDebugEvent < E11y::Event::Base
    # Common for ALL debug events
    severity :debug
    rate_limit 100, window: 1.minute  # Low limit
    on_exceeded :drop  # Drop debug logs (not critical)
    sample_rate 0.01  # 1% sampling
  end
end

# Inherit from base
class Events::DebugSqlQuery < Events::BaseDebugEvent
  schema do; required(:query).filled(:string); end
  # ← Inherits: rate_limit 100 + on_exceeded :drop
end

class Events::DebugApiCall < Events::BaseDebugEvent
  schema do; required(:endpoint).filled(:string); end
  # ← Inherits: rate_limit 100 + on_exceeded :drop
end
```

**Preset modules for rate limiting:**

```ruby
# lib/e11y/presets/high_value_event.rb
module E11y
  module Presets
    module HighValueEvent
      extend ActiveSupport::Concern
      included do
        rate_limit 10_000  # High limit
        on_exceeded :throttle  # Slow down, don't drop
        sample_rate 1.0  # Never sample
      end
    end
    
    module DebugEvent
      extend ActiveSupport::Concern
      included do
        rate_limit 100  # Low limit
        on_exceeded :drop  # Drop debug logs
        sample_rate 0.01  # 1% sampling
      end
    end
  end
end

# Usage:
class Events::PaymentProcessed < E11y::Event::Base
  include E11y::Presets::HighValueEvent  # ← Rate limit inherited!
  schema do; required(:transaction_id).filled(:string); end
end
```

**Conventions for rate limiting (sensible defaults):**

```ruby
# Convention: Default rate limit = 1000 events/sec
# Override only for high-volume or low-volume events

# Zero-config event (uses convention):
class Events::OrderCreated < E11y::Event::Base
  schema do; required(:order_id).filled(:string); end
  # ← Auto: rate_limit = 1000 (default)
end

# Override for high-volume:
class Events::PageView < E11y::Event::Base
  rate_limit 10_000  # ← Override: high-volume
  schema do; required(:page).filled(:string); end
end

# Override for low-volume:
class Events::DebugQuery < E11y::Event::Base
  rate_limit 100  # ← Override: low-volume
  schema do; required(:query).filled(:string); end
end
```

**Precedence (event-level overrides global):**

```ruby
# Global config (infrastructure):
E11y.configure do |config|
  config.rate_limiting do
    global limit: 10_000, window: 1.minute
    default_per_event_limit 1000  # Default for events
  end
end

# Event-level config (overrides global):
class Events::PaymentRetry < E11y::Event::Base
  rate_limit 100  # ← Override: 100 (not 1000)
  on_exceeded :drop  # ← Override: drop (not default)
end
```

**Benefits:**
- ✅ Locality of behavior (rate limit next to schema)
- ✅ DRY via inheritance/presets
- ✅ Sensible defaults (1000/sec)
- ✅ Easy to override when needed

---

## 🎯 The 3-Layer Rate Limiting System

### Layer 1: Global Rate Limiting

**Protect E11y infrastructure from flooding:**

```ruby
E11y.configure do |config|
  config.rate_limiting do
    # === GLOBAL LIMIT ===
    # Across ALL events, ALL sources
    global limit: 10_000,        # Max 10k events
           window: 1.minute,      # Per minute
           algorithm: :sliding_window  # OR :token_bucket, :fixed_window
    
    # What happens when exceeded:
    on_exceeded :sample  # Options: :drop, :sample, :throttle
    sample_rate 0.1      # Keep 10% when over limit
    
    # Track dropped events
    track_drops true
  end
end

# How it works:
# - Counts events across entire system
# - If > 10k/min → apply sample_rate (90% dropped)
# - Metrics: e11y_rate_limit_global_hits_total
```

**Algorithms:**

| Algorithm | Behavior | Use Case |
|-----------|----------|----------|
| `:sliding_window` | Smooth rate control | **Default** (best for most cases) |
| `:token_bucket` | Allows bursts | APIs with bursty traffic |
| `:fixed_window` | Simple but has edge cases | Low-volume scenarios |

---

### Layer 2: Per-Event Rate Limiting

**Prevent specific events from flooding:**

```ruby
E11y.configure do |config|
  config.rate_limiting do
    # === PER-EVENT LIMITS ===
    
    # Retry events (common culprit)
    per_event 'payment.retry',
              limit: 100,
              window: 1.minute,
              on_exceeded: :drop  # Drop retry logs (not critical)
    
    # Login failures (security)
    per_event 'user.login.failed',
              limit: 50,
              window: 1.minute,
              on_exceeded: :sample,
              sample_rate: 0.2  # Keep 20%
    
    # API errors (debugging)
    per_event 'api.error',
              limit: 200,
              window: 1.minute,
              on_exceeded: :throttle  # Slow down, don't drop
    
    # Background job failures
    per_event 'job.failed',
              limit: 500,
              window: 5.minutes,
              on_exceeded: :sample,
              sample_rate: 0.1
  end
end

# Usage:
Events::PaymentRetry.track(order_id: '123', attempt: 1)
Events::PaymentRetry.track(order_id: '456', attempt: 1)
# ... 99 more in same minute → All tracked

Events::PaymentRetry.track(order_id: '789', attempt: 1)
# → 101st event in minute → DROPPED (limit: 100)
# → Metric: e11y_rate_limit_per_event_hits_total{event="payment.retry"}
```

---

### Layer 3: Per-Context Rate Limiting

**Prevent single user/IP/tenant from flooding:**

```ruby
E11y.configure do |config|
  config.rate_limiting do
    # === PER-CONTEXT LIMITS ===
    
    # Per user (prevent single user abuse)
    per_context :user_id,
                limit: 1_000,
                window: 1.minute,
                on_exceeded: :sample,
                sample_rate: 0.1
    
    # Per IP address (prevent DDoS)
    per_context :ip_address,
                limit: 500,
                window: 1.minute,
                on_exceeded: :drop
    
    # Per tenant (multi-tenant apps)
    per_context :tenant_id,
                limit: 5_000,
                window: 1.minute,
                on_exceeded: :throttle
    
    # Per session (prevent session replay attacks)
    per_context :session_id,
                limit: 200,
                window: 1.minute,
                on_exceeded: :drop
  end
end

# How it works:
# User A: 1000 events/min → OK
# User A: 1001st event → 90% dropped (sample_rate 0.1)
# User B: 1000 events/min → OK (separate limit)
```

**Context extraction:**
```ruby
# E11y automatically extracts context from:
# 1. Event payload: event.payload[:user_id]
# 2. Event context: event.context[:user_id]
# 3. Rails Current: Current.user_id
# 4. Custom extractor:

E11y.configure do |config|
  config.rate_limiting do
    per_context :user_id,
                limit: 1_000,
                window: 1.minute,
                extractor: ->(event) {
                  # Custom logic to extract user_id
                  event.payload[:user_id] || event.context[:current_user]&.id
                }
  end
end
```

---

### Layer 4: DLQ Filter Integration (C02 Resolution) ⚠️

> **Reference:** See [ADR-013 §4.6: Rate Limiting × DLQ Filter](../ADR-013-reliability-error-handling.md#46-rate-limiting--dlq-filter-interaction-c02-resolution) for full architecture.

**Problem:** Rate limiting drops events BEFORE they reach DLQ filter. Critical events (e.g., payments) may be lost during traffic spikes, even though DLQ filter says "always save payments".

**Solution:** Rate limiter respects DLQ `always_save` filter - critical events bypass rate limits.

```ruby
E11y.configure do |config|
  config.rate_limiting do
    enabled true
    global limit: 10_000, window: 1.minute
    
    # ✅ Respect DLQ filter for critical events
    respect_dlq_filter true  # Critical events bypass rate limits!
    
    # Alternative: Explicit bypass patterns
    bypass_for do
      event_patterns ['payment.*', 'order.*', 'audit.*']
      severities [:error, :fatal]
    end
  end
  
  # DLQ filter configuration
  config.error_handling.dead_letter_queue.filter do
    always_save do
      event_patterns ['payment.*', 'order.*']
    end
  end
end

# Scenario: Traffic spike (15,000 payment failures/sec)
15_000.times do
  Events::PaymentFailed.track(order_id: '123', amount: 500)
end

# Result:
# - Rate limit: 10,000/min
# - Excess: 5,000 events over limit
# - ❌ WITHOUT C02 fix: 5,000 critical payment events DROPPED!
# - ✅ WITH C02 fix: ALL payment events processed (bypass rate limit!)
#   → Why? DLQ filter says "always_save payment.*"
#   → Rate limiter checks: dlq_filter.always_save?(event) → true
#   → Bypass rate limit → event goes to buffer → success!
```

**Flow Diagram:**

```
Event → Rate Limiter
  ├─ Check: dlq_filter.always_save?(event)?
  │   ├─ YES (critical event) → ✅ BYPASS rate limit → Buffer
  │   └─ NO (non-critical)
  │       ├─ Under limit? → ✅ PASS → Buffer
  │       └─ Over limit? → ❌ DROP (or sample)
  └─ Buffer → Adapter → DLQ (if adapter fails)
```

**Configuration Options:**

```ruby
# Option 1: Auto-respect DLQ filter (recommended)
config.rate_limiting.respect_dlq_filter = true

# Option 2: Explicit bypass patterns (more control)
config.rate_limiting.bypass_for do
  event_patterns ['payment.*', 'fraud.*', 'security.*']
  severities [:error, :fatal]
  custom_check { |event| event[:vip_customer] == true }
end

# Option 3: Hybrid (DLQ filter + extra patterns)
config.rate_limiting do
  respect_dlq_filter true  # Respect DLQ always_save
  bypass_for do
    event_patterns ['audit.*']  # Additional patterns
  end
end
```

**Trade-offs:**

| Aspect | Pro | Con | Decision |
|--------|-----|-----|----------|
| **Bypass critical events** | Zero data loss for payments | Rate limit less effective during attacks | Critical events > rate limits |
| **respect_dlq_filter** | DRY (single source of truth) | Tight coupling to DLQ config | Worth it for simplicity |
| **bypass_for patterns** | Flexible custom rules | Need to maintain bypass list | Use for edge cases only |

---

### Layer 5: Retry Rate Limiting (C06 Resolution) ⚠️

> **Reference:** See [ADR-013 §3.5: Retry Rate Limiting](../ADR-013-reliability-error-handling.md#35-retry-rate-limiting-c06-resolution) for full architecture.

**Problem:** Adapter failures trigger retries. If 1000 events fail → 3000 retry attempts (thundering herd) → buffer overflow.

**Solution:** Separate rate limit for RETRIES (staged retry with jitter).

```ruby
E11y.configure do |config|
  config.error_handling do
    retry_policy do
      max_attempts 3
      base_delay 100  # ms
      max_delay 5000  # ms
      exponential_backoff true
      jitter true
      
      # ✅ Retry rate limiting (separate from main rate limit!)
      retry_rate_limit do
        enabled true
        limit 1000        # Max 1000 retries/minute (not 10k!)
        window 1.minute
        
        # When retry is rate-limited:
        on_limit_exceeded :delay  # Options: :drop, :delay, :dlq
        
        # Delay strategy (staged retry)
        delay_strategy do
          base_delay 1000      # 1 sec
          max_delay 60_000     # 60 sec
          backoff_multiplier 2 # 1s → 2s → 4s → 8s → 16s → 32s → 60s
          jitter_range 0.2     # ±20% randomization
        end
      end
    end
  end
end

# Scenario: Loki down for 5 minutes (adapter fails)
# - 10,000 events/min attempted
# - Adapter fails → 10,000 events need retry
# - Without retry rate limiting:
#   - 10,000 × 3 attempts = 30,000 retries
#   - Immediate retry storm (buffer overflow!)
# - With retry rate limiting:
#   - First retry: 1,000 events (rate limit enforced)
#   - Next 9,000 events: delayed (staged retry)
#   - Retry schedule:
#     - 00:00 - 1,000 retries (immediate)
#     - 00:01 - 1,000 retries (delayed 1s)
#     - 00:02 - 1,000 retries (delayed 2s)
#     - 00:04 - 1,000 retries (delayed 4s)
#     - ... (exponential backoff)
#     - 01:00 - Last batch (delayed 60s)
#   - Result: ✅ No buffer overflow! Smooth retry spread over time.
```

**Retry Timeline Comparison:**

```
WITHOUT retry rate limiting:
00:00 Loki down
00:00 10,000 events fail → 30,000 immediate retries ❌ BUFFER OVERFLOW!
00:01 All retries exhausted, 10,000 events lost

WITH retry rate limiting:
00:00 Loki down
00:00 10,000 events fail → 1,000 immediate retries (rate limited)
00:01 1,000 retries (delayed)
00:02 1,000 retries (delayed)
00:04 1,000 retries (delayed)
00:08 1,000 retries (delayed)
00:16 1,000 retries (delayed)
00:32 1,000 retries (delayed)
01:00 1,000 retries (delayed)
02:00 1,000 retries (delayed)
04:00 1,000 retries (delayed)
05:00 Loki back online → 1,000 final retries → ✅ All 10,000 events saved!
```

**Configuration: Main Rate Limit vs Retry Rate Limit**

```ruby
E11y.configure do |config|
  # Main rate limiting (for NEW events)
  config.rate_limiting do
    global limit: 10_000, window: 1.minute
    on_exceeded :sample  # Sample excess events
  end
  
  # Retry rate limiting (for FAILED events)
  config.error_handling.retry_policy.retry_rate_limit do
    limit: 1_000, window: 1.minute  # 10× LOWER than main limit!
    on_limit_exceeded :delay         # Delay excess retries (don't drop!)
  end
end

# Why separate limits?
# 1. Retries are MORE expensive (adapter already failed once)
# 2. Lower retry rate prevents cascading failures (give adapter time to recover)
# 3. Main limit protects ingestion, retry limit protects adapter
```

**Trade-offs:**

| Aspect | Pro | Con | Decision |
|--------|-----|-----|----------|
| **Retry rate limit 10× lower** | Prevents adapter overload | Slower retry | Adapter stability > speed |
| **:delay (not :drop)** | No data loss | Memory for delayed queue | Worth it for reliability |
| **Exponential backoff + jitter** | Smooth recovery | Complex timing | Industry best practice |
| **Separate from main limit** | Fine-grained control | More config | Flexibility > simplicity |

---

## 💻 Rate Limiting Strategies

### Strategy 1: Drop

**Discard excess events:**
```ruby
on_exceeded :drop

# Use when:
# - Non-critical events (retry logs, debug events)
# - High volume, low value events
# - Already have enough signal

# Example:
per_event 'debug.log', limit: 100, window: 1.minute, on_exceeded: :drop
```

---

### Strategy 2: Sample

**Keep percentage of excess events:**
```ruby
on_exceeded :sample
sample_rate 0.1  # Keep 10%

# Use when:
# - Want SOME signal during flood
# - Statistical analysis OK (don't need every event)
# - Moderate volume

# Example:
per_event 'user.action', limit: 1000, window: 1.minute,
          on_exceeded: :sample
# → Sample rate: 0.1 (10%)
# → First 1000: all kept
# → Next 9000: 10% kept (900 events)
# → Total: 1900 events (vs 10,000 without rate limiting)
```

---

### Strategy 3: Backpressure

**Slow down event production:**
```ruby
on_exceeded :throttle

# Use when:
# - Events MUST be tracked (critical)
# - Can afford latency increase
# - Low to moderate volume

# How it works:
# 1. Limit exceeded
# 2. Sleep 10ms before tracking next event
# 3. Gradual slow down (not sudden drop)

# Example:
per_event 'order.created', limit: 100, window: 1.minute,
          on_exceeded: :throttle,
          backpressure_delay: 10.milliseconds
```

---

### Strategy 4: Aggregate

**Combine events into summary:**
```ruby
on_exceeded :aggregate

# Use when:
# - Many similar events
# - Summary is sufficient
# - High volume

# How it works:
# 1. First 100 events: tracked individually
# 2. Next 900 events: aggregated into 1 summary event
# 3. Summary includes: count, min/max/avg, sample

# Example:
per_event 'api.slow_request', limit: 100, window: 1.minute,
          on_exceeded: :aggregate,
          aggregate_fields: [:duration_ms, :endpoint]
# → First 100: individual events
# → Next 900: Summary event:
#   {
#     event_name: 'api.slow_request.aggregated',
#     count: 900,
#     duration_ms_min: 501,
#     duration_ms_max: 5000,
#     duration_ms_avg: 1200,
#     endpoints: ['/api/users', '/api/orders']
#   }
```

---

## 🚫 Bypass Rules (Allowlists)

**Always allow critical events:**

```ruby
E11y.configure do |config|
  config.rate_limiting do
    # Global rate limiting
    global limit: 10_000, window: 1.minute
    
    # === BYPASS RULES ===
    
    # Bypass by event type
    bypass_for event_types: [
      'system.critical',      # System-critical events
      'security.alert',       # Security alerts
      'payment.fraud',        # Fraud detection
      'data.corruption'       # Data integrity issues
    ]
    
    # Bypass by severity
    bypass_for severities: [:fatal, :error]
    
    # Bypass by context
    bypass_for contexts: {
      env: 'production',           # Only production
      user_role: 'admin'            # Admin users
    }
    
    # Bypass for specific users (VIPs)
    bypass_for_users ['vip_user_1', 'vip_user_2']
    
    # Custom bypass logic
    bypass_if ->(event) {
      # Always track events with high order amounts
      event.payload[:amount].to_i > 10_000
    }
  end
end

# Result:
# - Normal events: rate limited
# - Critical events: ALWAYS tracked (bypass)
```

---

## 📊 Implementation with Redis

**Production-ready implementation using Redis:**

```ruby
# lib/e11y/processing/rate_limiter.rb
module E11y
  module Processing
    class RateLimiter
      def initialize(redis: Redis.new)
        @redis = redis
        @config = E11y.config.rate_limiting
      end
      
      def allowed?(event)
        # Check bypass rules first
        return true if bypassed?(event)
        
        # Check global limit
        return false unless check_global_limit(event)
        
        # Check per-event limit
        return false unless check_per_event_limit(event)
        
        # Check per-context limits
        return false unless check_per_context_limits(event)
        
        true
      end
      
      private
      
      def check_global_limit(event)
        key = 'e11y:rate_limit:global'
        limit = @config.global_limit
        window = @config.global_window
        
        check_limit(key, limit, window)
      end
      
      def check_per_event_limit(event)
        limit_config = @config.per_event_limits[event.event_name]
        return true unless limit_config
        
        key = "e11y:rate_limit:event:#{event.event_name}"
        check_limit(key, limit_config[:limit], limit_config[:window])
      end
      
      def check_per_context_limits(event)
        @config.per_context_limits.all? do |field, limit_config|
          value = extract_context_value(event, field, limit_config[:extractor])
          next true unless value
          
          key = "e11y:rate_limit:context:#{field}:#{value}"
          check_limit(key, limit_config[:limit], limit_config[:window])
        end
      end
      
      def check_limit(key, limit, window)
        # Sliding window counter using Redis sorted sets
        now = Time.now.to_f
        window_start = now - window
        
        # Remove old entries (outside window)
        @redis.zremrangebyscore(key, 0, window_start)
        
        # Count current entries
        current_count = @redis.zcard(key)
        
        if current_count < limit
          # Add new entry
          @redis.zadd(key, now, "#{now}-#{SecureRandom.hex(8)}")
          @redis.expire(key, window.to_i + 60)  # TTL = window + buffer
          true
        else
          # Limit exceeded
          handle_exceeded(key, current_count, limit)
          false
        end
      end
      
      def handle_exceeded(key, current, limit)
        # Track metric
        Yabeda.e11y_internal.rate_limit_hits_total.increment(
          limit_type: extract_limit_type(key),
          key: key
        )
        
        # Log warning
        E11y.logger.warn(
          "[E11y] Rate limit exceeded: #{key} (#{current}/#{limit})"
        )
        
        # Alert if configured
        if @config.alert_on_limit
          alert_rate_limit_exceeded(key, current, limit)
        end
      end
      
      def bypassed?(event)
        # Check bypass rules
        @config.bypass_rules.any? do |rule|
          case rule[:type]
          when :event_types
            rule[:values].include?(event.event_name)
          when :severities
            rule[:values].include?(event.severity)
          when :contexts
            rule[:values].all? { |k, v| event.context[k] == v }
          when :custom
            rule[:condition].call(event)
          end
        end
      end
    end
  end
end
```

---

## 🔧 Implementation Details

> **Implementation:** See [ADR-006 Section 4.0: Rate Limiting + Retry Policy Resolution](../ADR-006-security-compliance.md#40-rate-limiting--retry-policy-resolution-conflict-14) for detailed architecture.

### Middleware Flow

E11y rate limiting is implemented as **middleware** in the event processing pipeline. Understanding the flow helps debug rate limiting behavior and optimize performance.

**Pipeline Order:**
```
Event.track() 
  → Schema Validation
  → Context Enrichment
  → Rate Limiting Middleware ← YOU ARE HERE
  → Adaptive Sampling
  → PII Filtering
  → Audit Signing
  → Adapter Routing
  → Write to Adapters
```

**Why Rate Limiting Before PII Filtering?**
- ✅ **Efficiency:** Drop events early (no wasted CPU on PII filtering)
- ✅ **Security:** Rate limiter sees original event (can detect patterns)
- ✅ **Accuracy:** Count real events (not filtered versions)

---

### Middleware Implementation

```ruby
# lib/e11y/middleware/rate_limiter.rb
module E11y
  module Middleware
    class RateLimiter < Base
      def call(event_data)
        # 1. Check bypass rules first (critical events)
        if bypassed?(event_data)
          return super(event_data)  # Pass to next middleware
        end
        
        # 2. Check global limit
        unless check_global_limit(event_data)
          handle_rate_limited(event_data, :global)
          return false  # Stop pipeline
        end
        
        # 3. Check per-event limit
        unless check_per_event_limit(event_data)
          handle_rate_limited(event_data, :per_event)
          return false
        end
        
        # 4. Check per-context limits
        unless check_per_context_limits(event_data)
          handle_rate_limited(event_data, :per_context)
          return false
        end
        
        # 5. All checks passed → continue pipeline
        super(event_data)
      end
      
      private
      
      def handle_rate_limited(event_data, limit_type)
        # Apply configured strategy
        case config.on_exceeded
        when :drop
          drop_event(event_data, limit_type)
        when :sample
          sample_event(event_data, limit_type)
        when :throttle
          apply_backpressure(event_data, limit_type)
        when :aggregate
          aggregate_event(event_data, limit_type)
        end
        
        # Track metric
        Yabeda.e11y_internal.rate_limit_hits_total.increment(
          limit_type: limit_type,
          event_name: event_data[:event_name]
        )
        
        # Log warning
        E11y.logger.warn(
          "[E11y RateLimit] Event rate limited: #{event_data[:event_name]} (#{limit_type})"
        )
      end
      
      def drop_event(event_data, limit_type)
        Yabeda.e11y_internal.rate_limit_dropped_events_total.increment(
          limit_type: limit_type
        )
      end
      
      def sample_event(event_data, limit_type)
        # Random sampling
        if rand < config.sample_rate
          super(event_data)  # Keep this one
        else
          drop_event(event_data, limit_type)
        end
      end
      
      def apply_backpressure(event_data, limit_type)
        # Slow down production
        sleep(config.backpressure_delay)
        super(event_data)
      end
      
      def aggregate_event(event_data, limit_type)
        # Add to aggregation buffer
        aggregation_buffer.add(event_data)
        
        # Flush aggregated event periodically
        if aggregation_buffer.should_flush?
          flush_aggregated_events(limit_type)
        end
      end
    end
  end
end
```

---

### Redis-Based Rate Limiting

E11y uses **Redis sorted sets** for distributed rate limiting across multiple application instances.

**Algorithm: Sliding Window Counter**

```ruby
def check_limit(key, limit, window)
  now = Time.now.to_f
  window_start = now - window
  
  # 1. Remove expired entries (outside window)
  redis.zremrangebyscore(key, 0, window_start)
  
  # 2. Count current entries
  current_count = redis.zcard(key)
  
  # 3. Check limit
  if current_count < limit
    # Add new entry (score = timestamp, member = unique ID)
    redis.zadd(key, now, "#{now}-#{SecureRandom.hex(8)}")
    redis.expire(key, window.to_i + 60)  # TTL cleanup
    true  # Allowed
  else
    false  # Rate limited
  end
end
```

**Why Sorted Sets?**
- ✅ **Sliding window:** Accurate counting (no edge cases like fixed window)
- ✅ **Distributed:** Works across multiple app instances
- ✅ **Efficient:** O(log N) for add/remove operations
- ✅ **Automatic cleanup:** Redis TTL handles old entries

**Redis Keys:**
```ruby
# Global limit
"e11y:rate_limit:global"

# Per-event limit
"e11y:rate_limit:event:payment.retry"

# Per-context limit
"e11y:rate_limit:context:user_id:user-123"
"e11y:rate_limit:context:ip_address:192.168.1.100"
```

---

### Retry Policy Integration

**Critical Decision:** Retries DO count toward rate limits (prevent retry amplification).

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  # Rate limiting
  config.rate_limiting do
    per_event 'payment.retry', limit: 100, window: 1.minute
  end
  
  # Retry policy
  config.error_handling do
    retry_policy do
      # ✅ Retries respect rate limits
      respect_rate_limits true
      
      # If retry is rate limited → send to DLQ
      on_retry_rate_limited :send_to_dlq
    end
  end
end
```

**Flow with Retries:**
```
1. Event.track() → Rate limited
2. Retry logic triggered
3. Retry attempt → Check rate limit AGAIN
4. If still rate limited → Send to DLQ (not dropped)
5. DLQ processed later (outside rate limit window)
```

**Why This Matters:**
- ✅ **Prevents retry amplification:** 1 failure → 1000 retries → 1000 rate limit hits
- ✅ **DLQ safety net:** Rate-limited retries not lost (processed later)
- ✅ **Observability preserved:** Can see retry patterns in metrics

---

### Performance Characteristics

**Latency:**
```ruby
# Benchmark: Rate limiter overhead
Benchmark.ips do |x|
  x.report('No rate limiting') do
    Events::TestEvent.track(foo: 'bar')  # Baseline
  end
  
  x.report('With rate limiting') do
    # Rate limiter enabled
    Events::TestEvent.track(foo: 'bar')
  end
  
  x.compare!
end

# Results:
# No rate limiting:    100,000 i/s (10μs per event)
# With rate limiting:   95,000 i/s (10.5μs per event)
# Overhead: ~0.5μs (5% increase)
```

**Redis Latency:**
```ruby
# Redis operations per event (within limit):
# 1. ZREMRANGEBYSCORE (cleanup)  ~0.1ms
# 2. ZCARD (count)               ~0.05ms
# 3. ZADD (add entry)            ~0.05ms
# 4. EXPIRE (set TTL)            ~0.05ms
# Total: ~0.25ms per event

# When rate limited:
# 1. ZREMRANGEBYSCORE            ~0.1ms
# 2. ZCARD                       ~0.05ms
# Total: ~0.15ms (no write)
```

**Scaling:**
```ruby
# Redis memory usage:
# - Global limit (10k events/min): ~500KB
# - Per-event limit (100/min): ~5KB per event type
# - Per-context limit (1k/min): ~50KB per user
# 
# Example: 1000 users × 50KB = 50MB
# → Acceptable for most deployments
```

---

### Troubleshooting

**Problem: Events dropped unexpectedly**

```ruby
# Check rate limit metrics
rate_limit_hits = Yabeda.e11y_internal.rate_limit_hits_total.values
# => { limit_type: 'per_event', event_name: 'payment.retry' } => 42

# Check Redis keys
redis.keys('e11y:rate_limit:*')
# => ["e11y:rate_limit:event:payment.retry"]

redis.zcard('e11y:rate_limit:event:payment.retry')
# => 100 (at limit!)

# Check TTL
redis.ttl('e11y:rate_limit:event:payment.retry')
# => 45 (45 seconds until window resets)
```

**Problem: Rate limiter not working**

```ruby
# 1. Check middleware order
E11y.config.middleware.list
# => [SchemaValidator, ContextEnricher, RateLimiter, ...]

# 2. Check rate limiting enabled
E11y.config.rate_limiting.enabled?
# => true

# 3. Check bypass rules
E11y.config.rate_limiting.bypass_rules
# => [{ type: :severities, values: [:fatal] }]

# 4. Check event matches bypass
event = { severity: :fatal }
E11y::Middleware::RateLimiter.new.bypassed?(event)
# => true (bypassed!)
```

**Problem: High Redis latency**

```ruby
# 1. Check Redis connection pool
E11y.config.redis.pool_size
# => 5 (default)

# Increase if needed
E11y.configure do |config|
  config.redis do
    pool_size 20  # For high-concurrency
  end
end

# 2. Use Redis pipelining for multiple checks
redis.pipelined do
  redis.zremrangebyscore(key, 0, window_start)
  redis.zcard(key)
  redis.zadd(key, now, id)
end

# 3. Consider local caching (for read-heavy workloads)
E11y.configure do |config|
  config.rate_limiting do
    cache_limit_checks true  # Cache for 1s
  end
end
```

---

## 📊 Self-Monitoring & Metrics

> **Implementation:** See [ADR-006 Section 4: Rate Limiting](../ADR-006-security-compliance.md#4-rate-limiting) for detailed architecture.

E11y provides comprehensive self-monitoring metrics for rate limiting. These metrics help you understand rate limit behavior, detect attacks, and optimize limits.

### Core Metrics

**1. `e11y_rate_limit_hits_total` (Counter)**
- **Description:** Total number of times a rate limit was hit (event attempted but limit reached).
- **Labels:**
  - `limit_type`: Type of limit (`global`, `per_event`, `per_context`)
  - `event_name`: Event type that hit the limit
  - `key`: Specific limit key (e.g., `user_id:123`, `ip:192.168.1.1`)
  - `strategy`: How event was handled (`drop`, `sample`, `backpressure`, `aggregate`)
- **Monitoring:**
  ```prometheus
  # Rate limit hit rate (events/sec)
  rate(e11y_rate_limit_hits_total[5m])
  
  # Which events hit limits most often?
  topk(10, sum by (event_name) (rate(e11y_rate_limit_hits_total[5m])))
  
  # Per-context abuse detection
  topk(10, sum by (key) (e11y_rate_limit_hits_total{limit_type="per_context"}))
  ```
- **Grafana Panel:**
  - **Title:** Rate Limit Hits by Type
  - **Query:** `sum by (limit_type) (rate(e11y_rate_limit_hits_total[5m]))`
  - **Visualization:** Time series graph
  - **Description:** Shows which rate limit type (global/per-event/per-context) is hit most frequently.

**2. `e11y_rate_limit_dropped_events_total` (Counter)**
- **Description:** Total number of events dropped due to rate limiting.
- **Labels:**
  - `limit_type`: Type of limit that caused drop
  - `event_name`: Event type that was dropped
- **Monitoring:**
  ```prometheus
  # Drop rate (events/sec)
  rate(e11y_rate_limit_dropped_events_total[5m])
  
  # Total dropped in last hour
  sum(increase(e11y_rate_limit_dropped_events_total[1h]))
  
  # Drop ratio (% of total events)
  rate(e11y_rate_limit_dropped_events_total[5m]) 
  / rate(e11y_events_tracked_total[5m])
  ```
- **Grafana Panel:**
  - **Title:** Event Drop Rate
  - **Query:** `rate(e11y_rate_limit_dropped_events_total[5m])`
  - **Visualization:** Time series graph with threshold line
  - **Alert Threshold:** > 100 drops/sec (high drop rate)

**3. `e11y_rate_limit_sampled_events_total` (Counter)**
- **Description:** Total number of events sampled (kept) when limit exceeded with `sample` strategy.
- **Labels:**
  - `limit_type`, `event_name`, `sample_rate`
- **Monitoring:**
  ```prometheus
  # Sampling effectiveness
  e11y_rate_limit_sampled_events_total / e11y_rate_limit_hits_total
  
  # Events saved by sampling (vs full drop)
  increase(e11y_rate_limit_sampled_events_total[1h])
  ```
- **Grafana Panel:**
  - **Title:** Sampled vs Dropped Events
  - **Query:** 
    ```prometheus
    sum(rate(e11y_rate_limit_sampled_events_total[5m])) /
    sum(rate(e11y_rate_limit_hits_total[5m]))
    ```
  - **Description:** Shows percentage of events retained during rate limiting (sampling effectiveness).

**4. `e11y_rate_limit_current` (Gauge)**
- **Description:** Current number of events in the rate limit window.
- **Labels:**
  - `limit_type`, `key`
- **Monitoring:**
  ```prometheus
  # Current utilization (% of limit)
  e11y_rate_limit_current / e11y_rate_limit_threshold
  
  # Max utilization in last hour
  max_over_time(e11y_rate_limit_current[1h])
  ```
- **Grafana Panel:**
  - **Title:** Rate Limit Utilization
  - **Query:** 
    ```prometheus
    (e11y_rate_limit_current / e11y_rate_limit_threshold) * 100
    ```
  - **Visualization:** Gauge (0-100%)
  - **Thresholds:** 
    - Green: 0-70%
    - Yellow: 70-90%
    - Red: 90-100%

**5. `e11y_rate_limit_threshold` (Gauge)**
- **Description:** Configured rate limit threshold.
- **Labels:**
  - `limit_type`, `key`
- **Monitoring:**
  ```prometheus
  # View configured limits
  e11y_rate_limit_threshold
  
  # Check if limits need adjustment
  e11y_rate_limit_current / e11y_rate_limit_threshold > 0.8
  ```

**6. `e11y_rate_limit_bypass_total` (Counter)**
- **Description:** Total number of events that bypassed rate limiting (critical events).
- **Labels:**
  - `event_name`, `bypass_reason` (`severity`, `event_type`, `custom`)
- **Monitoring:**
  ```prometheus
  # Bypass rate
  rate(e11y_rate_limit_bypass_total[5m])
  
  # Which events bypass most?
  topk(10, sum by (event_name) (e11y_rate_limit_bypass_total))
  ```

---

### Monitoring Dashboard

**Grafana Dashboard: E11y Rate Limiting**

```yaml
# dashboard.json structure
{
  "title": "E11y Rate Limiting",
  "panels": [
    {
      "title": "Rate Limit Hits (by type)",
      "query": "sum by (limit_type) (rate(e11y_rate_limit_hits_total[5m]))",
      "type": "graph"
    },
    {
      "title": "Drop Rate",
      "query": "rate(e11y_rate_limit_dropped_events_total[5m])",
      "type": "graph",
      "alert": {
        "threshold": 100,
        "severity": "warning"
      }
    },
    {
      "title": "Top Rate-Limited Events",
      "query": "topk(10, sum by (event_name) (e11y_rate_limit_hits_total))",
      "type": "table"
    },
    {
      "title": "Global Limit Utilization",
      "query": "(e11y_rate_limit_current{limit_type='global'} / e11y_rate_limit_threshold{limit_type='global'}) * 100",
      "type": "gauge",
      "thresholds": [70, 90]
    },
    {
      "title": "Per-Context Abuse Detection",
      "query": "topk(10, sum by (key) (e11y_rate_limit_hits_total{limit_type='per_context'}))",
      "type": "table"
    }
  ]
}
```

---

### Alerting Thresholds

| Metric | Threshold | Severity | Rationale |
|--------|-----------|----------|-----------|
| **Rate limit hits** | > 10/sec | Warning | Frequent rate limiting indicates high load or attack |
| **Drop rate** | > 100/sec | Critical | High drop rate means observability loss |
| **Global utilization** | > 80% | Warning | Approaching global limit, may need increase |
| **Global utilization** | > 95% | Critical | Nearly at limit, immediate action needed |
| **Per-event hits** | > 50/min | Warning | Specific event flooding (retry storm, bug) |
| **Per-context hits** | > 100/min | Warning | Single user/IP abusing system |

---

### Prometheus Alerts

```yaml
# config/prometheus/alerts.yml
groups:
  - name: e11y_rate_limiting
    rules:
      # Alert on frequent rate limiting
      - alert: E11yRateLimitHit
        expr: rate(e11y_rate_limit_hits_total[5m]) > 10
        for: 2m
        annotations:
          summary: "Rate limit hit frequently ({{ $value }} hits/sec)"
          description: "Check for retry storms or attacks"
      
      # Alert on high drop rate
      - alert: E11yHighDropRate
        expr: rate(e11y_rate_limit_dropped_events_total[5m]) > 100
        for: 1m
        annotations:
          summary: "High event drop rate ({{ $value }} events/sec)"
          description: "Increase limits or investigate flood source"
      
      # Alert on global limit approached
      - alert: E11yGlobalLimitApproached
        expr: |
          e11y_rate_limit_current{limit_type="global"} 
          / e11y_rate_limit_threshold{limit_type="global"} > 0.8
        for: 1m
        annotations:
          summary: "Global rate limit at {{ $value }}%"
```

---

## 💻 Usage Examples

### Example 1: Retry Storm Protection

```ruby
# app/services/payment_processor.rb
class PaymentProcessor
  MAX_RETRIES = 3
  
  def process(order)
    Events::PaymentAttempt.track(order_id: order.id)
    
    begin
      result = PaymentGateway.charge(order)
      Events::PaymentSuccess.track(order_id: order.id, severity: :success)
      result
    rescue PaymentGateway::TemporaryError => e
      retry_with_rate_limit(order, e)
    end
  end
  
  private
  
  def retry_with_rate_limit(order, error)
    MAX_RETRIES.times do |attempt|
      # Track retry (rate limited!)
      Events::PaymentRetry.track(
        order_id: order.id,
        attempt: attempt + 1,
        error: error.message
      )
      
      sleep(2 ** attempt)  # Exponential backoff
      
      begin
        return PaymentGateway.charge(order)
      rescue => e
        error = e
      end
    end
    
    # All retries failed
    Events::PaymentFailed.track(
      order_id: order.id,
      error: error.message,
      severity: :error
    )
    
    raise error
  end
end

# Rate limiting config:
E11y.configure do |config|
  config.rate_limiting do
    # Limit retries to 100/min globally
    per_event 'payment.retry',
              limit: 100,
              window: 1.minute,
              on_exceeded: :sample,
              sample_rate: 0.1
  end
end

# Result:
# - Normal operation: All retries tracked
# - Gateway outage: 100 retries/min tracked + 10% sampled
# - Observability maintained during incident ✅
```

---

### Example 2: Login Failure Protection

```ruby
# app/controllers/sessions_controller.rb
class SessionsController < ApplicationController
  def create
    user = User.find_by(email: params[:email])
    
    if user&.authenticate(params[:password])
      # Success
      Events::UserLoggedIn.track(
        user_id: user.id,
        ip_address: request.remote_ip,
        severity: :success
      )
      
      session[:user_id] = user.id
      redirect_to root_path
    else
      # Failure (rate limited per IP)
      Events::LoginFailed.track(
        email: params[:email],  # Filtered by PII filter
        ip_address: request.remote_ip,
        reason: 'invalid_credentials',
        severity: :warn
      )
      
      flash[:error] = 'Invalid credentials'
      render :new
    end
  end
end

# Rate limiting config:
E11y.configure do |config|
  config.rate_limiting do
    # Limit login failures per IP
    per_context :ip_address,
                limit: 50,
                window: 5.minutes,
                on_exceeded: :drop
    
    # Also limit per event
    per_event 'login.failed',
              limit: 200,
              window: 1.minute,
              on_exceeded: :sample,
              sample_rate: 0.2
  end
end

# Result:
# - Brute force attack: Max 50 events/IP/5min
# - Global flood: Max 200 events/min
# - Observability maintained, attacker data not logged ✅
```

---

## 🧪 Testing

```ruby
# spec/e11y/rate_limiting_spec.rb
RSpec.describe 'E11y Rate Limiting' do
  before do
    E11y.configure do |config|
      config.rate_limiting do
        global limit: 100, window: 1.minute
        per_event 'test.event', limit: 10, window: 1.minute
      end
    end
  end
  
  describe 'global rate limiting' do
    it 'allows events under limit' do
      50.times do
        result = Events::TestEvent.track(foo: 'bar')
        expect(result).to be_success
      end
    end
    
    it 'rate limits after threshold' do
      # Track 100 events (at limit)
      100.times { Events::TestEvent.track(foo: 'bar') }
      
      # 101st event should be rate limited
      result = Events::TestEvent.track(foo: 'bar')
      expect(result).to be_rate_limited
      
      # Metric incremented
      metric = Yabeda.e11y_internal.rate_limit_hits_total
      expect(metric.values[{ limit_type: 'global' }]).to be > 0
    end
  end
  
  describe 'per-event rate limiting' do
    it 'rate limits specific event type' do
      # Track 10 test.event (at limit)
      10.times { Events::TestEvent.track(foo: 'bar') }
      
      # 11th should be rate limited
      result = Events::TestEvent.track(foo: 'bar')
      expect(result).to be_rate_limited
      
      # But other events still work
      result = Events::OtherEvent.track(baz: 'qux')
      expect(result).to be_success
    end
  end
  
  describe 'bypass rules' do
    before do
      E11y.configure do |config|
        config.rate_limiting do
          global limit: 10, window: 1.minute
          bypass_for severities: [:fatal]
        end
      end
    end
    
    it 'bypasses rate limiting for critical events' do
      # Fill up limit
      10.times { Events::TestEvent.track(severity: :info) }
      
      # Fatal event should bypass
      result = Events::CriticalError.track(severity: :fatal)
      expect(result).to be_success  # Not rate limited!
    end
  end
end
```

---

## 💡 Best Practices

### ✅ DO

**1. Set conservative limits initially**
```ruby
# ✅ GOOD: Start low, increase if needed
global limit: 5_000, window: 1.minute
```

**2. Use per-context limits for abuse prevention**
```ruby
# ✅ GOOD: Prevent single user flooding
per_context :user_id, limit: 1_000, window: 1.minute
per_context :ip_address, limit: 500, window: 1.minute
```

**3. Always bypass critical events**
```ruby
# ✅ GOOD: Never rate limit security/system events
bypass_for event_types: ['security.alert', 'system.critical']
bypass_for severities: [:fatal]
```

**4. Monitor rate limit hits**
```ruby
# ✅ GOOD: Alert on frequent rate limiting
# Alert: rate_limit_hits_total > 10/min
```

---

### ❌ DON'T

**1. Don't set limits too high (defeats purpose)**
```ruby
# ❌ BAD: Limit too high to be effective
global limit: 1_000_000, window: 1.minute  # Useless!
```

**2. Don't rate limit critical events**
```ruby
# ❌ BAD: Rate limiting errors
per_event 'system.error', limit: 10  # You WANT to know about ALL errors!
```

**3. Don't ignore rate limit alerts**
```ruby
# ❌ BAD: Rate limits hitting frequently
# → Investigate! Could be attack or misconfiguration
```

---

## 🔒 Validations (NEW - v1.1)

> **🎯 Pattern:** Validate rate limiting configuration at class load time.

### Rate Limit Value Validation

**Problem:** Invalid rate limit values → runtime errors.

**Solution:** Validate rate limit is positive integer:

```ruby
# Gem implementation (automatic):
def self.rate_limit(limit, window: 1.minute)
  unless limit.is_a?(Integer) && limit > 0
    raise ArgumentError, "rate_limit must be positive integer, got: #{limit.inspect}"
  end
  unless window.is_a?(ActiveSupport::Duration) && window > 0
    raise ArgumentError, "window must be positive duration, got: #{window.inspect}"
  end
  self._rate_limit = limit
  self._rate_limit_window = window
end

# Result:
class Events::ApiRequest < E11y::Event::Base
  rate_limit -100  # ← ERROR: "rate_limit must be positive integer, got: -100"
end
```

### On Exceeded Strategy Validation

**Problem:** Invalid on_exceeded strategies → silent failures.

**Solution:** Validate strategy against whitelist:

```ruby
# Gem implementation (automatic):
VALID_ON_EXCEEDED = [:drop, :sample, :throttle]

def self.on_exceeded(strategy)
  unless VALID_ON_EXCEEDED.include?(strategy)
    raise ArgumentError, "Invalid on_exceeded: #{strategy}. Valid: #{VALID_ON_EXCEEDED.join(', ')}"
  end
  self._on_exceeded = strategy
end

# Result:
class Events::ApiRequest < E11y::Event::Base
  on_exceeded :backpressure  # ← ERROR: "Invalid on_exceeded: :backpressure. Valid: drop, sample, throttle"
end
```

### Audit Event Rate Limiting Validation (LOCKED)

**Problem:** Attempting to rate limit audit events → compliance violations.

**Solution:** Lock rate_limiting for audit events:

```ruby
# Gem implementation (automatic):
def self.rate_limiting(enabled)
  if self._audit_event && enabled
    raise ArgumentError, "Cannot enable rate_limiting for audit events! Audit events must never be rate limited."
  end
  self._rate_limiting = enabled
end

# Result:
class Events::UserDeleted < E11y::Event::Base
  audit_event true
  rate_limit 1000  # ← ERROR: "Cannot enable rate_limiting for audit events!"
end
```

---

## 🌍 Environment-Specific Rate Limiting (NEW - v1.1)

> **🎯 Pattern:** Different rate limits per environment.

### Example 1: Higher Limits in Production

```ruby
class Events::ApiRequest < E11y::Event::Base
  schema do
    required(:endpoint).filled(:string)
    required(:status).filled(:integer)
  end
  
  # Environment-specific rate limits
  rate_limit case Rails.env
             when 'production' then 10_000
             when 'staging' then 1_000
             else 100  # Dev/test
             end
  
  on_exceeded Rails.env.production? ? :sample : :drop
  sample_rate 0.1 if Rails.env.production?
end
```

### Example 2: Debug Events (Strict in Prod, Loose in Dev)

```ruby
class Events::DebugQuery < E11y::Event::Base
  schema do
    required(:query).filled(:string)
    required(:duration_ms).filled(:integer)
  end
  
  # Strict rate limiting in production
  rate_limit Rails.env.production? ? 100 : 10_000
  on_exceeded :drop  # Always drop debug logs
end
```

### Example 3: Feature Flag for Rate Limiting

```ruby
class Events::ExperimentalFeature < E11y::Event::Base
  schema do
    required(:feature_name).filled(:string)
  end
  
  # Enable rate limiting only when feature flag is on
  if ENV['ENABLE_RATE_LIMITING'] == 'true'
    rate_limit 1_000
    on_exceeded :sample
    sample_rate 0.1
  end
end
```

---

## 📊 Precedence Rules for Rate Limiting (NEW - v1.1)

> **🎯 Pattern:** Rate limiting configuration precedence (most specific wins).

### Precedence Order (Highest to Lowest)

```
1. Event-level explicit config (highest priority)
   ↓
2. Preset module config
   ↓
3. Base class config (inheritance)
   ↓
4. Convention-based defaults (1000/sec)
   ↓
5. Global config (lowest priority)
```

### Example: Mixing Inheritance + Presets for Rate Limiting

```ruby
# Global config (lowest priority)
E11y.configure do |config|
  config.rate_limiting do
    global limit: 10_000, window: 1.minute  # Default for all events
    on_exceeded :drop
  end
end

# Base class (medium priority)
class Events::BaseDebugEvent < E11y::Event::Base
  severity :debug
  rate_limit 100, window: 1.minute  # Override global (stricter)
  on_exceeded :drop
end

# Preset module (higher priority)
module E11y::Presets::HighValueEvent
  extend ActiveSupport::Concern
  included do
    rate_limit 10_000, window: 1.minute  # Override base (looser)
    on_exceeded :throttle  # Never drop high-value events
  end
end

# Event (highest priority)
class Events::CriticalPayment < Events::BaseDebugEvent
  include E11y::Presets::HighValueEvent
  
  rate_limit 50_000, window: 1.minute  # Override preset (even looser)
  
  # Final config:
  # - severity: :debug (from base)
  # - rate_limit: 50_000/min (event-level override)
  # - on_exceeded: :throttle (from preset)
end
```

### Precedence Rules Table

| Config | Global | Convention | Base Class | Preset | Event-Level | Winner |
|--------|--------|------------|------------|--------|-------------|--------|
| `rate_limit` | `10_000` | `1_000` | `100` | `10_000` | `50_000` | **`50_000`** (event) |
| `on_exceeded` | `:drop` | - | `:drop` | `:throttle` | - | **`:throttle`** (preset) |
| `sample_rate` | `0.1` | - | - | `0.5` | - | **`0.5`** (preset) |

### Convention-Based Defaults

**Convention:** If no rate_limit specified → default `1000/sec`:

```ruby
class Events::ApiRequest < E11y::Event::Base
  schema do
    required(:endpoint).filled(:string)
  end
  # ← Auto: rate_limit = 1000 (convention!)
end
```

---

## 📚 Related Use Cases

- **[UC-002: Business Event Tracking](./UC-002-business-event-tracking.md)** - Event definitions
- **[UC-007: PII Filtering](./UC-007-pii-filtering.md)** - Prevent PII leaks
- **[UC-013: High Cardinality Protection](./UC-013-high-cardinality-protection.md)** - Cost control

---

**Document Version:** 1.1 (Unified DSL)  
**Last Updated:** January 16, 2026  
**Status:** ✅ Complete - Consistent with DSL-SPECIFICATION.md v1.1.0

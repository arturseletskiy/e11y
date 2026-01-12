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
    on_exceeded :sample  # Options: :drop, :sample, :backpressure
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
              on_exceeded: :backpressure  # Slow down, don't drop
    
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
                on_exceeded: :backpressure
    
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
          on_exceeded: :sample, sample_rate: 0.1
# → First 1000: all kept
# → Next 9000: 10% kept (900 events)
# → Total: 1900 events (vs 10,000 without rate limiting)
```

---

### Strategy 3: Backpressure

**Slow down event production:**
```ruby
on_exceeded :backpressure

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
          on_exceeded: :backpressure,
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

## 📊 Monitoring

### Self-Monitoring Metrics

```ruby
# === RATE LIMIT METRICS ===
e11y_rate_limit_hits_total{limit_type,key}           # Times limit hit
e11y_rate_limit_dropped_events_total{limit_type}     # Events dropped
e11y_rate_limit_sampled_events_total{limit_type}     # Events sampled
e11y_rate_limit_current{limit_type,key}              # Current count
e11y_rate_limit_threshold{limit_type,key}            # Configured limit

# Prometheus queries:
# - Rate limit hit rate:
#   rate(e11y_rate_limit_hits_total[5m])
#
# - Which events are hitting limits?
#   topk(10, sum by (key) (e11y_rate_limit_hits_total))
#
# - How many events dropped?
#   sum(increase(e11y_rate_limit_dropped_events_total[1h]))
```

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

## 📚 Related Use Cases

- **[UC-002: Business Event Tracking](./UC-002-business-event-tracking.md)** - Event definitions
- **[UC-007: PII Filtering](./UC-007-pii-filtering.md)** - Prevent PII leaks
- **[UC-013: High Cardinality Protection](./UC-013-high-cardinality-protection.md)** - Cost control

---

**Document Version:** 1.0  
**Last Updated:** January 12, 2026  
**Status:** ✅ Complete

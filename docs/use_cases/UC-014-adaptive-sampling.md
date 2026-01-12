# UC-014: Adaptive Sampling

**Status:** v1.1 Enhancement  
**Complexity:** Advanced  
**Setup Time:** 45-60 minutes  
**Target Users:** SRE, DevOps, Engineering Managers

---

## 📋 Overview

### Problem Statement

**The resource waste problem:**
```ruby
# ❌ FIXED SAMPLING: Wastes resources, misses important events
E11y.configure do |config|
  config.sampling do
    # Fixed 10% sampling for ALL events
    sample_rate 0.1  # 90% dropped!
  end
end

# Problems during incidents:
# 09:00 AM: Normal load (1k events/sec)
# → 10% sampling = 100 events/sec tracked (OK)
#
# 09:30 AM: Error spike! (100k errors/sec)
# → 10% sampling = 10k events/sec tracked
# → But we need MORE samples during errors, not same rate!
#
# Result:
# - Wasted capacity during normal times (could track more)
# - Insufficient data during incidents (need more samples)
# - No signal/noise optimization
# - Fixed cost regardless of load
```

### E11y Solution

**Dynamic sampling adapts to conditions:**
```ruby
# ✅ ADAPTIVE SAMPLING: Smart resource allocation
E11y.configure do |config|
  config.adaptive_sampling do
    # Adjust sampling based on multiple factors
    enabled true
    
    # Base sampling rate (adjusted dynamically)
    base_sample_rate 0.1  # 10% default
    
    # Increase sampling during errors
    on_error_spike do
      sample_rate 1.0  # 100% during errors!
      duration 5.minutes
      error_rate_threshold 0.05  # 5% error rate triggers
    end
    
    # Decrease sampling during high load
    on_high_load do
      sample_rate 0.01  # 1% during overload
      load_threshold 50_000  # events/sec
    end
    
    # Never sample critical events
    always_sample severities: [:error, :fatal],
                  event_patterns: ['payment.*', 'security.*']
    
    # Sample by value (high-value events)
    sample_by_value do
      field :amount
      threshold 1000  # Always sample >$1000 transactions
    end
  end
end

# Result:
# Normal: 10% sampling (1k → 100 events/sec)
# Error spike: 100% sampling (100k errors → 100k tracked!)
# High load: 1% sampling (100k → 1k events/sec)
# Critical: Always 100% (never dropped)
```

---

## 🎯 Adaptive Sampling Strategies

### Strategy 1: Error-Based Sampling

**Increase sampling during error spikes:**
```ruby
E11y.configure do |config|
  config.adaptive_sampling do
    # Detect error rate increase
    error_spike_detection do
      enabled true
      
      # Calculate error rate over sliding window
      window 1.minute
      
      # Thresholds (absolute + relative)
      absolute_threshold 100  # >100 errors/min → spike
      relative_threshold 3.0  # 3x normal rate → spike
      
      # Action: increase sampling
      on_spike do
        sample_rate 1.0  # 100%
        duration 5.minutes
        exponential_decay true  # Gradually return to normal
      end
      
      # Track baseline error rate
      baseline_window 1.hour
      baseline_calculation :p95  # Use p95 as baseline
    end
  end
end

# How it works:
# 1. Track error rate: 10 errors/min (baseline)
# 2. Sudden spike: 150 errors/min (15x increase!)
# 3. Trigger: sample_rate → 1.0 (100%)
# 4. Duration: 5 minutes at 100%
# 5. Decay: Gradually return to 10% over next 10 minutes
```

---

### Strategy 2: Load-Based Sampling

**Adjust sampling based on event volume:**
```ruby
E11y.configure do |config|
  config.adaptive_sampling do
    load_based_sampling do
      enabled true
      
      # Define load tiers
      tiers [
        { threshold: 0,      sample_rate: 1.0 },   # <1k/sec: 100%
        { threshold: 1_000,  sample_rate: 0.5 },   # 1k-10k/sec: 50%
        { threshold: 10_000, sample_rate: 0.1 },   # 10k-50k/sec: 10%
        { threshold: 50_000, sample_rate: 0.01 }   # >50k/sec: 1%
      ]
      
      # Smooth transitions (avoid sudden jumps)
      transition_period 30.seconds
      
      # Hysteresis (prevent flapping)
      hysteresis 0.2  # 20% buffer before tier change
    end
  end
end

# Example timeline:
# 10:00: 500 events/sec   → 100% sampling
# 10:05: 5k events/sec    → 50% sampling (gradual transition)
# 10:10: 60k events/sec   → 1% sampling (overload!)
# 10:15: 8k events/sec    → 10% sampling (returning to normal)
# 10:20: 500 events/sec   → 100% sampling (normal)
```

---

### Strategy 3: Value-Based Sampling

**Always sample high-value events:**
```ruby
E11y.configure do |config|
  config.adaptive_sampling do
    value_based_sampling do
      enabled true
      
      # Sample by transaction amount
      sample_by field: :amount,
                 threshold: 1000,  # >$1000
                 sample_rate: 1.0  # Always track high-value
      
      # Sample by user segment
      sample_by field: :user_segment,
                 values: ['enterprise', 'vip'],
                 sample_rate: 1.0  # Always track VIP users
      
      # Sample by event importance
      sample_by field: :event_importance,
                 threshold: 8,  # Importance score >8
                 sample_rate: 1.0
      
      # Everything else: base sample rate
      default_sample_rate 0.1  # 10%
    end
  end
end

# Usage:
Events::OrderPaid.track(
  order_id: '123',
  amount: 5000,  # >$1000 → Always sampled!
  user_segment: 'enterprise'  # VIP → Always sampled!
)

Events::OrderPaid.track(
  order_id: '456',
  amount: 50,  # <$1000 → 10% chance
  user_segment: 'free'  # Regular → 10% chance
)
```

---

### Strategy 4: Content-Based Sampling

**Sample based on event content/patterns:**
```ruby
E11y.configure do |config|
  config.adaptive_sampling do
    content_based_sampling do
      enabled true
      
      # Always sample specific patterns
      always_sample patterns: [
        'payment.*',       # All payment events
        'security.*',      # All security events
        'user.deleted',    # GDPR events
        'admin.*'          # Admin actions
      ]
      
      # Never sample (drop entirely)
      never_sample patterns: [
        'debug.*',         # Debug events in production
        'heartbeat.*'      # Heartbeat noise
      ]
      
      # Smart sampling for repeated events
      deduplication do
        enabled true
        window 1.minute
        
        # If same event repeats >10 times/min → sample 10%
        threshold 10
        sample_rate 0.1
        
        # Dedupe by these fields
        dedupe_keys [:event_name, :user_id, :error_code]
      end
    end
  end
end

# Example:
# Event: user.login.failed (user_id: 123, error: invalid_password)
# 1st occurrence: Tracked (100%)
# 2nd occurrence: Tracked (100%)
# ...
# 10th occurrence: Tracked (100%)
# 11th occurrence: Tracked (10% chance - deduped!)
# 12th-100th: Tracked (10% chance)
```

---

### Strategy 5: Tail-Based Sampling

**Sample based on final outcome (requires buffering):**
```ruby
E11y.configure do |config|
  config.adaptive_sampling do
    tail_based_sampling do
      enabled true
      
      # Buffer events for request duration
      buffer_duration 30.seconds  # Max request time
      
      # Decision criteria (applied at request end)
      sample_if do |events_in_request|
        # Always sample if ANY error
        return true if events_in_request.any? { |e| e.severity == :error }
        
        # Always sample if slow (>1 second)
        request_duration = events_in_request.last.timestamp - events_in_request.first.timestamp
        return true if request_duration > 1.0
        
        # Always sample if high-value transaction
        return true if events_in_request.any? { |e| e.payload[:amount].to_i > 1000 }
        
        # Otherwise: probabilistic sampling
        rand < 0.1  # 10%
      end
    end
  end
end

# How it works:
# Request starts → Buffer all events
# Request ends → Evaluate criteria
# Decision: Keep all or drop all events for this request

# Example:
# Request A: 10 events, no errors, 200ms → 10% chance (all or nothing)
# Request B: 10 events, 1 error → 100% (keep all!)
# Request C: 10 events, 1500ms → 100% (keep all - slow!)
```

---

### Strategy 6: Machine Learning-Based Sampling

**Learn optimal sampling from historical data:**
```ruby
E11y.configure do |config|
  config.adaptive_sampling do
    ml_based_sampling do
      enabled true
      
      # Train model on historical data
      training_data window: 7.days,
                    features: [
                      :event_name,
                      :severity,
                      :error_rate,
                      :request_duration,
                      :time_of_day,
                      :day_of_week,
                      :load_level
                    ]
      
      # Model predicts event "importance"
      importance_threshold 0.7  # >0.7 → always sample
      
      # Update model periodically
      retrain_interval 1.day
      
      # Fallback if model fails
      fallback_sample_rate 0.1
    end
  end
end

# Model learns patterns like:
# - Errors during peak hours → High importance
# - Slow requests on weekends → High importance
# - Normal events at 3 AM → Low importance
```

---

## 💻 Implementation Examples

### Example 1: Production Incident Response

```ruby
# Scenario: Payment gateway outage
# Normal: 1k events/sec, 1% errors
# Incident: 50k events/sec, 80% errors

E11y.configure do |config|
  config.adaptive_sampling do
    # Detect error spike
    error_spike_detection do
      enabled true
      window 1.minute
      absolute_threshold 100
      relative_threshold 3.0
      
      on_spike do
        sample_rate 1.0  # 100% during errors
        duration 10.minutes
      end
    end
    
    # But also protect from overload
    load_based_sampling do
      tiers [
        { threshold: 0,      sample_rate: 1.0 },
        { threshold: 10_000, sample_rate: 0.5 },
        { threshold: 50_000, sample_rate: 0.1 }
      ]
    end
    
    # Priority: Always sample payment errors
    always_sample event_patterns: ['payment.*'],
                  severities: [:error, :fatal]
  end
end

# Timeline during incident:
# 10:00: Normal (1k/sec, 1% errors)
#   → Base sampling: 10%
#   → Errors: 100% (always_sample)
#
# 10:05: Incident starts (10k/sec, 40% errors)
#   → Error spike detected!
#   → All events: 100% (spike mode)
#
# 10:10: Incident peak (50k/sec, 80% errors)
#   → Load protection kicks in
#   → Non-payment events: 10% (load tier)
#   → Payment errors: 100% (always_sample)
#
# 10:20: Incident resolving (5k/sec, 10% errors)
#   → Gradual return to normal
#   → Sample rate: 50% → 30% → 10%
#
# 10:30: Normal (1k/sec, 1% errors)
#   → Back to base sampling: 10%
```

---

### Example 2: Black Friday Traffic

```ruby
# Scenario: Black Friday sale
# Normal: 2k events/sec
# Black Friday: 100k events/sec (50x increase!)

E11y.configure do |config|
  config.adaptive_sampling do
    # Load-based scaling
    load_based_sampling do
      tiers [
        { threshold: 0,       sample_rate: 1.0 },   # Normal
        { threshold: 10_000,  sample_rate: 0.5 },   # Busy
        { threshold: 50_000,  sample_rate: 0.1 },   # Very busy
        { threshold: 100_000, sample_rate: 0.01 }   # Black Friday!
      ]
    end
    
    # But always sample high-value orders
    value_based_sampling do
      sample_by field: :amount,
                 threshold: 500,
                 sample_rate: 1.0  # Always track >$500 orders
    end
    
    # And always sample errors
    always_sample severities: [:error, :fatal]
  end
end

# Result during Black Friday:
# 100k events/sec total
# → Regular events: 1% (1k events/sec tracked)
# → High-value orders (5k/sec): 100% (5k tracked)
# → Errors (500/sec): 100% (500 tracked)
# Total tracked: 6.5k events/sec (6.5% effective rate)
# → vs 10k with fixed 10% sampling (saves 35%!)
```

---

### Example 3: Debug Session

```ruby
# Scenario: Engineer debugging production issue for specific user

# Temporarily increase sampling for specific user
E11y.with_sampling_override(
  user_id: 'debug_user_123',
  sample_rate: 1.0,  # 100% for this user
  duration: 1.hour
) do
  # All events for this user tracked at 100% for 1 hour
  # Other users: normal sampling rates
end

# OR: Programmatically via API
E11y.configure do |config|
  config.adaptive_sampling do
    # Whitelist specific users for full sampling
    whitelist_sampling do
      users ['debug_user_123', 'vip_user_456']
      sample_rate 1.0
      expires_at 1.hour.from_now
    end
  end
end

# OR: Dynamic via Redis (supports multiple app servers)
E11y::Sampling.set_override(
  context: { user_id: 'debug_user_123' },
  sample_rate: 1.0,
  ttl: 1.hour
)
```

---

## 📊 Monitoring Adaptive Sampling

**Track sampling effectiveness:**
```ruby
# Self-monitoring metrics
E11y.configure do |config|
  config.self_monitoring do
    # Current sample rate (per strategy)
    gauge :adaptive_sampling_current_rate,
          tags: [:strategy]
    
    # Events sampled vs dropped
    counter :adaptive_sampling_events_sampled_total,
            tags: [:strategy, :reason]
    counter :adaptive_sampling_events_dropped_total,
            tags: [:strategy, :reason]
    
    # Load metrics
    gauge :adaptive_sampling_current_load_events_per_sec
    gauge :adaptive_sampling_error_rate
    
    # Strategy transitions
    counter :adaptive_sampling_strategy_transitions_total,
            tags: [:from_strategy, :to_strategy, :reason]
    
    # Effectiveness
    histogram :adaptive_sampling_resource_savings_pct,
              buckets: [10, 25, 50, 75, 90]
  end
end

# Prometheus queries:
# - Current sampling rate:
#   adaptive_sampling_current_rate
#
# - How many events dropped by adaptive sampling?
#   sum(increase(adaptive_sampling_events_dropped_total[1h]))
#
# - Resource savings:
#   histogram_quantile(0.5, adaptive_sampling_resource_savings_pct_bucket)
```

---

## 🧪 Testing

```ruby
# spec/e11y/adaptive_sampling_spec.rb
RSpec.describe 'Adaptive Sampling' do
  describe 'error spike detection' do
    it 'increases sampling during error spikes' do
      E11y.configure do |config|
        config.adaptive_sampling do
          error_spike_detection do
            enabled true
            absolute_threshold 10
            on_spike do
              sample_rate 1.0
            end
          end
        end
      end
      
      # Normal: 10% sampling
      expect(E11y.current_sample_rate).to eq(0.1)
      
      # Simulate error spike (20 errors in 1 minute)
      20.times { Events::TestError.track(severity: :error) }
      
      # Should increase to 100%
      expect(E11y.current_sample_rate).to eq(1.0)
    end
  end
  
  describe 'load-based sampling' do
    it 'decreases sampling under high load' do
      E11y.configure do |config|
        config.adaptive_sampling do
          load_based_sampling do
            tiers [
              { threshold: 0,     sample_rate: 1.0 },
              { threshold: 1_000, sample_rate: 0.1 }
            ]
          end
        end
      end
      
      # Low load: 100% sampling
      expect(E11y.current_sample_rate).to eq(1.0)
      
      # Simulate high load (1500 events/sec)
      E11y::LoadMonitor.report_load(1500)
      
      # Should decrease to 10%
      expect(E11y.current_sample_rate).to eq(0.1)
    end
  end
  
  describe 'value-based sampling' do
    it 'always samples high-value events' do
      E11y.configure do |config|
        config.adaptive_sampling do
          base_sample_rate 0.1
          value_based_sampling do
            sample_by field: :amount, threshold: 1000, sample_rate: 1.0
          end
        end
      end
      
      # High-value: always sampled
      100.times do
        result = Events::OrderPaid.track(amount: 5000)
        expect(result).to be_sampled
      end
      
      # Low-value: 10% chance
      results = 1000.times.map { Events::OrderPaid.track(amount: 50) }
      sampled_count = results.count(&:sampled?)
      expect(sampled_count).to be_within(50).of(100)  # ~10%
    end
  end
end
```

---

## 💡 Best Practices

### ✅ DO

**1. Always sample critical events**
```ruby
# ✅ GOOD
always_sample severities: [:error, :fatal],
              event_patterns: ['payment.*', 'security.*']
```

**2. Use multiple strategies together**
```ruby
# ✅ GOOD: Layered approach
config.adaptive_sampling do
  error_spike_detection { ... }  # Layer 1
  load_based_sampling { ... }    # Layer 2
  value_based_sampling { ... }   # Layer 3
end
```

**3. Monitor sampling effectiveness**
```ruby
# ✅ GOOD: Track metrics
# - adaptive_sampling_resource_savings_pct
# - adaptive_sampling_events_dropped_total
```

**4. Test in staging first**
```ruby
# ✅ GOOD: Validate before production
# Test error spike scenarios
# Test high load scenarios
# Verify critical events never dropped
```

---

### ❌ DON'T

**1. Don't sample audit events**
```ruby
# ❌ BAD: Audit events must be 100%
# Use .audit() not .track() for compliance events
Events::UserDeleted.audit(...)  # Always 100%
```

**2. Don't use aggressive sampling without testing**
```ruby
# ❌ BAD: 1% sampling too aggressive
base_sample_rate 0.01  # Might miss important events!

# ✅ GOOD: Start conservative
base_sample_rate 0.1  # 10%, adjust based on data
```

**3. Don't ignore dropped event metrics**
```ruby
# ❌ BAD: Not monitoring drops
# → You might be dropping critical events!

# ✅ GOOD: Alert on unexpected drops
# Alert: adaptive_sampling_events_dropped_total{reason="critical"} > 0
```

---

## 📚 Related Use Cases

- **[UC-011: Rate Limiting](./UC-011-rate-limiting.md)** - Complementary with sampling
- **[UC-015: Cost Optimization](./UC-015-cost-optimization.md)** - Sampling reduces costs

---

## 🎯 Summary

### Cost Savings

| Scenario | Fixed Sampling | Adaptive Sampling | Savings |
|----------|----------------|-------------------|---------|
| Normal load | 10% (100 ev/sec) | 10% (100 ev/sec) | 0% |
| Error spike | 10% (10k ev/sec) | 100% (100k ev/sec) | Better data! |
| High load | 10% (10k ev/sec) | 1% (1k ev/sec) | **90%** |
| Black Friday | 10% (10k ev/sec) | 6.5% (6.5k ev/sec) | **35%** |

**Result:** Same or better data quality, 35-90% cost reduction during peaks!

---

**Document Version:** 1.0  
**Last Updated:** January 12, 2026  
**Status:** ✅ Complete

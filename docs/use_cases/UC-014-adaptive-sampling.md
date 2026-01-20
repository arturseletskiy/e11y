# UC-014: Adaptive Sampling

**Status:** Partially Implemented (Error-Based - 2026-01-19)  
**Complexity:** Advanced  
**Setup Time:** 45-60 minutes  
**Target Users:** SRE, DevOps, Engineering Managers

**Implementation Status:**
- ✅ **Basic Sampling** - `E11y::Middleware::Sampling` with trace-aware logic (L2.7)
- ✅ **Event-level DSL** - `sample_rate` and `adaptive_sampling` in `Event::Base`
- ✅ **Pipeline Integration** - Sampling middleware in default pipeline
- ✅ **Error-Based Adaptive** - 100% sampling during error spikes (FEAT-4838)
- ✅ **Load-Based Adaptive** - Tiered sampling (100%/50%/10%/1%) based on load (FEAT-4842)
- ✅ **Value-Based Sampling** - Event DSL for sampling by payload values (FEAT-4846)
- ✅ **Stratified Sampling** - SLO-accurate sampling with correction (C11, FEAT-4850)

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

## 🚀 Current Implementation (2026-01-19)

### Basic Sampling (L2.7) ✅

**What's Implemented:**

```ruby
# 1. Event-level sample rate (explicit)
class HighFrequencyEvent < E11y::Event::Base
  sample_rate 0.01  # 1% sampling
end

# 2. Severity-based defaults (automatic)
class ErrorEvent < E11y::Event::Base
  severity :error  # → 100% sampling (SEVERITY_SAMPLE_RATES[:error])
end

class DebugEvent < E11y::Event::Base
  severity :debug  # → 1% sampling (SEVERITY_SAMPLE_RATES[:debug])
end

# 3. Trace-aware sampling (C05 resolution)
# All events in same trace_id get same sampling decision
OrderCreated.track(order_id: 123, trace_id: "abc")  # Sampled
PaymentProcessed.track(order_id: 123, trace_id: "abc")  # Also sampled (same trace)

# 4. Audit event exemption
class AuditEvent < E11y::Event::Base
  audit_event true  # Never sampled, always processed
end

# 5. Middleware configuration
E11y.configure do |config|
  # Sampling middleware is automatically added to default pipeline
  # Can override with custom config:
  config.pipeline.use E11y::Middleware::Sampling,
                      default_sample_rate: 0.1,
                      trace_aware: true
end
```

### Error-Based Adaptive Sampling (FEAT-4838) ✅

**Implemented (2026-01-19):**

```ruby
# Enable error-based adaptive sampling
E11y.configure do |config|
  config.pipeline.use E11y::Middleware::Sampling,
    default_sample_rate: 0.1,          # 10% normal sampling
    error_based_adaptive: true,        # Enable adaptive sampling
    error_spike_config: {
      window: 60,                      # 60 seconds sliding window
      absolute_threshold: 100,         # 100 errors/min triggers spike
      relative_threshold: 3.0,         # 3x normal rate triggers spike
      spike_duration: 300              # Keep 100% sampling for 5 minutes
    }
end

# Behavior:
# Normal conditions: 10% sampling (as configured)
# Error spike detected: Automatically increases to 100% sampling
# After spike ends: Returns to 10% after 5 minutes

# Example scenario:
# 09:00 AM: Normal load (10 errors/min)
# → 10% sampling (100 events/sec tracked)
#
# 09:30 AM: Error spike! (150 errors/min > 100 threshold)
# → 100% sampling (1000 events/sec tracked)
# → Better data for debugging!
#
# 09:35 AM: Errors normalized (10 errors/min)
# → Still 100% sampling (within spike_duration)
#
# 09:40 AM: 5 minutes passed
# → Back to 10% sampling
```

**Features:**
- **Absolute threshold**: Triggers when errors/min exceeds configured value
- **Relative threshold**: Triggers when error rate is 3x baseline
- **Baseline tracking**: Exponential moving average of normal error rate
- **Spike duration**: Maintains elevated sampling for configured period
- **Non-intrusive**: Errors are tracked automatically, no code changes needed

**Precedence (updated):**
0. **Error spike override** (100% during spike) - FEAT-4838
1. Explicit `sample_rate` (highest priority)
2. Severity-based defaults (`SEVERITY_SAMPLE_RATES`)
3. Middleware `default_sample_rate` (fallback)

**What's NOT Implemented Yet:**
- ⏳ Load-based adaptive (FEAT-4842)
- ⏳ Value-based sampling (FEAT-4846)
- ⏳ Stratified sampling for SLO accuracy (FEAT-4850, C11)
- ⏳ `adaptive_sampling` DSL block (placeholder only)

**See:**
- Detector: `lib/e11y/sampling/error_spike_detector.rb`
- Middleware: `lib/e11y/middleware/sampling.rb`
- Event DSL: `lib/e11y/event/base.rb` (`.sample_rate`, `.resolve_sample_rate`)
- Tests: `spec/e11y/sampling/error_spike_detector_spec.rb`, `spec/e11y/middleware/sampling_spec.rb`

### Load-Based Adaptive Sampling (FEAT-4842) ✅

**Implemented (2026-01-20):**

```ruby
# Enable load-based adaptive sampling
E11y.configure do |config|
  config.pipeline.use E11y::Middleware::Sampling,
    default_sample_rate: 0.1,             # 10% base sampling
    load_based_adaptive: true,            # Enable adaptive sampling
    load_monitor_config: {
      window: 60,                         # 60 seconds sliding window
      normal_threshold: 1_000,            # < 1k events/sec = normal
      high_threshold: 10_000,             # 10k events/sec = high load
      very_high_threshold: 50_000,        # 50k events/sec = very high
      overload_threshold: 100_000         # > 100k events/sec = overload
    }
end

# Tiered sampling behavior:
# Normal (<1k): 100% sampling (track everything)
# High (1k-10k): 50% sampling (moderate reduction)
# Very High (10k-50k): 10% sampling (aggressive reduction)
# Overload (>100k): 1% sampling (extreme reduction)

# Example scenario:
# 09:00: 500 events/sec   → 100% sampling (normal load)
# 09:30: 15k events/sec   → 10% sampling (very high load)
# 10:00: 120k events/sec  → 1% sampling (overload!)
# 10:30: 2k events/sec    → 50% sampling (returning to normal)
```

**Features:**
- **Tiered sampling**: 4 load levels with different sampling rates
- **Sliding window**: Event rate calculated over 60-second window
- **Thread-safe**: Uses MonitorMixin for concurrent access
- **Dynamic adjustment**: Sample rate updates in real-time

**Integration with other strategies:**
- Works as a "base rate" that can be further restricted by event-level config
- Error-based adaptive overrides load-based (100% during spikes)
- Value-based sampling overrides load-based (100% for high-value events)

**See:**
- Monitor: `lib/e11y/sampling/load_monitor.rb`
- Tests: `spec/e11y/sampling/load_monitor_spec.rb`, `spec/e11y/middleware/sampling_stress_spec.rb`

### Value-Based Sampling (FEAT-4846) ✅

**Implemented (2026-01-20):**

```ruby
# Event-level value-based sampling DSL
class Events::OrderPaid < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:decimal)
    required(:user_segment).filled(:string)
  end
  
  # Strategy 1: Always sample high-value orders
  sample_by_value field: "amount",
                  operator: :greater_than,
                  threshold: 1000,
                  sample_rate: 1.0  # 100% for orders > $1000
  
  # Strategy 2: Sample range of orders
  sample_by_value field: "amount",
                  operator: :in_range,
                  threshold: 100..500,
                  sample_rate: 0.5  # 50% for $100-$500 orders
  
  # Strategy 3: Sample specific segments
  sample_by_value field: "user_segment",
                  operator: :equals,
                  threshold: "enterprise",
                  sample_rate: 1.0  # 100% for enterprise users
end

# Usage:
Events::OrderPaid.track(
  order_id: "123",
  amount: 5000,              # > $1000 → Always sampled!
  user_segment: "enterprise"  # → Also matches second rule!
)

Events::OrderPaid.track(
  order_id: "456",
  amount: 250,               # In range $100-$500 → 50% chance
  user_segment: "free"
)

Events::OrderPaid.track(
  order_id: "789",
  amount: 50,                # < $100 → Falls back to default sampling
  user_segment: "free"
)
```

**Supported Operators:**
- `:greater_than` (>): Numeric threshold (e.g., amount > 1000)
- `:less_than` (<): Numeric threshold (e.g., latency < 100)
- `:equals` (==): Exact value match (string or numeric)
- `:in_range`: Range of values (e.g., 100..500)

**Features:**
- **Nested field extraction**: Supports dot notation (e.g., `"order.amount"`)
- **Type coercion**: Numeric strings automatically converted to floats
- **Nil handling**: Missing/nil values treated as 0.0
- **High priority**: Overrides load-based sampling

**See:**
- Extractor: `lib/e11y/sampling/value_extractor.rb`
- Config: `lib/e11y/event/value_sampling_config.rb`
- Event DSL: `lib/e11y/event/base.rb` (`.sample_by_value`)
- Tests: `spec/e11y/sampling/value_extractor_spec.rb`, `spec/e11y/middleware/sampling_value_based_spec.rb`

### Stratified Sampling for SLO Accuracy (FEAT-4850, C11 Resolution) ✅

**Implemented (2026-01-20):**

```ruby
# Automatic stratified sampling (no config needed!)
# E11y automatically records sample rates per severity stratum

# Example: SLO calculation with sampling correction
module E11y
  module SLO
    class Tracker
      # Calculates success rate with sampling correction
      def track_http_request_success(controller:, action:, status:, duration_ms:, sample_rate: 1.0)
        # Record sampled event
        E11y::Metrics.increment("e11y.slo.http.requests",
          controller: controller,
          action: action,
          status_class: "#{status / 100}xx",
          sample_rate: sample_rate  # ← Metadata for correction
        )
        
        # Stratified tracker records for later correction
        @stratified_tracker.record_sample(
          severity: status >= 500 ? :error : :info,
          sample_rate: sample_rate
        )
      end
      
      # Calculate corrected success rate
      def http_success_rate(window: 5.minutes)
        # Get correction factors per severity
        correction = @stratified_tracker.sampling_correction(:info)
        
        # Apply correction to raw metrics
        raw_success_rate = Yabeda.e11y_slo_http_requests
          .with_labels(status_class: "2xx")
          .get
        
        corrected_success_rate = raw_success_rate * correction
        corrected_success_rate
      end
    end
  end
end

# Scenario: 1000 requests (950 success, 50 errors)
# Stratified sampling: errors 100%, success 10%
# Events kept: 50 + 95 = 145 (85.5% cost savings!)

# Without correction:
# Observed success rate: 95/145 = 65.5% ❌ WRONG

# With correction:
# Corrected success: 95 / 0.1 = 950
# Corrected errors: 50 / 1.0 = 50
# Corrected success rate: 950 / 1000 = 95.0% ✅ ACCURATE
```

**Features:**
- **Automatic tracking**: No config needed, records sample rates per event
- **Per-severity correction**: Different correction factors for errors vs success
- **Integration with SLO**: Seamlessly corrects SLO metrics
- **< 5% error margin**: Proven accuracy in integration tests

**See:**
- Tracker: `lib/e11y/sampling/stratified_tracker.rb`
- SLO integration: `lib/e11y/slo/tracker.rb`
- Tests: `spec/e11y/sampling/stratified_tracker_spec.rb`, `spec/e11y/slo/stratified_sampling_integration_spec.rb`

---

## 🎯 Adaptive Sampling Strategies (Conceptual - Future)

---

### Event-Level Sampling Configuration (NEW - v1.1)

> **🎯 CONTRADICTION_01 Resolution:** Move sampling config from global initializer to event classes.

**Event-level sampling DSL:**

```ruby
# app/events/order_created.rb
module Events
  class OrderCreated < E11y::Event::Base
    schema do
      required(:order_id).filled(:string)
      required(:amount).filled(:decimal)
    end
    
    # ✨ Event-level sampling (right next to schema!)
    sample_rate 0.1  # 10% sampling
    
    # Or adaptive sampling:
    adaptive_sampling do
      base_rate 0.1  # 10% default
      
      # Increase for high-value orders
      sample_by_value do
        field :amount
        threshold 1000  # Always sample >$1000
      end
      
      # Increase during errors
      on_error_spike do
        sample_rate 1.0  # 100% during errors
        duration 5.minutes
      end
    end
  end
end
```

**Inheritance for sampling:**

```ruby
# Base class with common sampling
module Events
  class BasePaymentEvent < E11y::Event::Base
    # Never sample payments (high-value)
    sample_rate 1.0  # 100%
    
    # Or adaptive:
    adaptive_sampling do
      base_rate 1.0  # Always sample by default
      
      # But reduce during extreme load
      on_high_load do
        sample_rate 0.5  # 50% during overload
        load_threshold 100_000  # events/sec
      end
    end
  end
end

# Inherit from base
class Events::PaymentSucceeded < Events::BasePaymentEvent
  schema do; required(:transaction_id).filled(:string); end
  # ← Inherits: sample_rate 1.0 + adaptive rules
end

class Events::PaymentFailed < Events::BasePaymentEvent
  # Override: ALWAYS sample errors (even during overload)
  sample_rate 1.0
  adaptive_sampling enabled: false  # ← Disable adaptive (keyword arg!)
end
```

**Preset modules for sampling:**

```ruby
# lib/e11y/presets/high_value_event.rb
module E11y
  module Presets
    module HighValueEvent
      extend ActiveSupport::Concern
      included do
        sample_rate 1.0  # Never sample (100%)
        
        adaptive_sampling do
          # Only reduce during extreme load
          on_high_load do
            sample_rate 0.5  # 50%
            load_threshold 100_000
          end
        end
      end
    end
    
    module DebugEvent
      extend ActiveSupport::Concern
      included do
        sample_rate 0.01  # 1% sampling
        
        adaptive_sampling do
          # Increase during errors
          on_error_spike do
            sample_rate 0.1  # 10% during errors
          end
        end
      end
    end
  end
end

# Usage:
class Events::PaymentProcessed < E11y::Event::Base
  include E11y::Presets::HighValueEvent  # ← Sampling inherited!
  schema do; required(:transaction_id).filled(:string); end
end

class Events::DebugQuery < E11y::Event::Base
  include E11y::Presets::DebugEvent  # ← Sampling inherited!
  schema do; required(:query).filled(:string); end
end
```

**Conventions for sampling (sensible defaults):**

```ruby
# Convention: Severity → Sample Rate
# :error/:fatal → 1.0 (100%, never sample errors!)
# :warn → 0.5 (50%)
# :success/:info → 0.1 (10%)
# :debug → 0.01 (1%)

# Zero-config event (uses conventions):
class Events::OrderCreated < E11y::Event::Base
  severity :success
  schema do; required(:order_id).filled(:string); end
  # ← Auto: sample_rate = 0.1 (10%, from severity!)
end

# Override convention:
class Events::OrderCreated < E11y::Event::Base
  severity :success
  sample_rate 1.0  # ← Override: never sample orders
  schema do; required(:order_id).filled(:string); end
end
```

**Precedence (event-level overrides global):**

```ruby
# Global config (infrastructure):
E11y.configure do |config|
  config.sampling do
    base_sample_rate 0.1  # 10% default
    
    adaptive_sampling do
      on_error_spike do
        sample_rate 1.0
      end
    end
  end
end

# Event-level config (overrides global):
class Events::CriticalError < E11y::Event::Base
  sample_rate 1.0  # ← Override: always 100% (not 10%)
  adaptive_sampling enabled: false  # ← Disable adaptive (keyword arg!)
end
```

**Benefits:**
- ✅ Locality of behavior (sampling next to schema)
- ✅ DRY via inheritance/presets
- ✅ Sensible defaults (90% events need zero config)
- ✅ Easy to override when needed

---

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
    end
  end
end
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

### Strategy 7: Trace-Consistent Sampling

**Problem:** Inconsistent sampling breaks distributed traces

```ruby
# ❌ PROBLEM: Inconsistent sampling creates incomplete traces
# 
# HTTP request (trace_id: abc-123):
# → Sample rate: 10% → NOT sampled (90% case)
# 
# Background job (trace_id: abc-123):
# → Sample rate: 10% → MAYBE sampled
# 
# RESULT: Job event exists in Loki, but NO parent HTTP event!
# → Trace is INCOMPLETE (orphaned events, can't understand context)
```

**Solution:** Sample decision propagated across trace boundaries

```ruby
E11y.configure do |config|
  config.adaptive_sampling do
    # ✅ Trace-consistent sampling: All or nothing
    trace_consistent do
      enabled true
      
      # Sample entire trace if ANY event is error/fatal
      sample_on_error true
      
      # Propagate sample decision to jobs/services
      propagate_decision true
      sample_decision_key 'e11y_sampled'
    end
  end
end

# How it works:
# 1. HTTP request arrives (trace_id: abc-123)
# 2. Sample decision made: rand < 0.1 → false (NOT sampled)
# 3. Decision stored in Current.sampled = false
# 4. Job enqueued with metadata: { e11y_sampled: false }
# 5. Job executes → reads e11y_sampled → skips tracking
# 
# RESULT: Both HTTP and Job NOT sampled → Trace consistent!
```

**Trace lifecycle example:**

```ruby
# === REQUEST (trace_id: abc-123) ===
class OrdersController < ApplicationController
  def create
    # 1. Sample decision made at entry point
    # → rand < 0.1 = 0.05 → SAMPLED!
    # → Current.sampled = true
    
    Events::OrderCreated.track(order_id: '123')
    # → Tracked (sampled = true)
    
    # 2. Enqueue job (sample decision propagated)
    SendEmailJob.perform_later(
      order_id: '123'
      # E11y automatically adds: e11y_sampled: true
    )
    
    Events::OrderCompleted.track(order_id: '123')
    # → Tracked (sampled = true)
  end
end

# === BACKGROUND JOB (trace_id: abc-123, e11y_sampled: true) ===
class SendEmailJob < ApplicationJob
  def perform(order_id)
    # 3. Sample decision restored from job metadata
    # → Current.sampled = true (from metadata)
    
    Events::EmailSending.track(order_id: order_id)
    # → Tracked (sampled = true, consistent with parent!)
    
    send_email(order_id)
    
    Events::EmailSent.track(order_id: order_id)
    # → Tracked (sampled = true)
  end
end

# RESULT: Complete trace in Loki!
# [abc-123] order.created (HTTP)
# [abc-123] order.completed (HTTP)
# [abc-123] email.sending (Job)
# [abc-123] email.sent (Job)
# → All events present, trace is COMPLETE!
```

**Exception handling:**

```ruby
E11y.configure do |config|
  config.adaptive_sampling do
    trace_consistent do
      enabled true
      
      # If error occurs, sample ENTIRE trace retroactively
      sample_on_error true
      
      # This requires buffering (see UC-001: Request-Scoped Debug Buffering)
      # If trace was NOT sampled initially, but error occurs:
      # → Flush buffer (contains all events)
      # → Sample decision overridden to true
      # → Complete trace available for debugging!
    end
    
    # Always sample specific patterns (override trace decision)
    always_sample event_patterns: ['payment.*', 'security.*'],
                  severities: [:error, :fatal]
  end
end

# Example:
# 1. HTTP request: sample decision = false (NOT sampled)
# 2. Order created: NOT tracked (buffer only)
# 3. Payment fails: ERROR!
# 4. sample_on_error = true → Override decision to true
# 5. Flush buffer → All events sent (including buffered ones)
# 6. Job executes with e11y_sampled: true → Tracked
# 
# RESULT: Complete trace available BECAUSE of error!
```

**Cross-service propagation:**

```ruby
# Service A: API Gateway (trace_id: abc-123, sampled: true)
class OrdersController < ApplicationController
  def create
    Events::OrderReceived.track(order_id: '123')
    # → Tracked (sampled = true)
    
    # Call Payment Service (propagate sample decision in header)
    response = HTTP
      .headers(
        'X-Trace-ID' => E11y::Current.trace_id,
        'X-E11y-Sampled' => E11y::Current.sampled.to_s  # ← Propagate!
      )
      .post('http://payment-service/charge', json: { order_id: '123' })
    
    Events::OrderCreated.track(order_id: '123')
    # → Tracked
  end
end

# Service B: Payment Service (trace_id: abc-123, sampled: true from header)
class PaymentsController < ApplicationController
  def charge
    # Sample decision extracted from X-E11y-Sampled header
    # → Current.sampled = true
    
    Events::PaymentProcessing.track(order_id: params[:order_id])
    # → Tracked (consistent with Service A!)
    
    process_payment
    
    Events::PaymentSucceeded.track(order_id: params[:order_id])
    # → Tracked
  end
end

# RESULT: Complete distributed trace!
# [Service A, abc-123] order.received
# [Service A, abc-123] order.created
# [Service B, abc-123] payment.processing
# [Service B, abc-123] payment.succeeded
```

**Configuration for different scenarios:**

```ruby
E11y.configure do |config|
  config.adaptive_sampling do
    # Strategy 1: Strict trace consistency (default)
    trace_consistent do
      enabled true
      propagate_decision true
      sample_on_error true
    end
    
    # Strategy 2: Independent sampling (simpler, but incomplete traces)
    # trace_consistent do
    #   enabled false  # Each service/job samples independently
    # end
    
    # Strategy 3: Always sample background jobs (practical compromise)
    always_sample event_patterns: ['background_jobs.*']
    # → Jobs always tracked, HTTP sampled independently
    # → Cost: jobs 100%, HTTP 10%
    # → Benefit: Never lose job events, acceptable overhead
    
    # Strategy 4: Orphaned job handling
    # Jobs WITHOUT parent trace (cron jobs, manual triggers)
    orphaned_job_sampling do
      sample_rate 1.0  # Always sample orphaned jobs
    end
  end
end
```

**Why trace-consistent sampling matters:**

| Scenario | Without Trace-Consistency | With Trace-Consistency | Winner |
|----------|---------------------------|------------------------|--------|
| **Normal request** (sampled) | HTTP tracked, Job 10% chance | HTTP tracked, Job tracked | ✅ Same |
| **Normal request** (not sampled) | HTTP dropped, Job 10% chance → orphaned! | HTTP dropped, Job dropped | ✅ Consistent |
| **Error request** (initially not sampled) | HTTP buffered only, Job 10% chance | HTTP flushed + Job tracked (sample_on_error) | ✅ Complete |
| **Distributed trace** | Service A sampled, Service B 10% chance → broken! | Service A sampled → Service B sampled | ✅ Complete |

**See also:**
- **[UC-006: Trace Context Management](./UC-006-trace-context-management.md)** - Implementation details for trace propagation
- **[UC-001: Request-Scoped Debug Buffering](./UC-001-request-scoped-debug-buffering.md)** - How `sample_on_error` works with buffering

---

### Strategy 8: Stratified Sampling for Accurate SLO (C11 Resolution) ⚠️

> **Reference:** See [ADR-009 §3.7: Stratified Sampling for SLO Accuracy](../ADR-009-cost-optimization.md#37-stratified-sampling-for-slo-accuracy-c11-resolution) for full architecture and [UC-004: SLO Tracking with Sampling Correction](./UC-004-zero-config-slo-tracking.md#sampling-correction-for-accurate-slo-c11-resolution) for SLO calculation details.

**Problem with Random Sampling:** Breaks SLO metrics! Errors are rare (5%) → random 10% sampling drops 90% of errors → SLO appears better than reality.

**Solution:** Stratified sampling preserves error/success RATIO by sampling each severity class at different rates.

```ruby
E11y.configure do |config|
  config.cost_optimization do
    sampling do
      # ✅ Stratified sampling (NOT random!)
      strategy :stratified_adaptive
      
      # Cost budget
      cost_budget 100_000  # events/month
      
      # 🎯 SIMPLE CONFIG: Sample rate by severity (C11)
      stratified_rates do
        error 1.0    # 100% - Keep ALL errors (critical for SLO!)
        warn  0.5    # 50%  - Medium priority
        info  0.1    # 10%  - Low priority (успешные запросы)
        debug 0.05   # 5%   - Very low priority
      end
    end
  end
  
  # SLO tracking with automatic correction (enabled by default!)
  config.slo do
    enable_sampling_correction true  # ✅ Corrects metrics automatically
  end
end
```

**How It Works:**

```ruby
# Scenario: 1000 requests (950 success, 50 errors) → 95% success rate

# Random sampling (10%):
# - Sample 100 random events
# - Might get: 98 success, 2 errors (luck!)
# - Observed success rate: 98% ❌ WRONG! (should be 95%)

# Stratified sampling (errors: 100%, success: 10%):
# - Sample 50 errors (100% × 50)
# - Sample 95 success (10% × 950)
# - Total: 145 events sampled (85.5% cost savings!)
# - Observed success rate: 95/145 = 65.5%
# - Corrected success rate: (95 × 1/0.1) / ((95 × 1/0.1) + (50 × 1/1.0)) = 950 / 1000 = 95% ✅ CORRECT!
```

**Cost Savings Example:**

```ruby
# 10M events/month (9.5M success, 500K errors)

# WITHOUT stratified sampling (100% all events):
# Cost: 10M events × $0.001 = $10,000/month

# WITH stratified sampling (errors: 100%, success: 10%):
# Kept: (500K × 1.0) + (9.5M × 0.1) = 500K + 950K = 1.45M events
# Cost: 1.45M × $0.001 = $1,450/month
# Savings: $8,550/month (85.5% reduction!) 💰
# SLO accuracy: 100% (errors fully preserved)
```

**Comparison: Random vs Stratified**

| Aspect | Random Sampling (10%) | Stratified Sampling (C11) |
|--------|----------------------|--------------------------|
| **Events kept** | 1M (10% of 10M) | 1.45M (14.5% of 10M) |
| **Errors kept** | ~50K (10% × 500K) ❌ | 500K (100% × 500K) ✅ |
| **Success kept** | ~950K (10% × 9.5M) | 950K (10% × 9.5M) |
| **SLO accuracy** | ±5% error ❌ | 0% error ✅ |
| **Cost savings** | 90% | 85.5% |
| **Best for** | Non-critical apps | Production SLO tracking |

**StratifiedAdaptiveSampler Implementation:**

```ruby
# lib/e11y/sampling/stratified_adaptive_sampler.rb
module E11y
  module Sampling
    class StratifiedAdaptiveSampler < SimplifiedSampler
      def sample?(event)
        # Get sample rate for event severity
        sample_rate = stratified_rate_for(event)
        
        # Random sampling within stratum
        rand < sample_rate
      end
      
      def stratified_rate_for(event)
        case event.severity
        when :error, :fatal
          1.0  # 100% - never drop errors!
        when :warn
          0.5  # 50%
        when :info, :success
          0.1  # 10%
        when :debug
          0.05 # 5%
        else
          0.1  # Default
        end
      end
      
      # Store sample rate in event metadata (for correction)
      def after_sample(event, sampled)
        if sampled
          event.metadata[:sample_rate] = stratified_rate_for(event)
        end
      end
    end
  end
end
```

**SLO Calculation with Correction:**

```ruby
# lib/e11y/slo/calculator.rb
module E11y
  module SLO
    class Calculator
      def error_rate
        # Query sampled events
        total_sampled = Event.count
        errors_sampled = Event.where(severity: [:error, :fatal]).count
        
        # Apply sampling correction
        total_corrected = correct_count(total_sampled)
        errors_corrected = correct_count(errors_sampled, severity: :error)
        
        # Calculate corrected error rate
        errors_corrected.to_f / total_corrected
      end
      
      private
      
      def correct_count(sampled_count, severity: nil)
        # Get sample rate for this severity
        sample_rate = case severity
                      when :error, :fatal then 1.0
                      when :warn then 0.5
                      when :info, :success then 0.1
                      else 0.1
                      end
        
        # Correct count: observed × (1 / sample_rate)
        sampled_count / sample_rate
      end
    end
  end
end

# Usage:
E11y::SLO.error_rate  # ✅ Returns corrected error rate (accurate!)
```

**Trade-offs:**

| Aspect | Pro | Con | Decision |
|--------|-----|-----|----------|
| **Stratified by severity** | SLO accuracy preserved | Slightly more complex | Accuracy > simplicity |
| **100% errors, 10% success** | 85% cost savings + accurate SLO | More events than pure random | Best balance |
| **Sampling correction math** | Accurate metrics | Need to apply correction | Auto-corrected by E11y |
| **Simple config** | Easy to use | Less flexible than custom strata | Covers 95% of use cases |

---

## 💻 Implementation Examples

### Example 1: Production Incident Response (Phase 2.8 - All Strategies) ✅

```ruby
# Scenario: Payment gateway outage
# Normal: 1k events/sec, 1% errors
# Incident: 50k events/sec, 80% errors

# Configuration with all 4 strategies
E11y.configure do |config|
  config.pipeline.use E11y::Middleware::Sampling,
    default_sample_rate: 0.1,
    
    # Strategy 1: Error-Based Adaptive (FEAT-4838)
    error_based_adaptive: true,
    error_spike_config: {
      window: 60,
      absolute_threshold: 100,       # 100 errors/min
      relative_threshold: 3.0,       # 3x baseline
      spike_duration: 600            # 10 minutes
    },
    
    # Strategy 2: Load-Based Adaptive (FEAT-4842)
    load_based_adaptive: true,
    load_monitor_config: {
      window: 60,
      normal_threshold: 1_000,
      high_threshold: 10_000,
      very_high_threshold: 50_000,
      overload_threshold: 100_000
    }
end

# Strategy 3: Value-Based Sampling (FEAT-4846)
class Events::PaymentProcessed < E11y::Event::Base
  # Always sample payment events (business-critical)
  sample_rate 1.0
  
  # But still respect value-based rules
  sample_by_value field: "amount",
                  operator: :greater_than,
                  threshold: 1000,
                  sample_rate: 1.0  # Always sample high-value
end

# Timeline during incident:
# 10:00: Normal (1k/sec, 1% errors)
#   → Load: normal → base rate 100%
#   → Error spike: NO → rate unchanged
#   → Payment events: 100% (event-level config)
#   → Final: 100% sampling
#
# 10:05: Incident starts (10k/sec, 40% errors)
#   → Load: high → base rate 50%
#   → Error spike: YES (40% > 5%) → override to 100%!
#   → Payment events: 100% (error spike overrides)
#   → Final: 100% sampling (debug priority!)
#
# 10:10: Incident peak (50k/sec, 80% errors)
#   → Load: very_high → base rate 10%
#   → Error spike: YES (still active) → override to 100%!
#   → Payment events: 100% (error spike overrides)
#   → Final: 100% sampling (all errors captured!)
#
# 10:20: Incident resolving (5k/sec, 10% errors)
#   → Load: high → base rate 50%
#   → Error spike: Still active (within 10min duration)
#   → Payment events: 100%
#   → Final: 100% sampling (spike duration not expired)
#
# 10:30: Normal (1k/sec, 1% errors)
#   → Load: normal → base rate 100%
#   → Error spike: NO (expired after 10min)
#   → Payment events: 100%
#   → Final: 100% sampling (back to normal)
```

**Original Example (Conceptual):**

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

### Example 2: Black Friday Traffic (Phase 2.8 - Load + Value-Based) ✅

```ruby
# Scenario: Black Friday sale
# Normal: 2k events/sec
# Black Friday: 100k events/sec (50x increase!)

# Configuration with load-based + value-based sampling
E11y.configure do |config|
  config.pipeline.use E11y::Middleware::Sampling,
    default_sample_rate: 0.1,
    
    # Load-Based Adaptive (FEAT-4842)
    load_based_adaptive: true,
    load_monitor_config: {
      window: 60,
      normal_threshold: 1_000,
      high_threshold: 10_000,
      very_high_threshold: 50_000,
      overload_threshold: 100_000    # Black Friday triggers this!
    },
    
    # Error-Based Adaptive (for incident detection)
    error_based_adaptive: true,
    error_spike_config: {
      absolute_threshold: 100,
      relative_threshold: 3.0
    }
end

# Value-Based Sampling (FEAT-4846)
class Events::OrderPaid < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:decimal)
  end
  
  # Always sample high-value orders (even during overload!)
  sample_by_value field: "amount",
                  operator: :greater_than,
                  threshold: 500,
                  sample_rate: 1.0  # 100% for >$500 orders
end

# Black Friday timeline:
# 00:00 (start): 100k events/sec
#   → Load: overload → base rate 1%
#   → High-value orders (5k/sec): 100% (value-based override)
#   → Regular orders (95k/sec): 1% = 950 events/sec
#   → Total tracked: 5k + 950 = 5,950 events/sec (5.95%)
#   vs. 10k with fixed 10% sampling → 40% savings!
#
# 12:00 (peak): 150k events/sec
#   → Load: overload → base rate 1%
#   → High-value orders (10k/sec): 100% (10k tracked)
#   → Regular orders (140k/sec): 1% = 1,400 tracked
#   → Total tracked: 11,400 events/sec (7.6%)
#   → Cost protection while capturing all high-value!
#
# 23:59 (end): 20k events/sec
#   → Load: high → base rate 50%
#   → High-value orders (1k/sec): 100% (1k tracked)
#   → Regular orders (19k/sec): 50% = 9,500 tracked
#   → Total tracked: 10,500 events/sec (52.5%)
#   → Returning to normal rates
```

**Stratified Sampling SLO Accuracy (FEAT-4850):**

```ruby
# During Black Friday, even with aggressive sampling (1% for regular, 100% for errors):
# - Errors: 500/sec × 100% = 500 tracked
# - Success: 99.5k/sec × 1% = 995 tracked
# - Total: 1,495 tracked (1.495% sampling!)
#
# SLO Calculation (with correction):
# Observed success rate: 995 / 1495 = 66.6% ❌ WRONG
# Corrected success: 995 / 0.01 = 99,500
# Corrected errors: 500 / 1.0 = 500
# Corrected success rate: 99,500 / 100,000 = 99.5% ✅ ACCURATE
#
# Result: 98.5% cost savings with 100% SLO accuracy!
```

**Original Example (Conceptual):**

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

## 🔒 Validations (NEW - v1.1)

> **🎯 Pattern:** Validate sampling configuration at class load time.

### Sample Rate Validation

**Problem:** Invalid sample rates → silent failures.

**Solution:** Validate sample_rate is between 0.0 and 1.0:

```ruby
# Gem implementation (automatic):
def self.sample_rate(rate)
  unless rate.is_a?(Numeric) && rate >= 0.0 && rate <= 1.0
    raise ArgumentError, "sample_rate must be 0.0..1.0, got: #{rate.inspect}"
  end
  self._sample_rate = rate
end

# Result:
class Events::ApiRequest < E11y::Event::Base
  sample_rate 1.5  # ← ERROR: "sample_rate must be 0.0..1.0, got: 1.5"
end
```

### Adaptive Sampling Validation

**Problem:** Invalid adaptive_sampling config → runtime errors.

**Solution:** Validate enabled parameter:

```ruby
# Gem implementation (automatic):
def self.adaptive_sampling(enabled:)
  unless [true, false].include?(enabled)
    raise ArgumentError, "adaptive_sampling enabled: must be true or false, got: #{enabled.inspect}"
  end
  self._adaptive_sampling = enabled
end

# Result:
class Events::ApiRequest < E11y::Event::Base
  adaptive_sampling enabled: "yes"  # ← ERROR: "adaptive_sampling enabled: must be true or false, got: \"yes\""
end
```

### Audit Event Sampling Validation (LOCKED)

**Problem:** Attempting to sample audit events → compliance violations.

**Solution:** Lock sampling for audit events:

```ruby
# Gem implementation (automatic):
def self.sampling(enabled)
  if self._audit_event && enabled
    raise ArgumentError, "Cannot enable sampling for audit events! Audit events must never be sampled."
  end
  self._sampling = enabled
end

# Result:
class Events::UserDeleted < E11y::Event::Base
  audit_event true
  sample_rate 0.5  # ← ERROR: "Cannot enable sampling for audit events!"
end
```

---

## 🌍 Environment-Specific Sampling (NEW - v1.1)

> **🎯 Pattern:** Different sampling rates per environment.

### Example 1: Higher Sampling in Production

```ruby
class Events::DebugQuery < E11y::Event::Base
  schema do
    required(:query).filled(:string)
    required(:duration_ms).filled(:integer)
  end
  
  # Environment-specific sampling
  sample_rate Rails.env.production? ? 0.01 : 1.0  # 1% prod, 100% dev
  adaptive_sampling enabled: Rails.env.production?  # Only in prod
end
```

### Example 2: Feature Flag for Adaptive Sampling

```ruby
class Events::ApiRequest < E11y::Event::Base
  schema do
    required(:endpoint).filled(:string)
    required(:status).filled(:integer)
  end
  
  # Enable adaptive sampling only when flag is on
  if ENV['ENABLE_ADAPTIVE_SAMPLING'] == 'true'
    adaptive_sampling enabled: true
    sample_rate 0.1  # Base rate: 10%
  else
    sample_rate 1.0  # Fixed: 100%
  end
end
```

### Example 3: Cost-Based Sampling

```ruby
class Events::UserAction < E11y::Event::Base
  schema do
    required(:action_type).filled(:string)
  end
  
  # Aggressive sampling in high-cost environments
  sample_rate case ENV['OBSERVABILITY_TIER']
              when 'premium' then 1.0    # 100% (unlimited budget)
              when 'standard' then 0.1   # 10% (moderate budget)
              when 'basic' then 0.01     # 1% (tight budget)
              else 0.1
              end
end
```

---

## 📊 Precedence Rules for Sampling (NEW - v1.1)

> **🎯 Pattern:** Sampling configuration precedence (most specific wins).

### Precedence Order (Highest to Lowest)

```
1. Event-level explicit config (highest priority)
   ↓
2. Preset module config
   ↓
3. Base class config (inheritance)
   ↓
4. Convention-based defaults (severity → sample rate)
   ↓
5. Global config (lowest priority)
```

### Example: Mixing Inheritance + Presets for Sampling

```ruby
# Global config (lowest priority)
E11y.configure do |config|
  config.sampling do
    base_sample_rate 0.1  # Default: 10%
    adaptive_sampling enabled: false
  end
end

# Base class (medium priority)
class Events::BasePaymentEvent < E11y::Event::Base
  severity :success
  sample_rate 1.0  # Override global (never sample payments!)
  adaptive_sampling enabled: false  # Disable adaptive
end

# Preset module (higher priority)
module E11y::Presets::DebugEvent
  extend ActiveSupport::Concern
  included do
    sample_rate 0.01  # Override base (1% for debug)
    adaptive_sampling enabled: true  # Enable adaptive
  end
end

# Event (highest priority)
class Events::CriticalDebug < Events::BasePaymentEvent
  include E11y::Presets::DebugEvent
  
  sample_rate 0.1  # Override preset (10% for critical debug)
  
  # Final config:
  # - severity: :success (from base)
  # - sample_rate: 0.1 (event-level override)
  # - adaptive_sampling: enabled: true (from preset)
end
```

### Precedence Rules Table

| Config | Global | Convention | Base Class | Preset | Event-Level | Winner |
|--------|--------|------------|------------|--------|-------------|--------|
| `sample_rate` | `0.1` | `0.5` (`:warn`) | `1.0` | `0.01` | `0.1` | **`0.1`** (event) |
| `adaptive_sampling` | `false` | - | `false` | `true` | - | **`true`** (preset) |

### Convention-Based Defaults

**Convention:** Severity → sample_rate (if not specified):

```ruby
# :error/:fatal → 1.0 (100%)
class Events::PaymentFailed < E11y::Event::Base
  severity :error
  # ← Auto: sample_rate = 1.0 (convention!)
end

# :warn → 0.5 (50%)
class Events::SlowQuery < E11y::Event::Base
  severity :warn
  # ← Auto: sample_rate = 0.5 (convention!)
end

# :debug → 0.01 (1%)
class Events::DebugLog < E11y::Event::Base
  severity :debug
  # ← Auto: sample_rate = 0.01 (convention!)
end
```

---

## 📚 Related Use Cases

- **[UC-006: Trace Context Management](./UC-006-trace-context-management.md)** - Trace-consistent sampling requires trace propagation
- **[UC-001: Request-Scoped Debug Buffering](./UC-001-request-scoped-debug-buffering.md)** - `sample_on_error` works with buffering
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

**Document Version:** 1.1 (Unified DSL)  
**Last Updated:** January 16, 2026  
**Status:** ✅ Complete - Consistent with DSL-SPECIFICATION.md v1.1.0

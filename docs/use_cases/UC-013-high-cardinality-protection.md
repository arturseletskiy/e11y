# UC-013: High Cardinality Protection

**Status:** v1.0 Feature (Critical for Scale)  
**Complexity:** Advanced  
**Setup Time:** 30-60 minutes  
**Target Users:** Engineering Managers, SRE, DevOps, Backend Developers

---

## 📋 Overview

### Problem Statement

**The $68,000/month mistake:**
```ruby
# ❌ CATASTROPHIC: Using user_id as metric label (event-level example - avoid!)
class Events::UserAction < E11y::Event::Base
  metrics do
    counter :user_actions_total, tags: [:user_id, :action_type]  # ← 💸💸💸 DON'T
  end
end

# With 100,000 users × 10 action types = 1,000,000 metric series
# Datadog cost: $68/host × 1000 hosts = $68,000/month
# Prometheus memory: ~200 bytes/series × 1M = 200 MB per host
# Query latency: 10x slower due to cardinality explosion
```

**Real-world impact:**
- 200 services × 1,000 users × 5 dimensions = **1,000,000 metric series**
- **Datadog cost: $68,000/month**
- **Prometheus OOM crashes** (out of memory)
- **Query timeouts** (PromQL queries take 30+ seconds)
- **Incident during Black Friday** (metrics system collapsed)

### E11y Solution (Event-Level)

**Use low-cardinality tags in event-level metrics:**
```ruby
# ✅ SAFE: Use user_segment, not user_id
class Events::UserAction < E11y::Event::Base
  schema do
    required(:user_id).filled(:string)
    required(:action_type).filled(:string)
    required(:user_segment).filled(:string)  # pre-aggregated: 'free', 'paid', 'enterprise'
  end

  metrics do
    counter :user_actions_total, tags: [:user_segment, :action_type]  # 3 × 10 = 30 series
  end
end

# Result: low cardinality, manageable cost
```

---

## 🎯 Event-Level Cardinality Protection (NEW - v1.1)

> **🎯 CONTRADICTION_01 Resolution:** Move cardinality config from global initializer to event classes.

**Event-level cardinality DSL:**

```ruby
# app/events/user_action.rb
module Events
  class UserAction < E11y::Event::Base
    schema do
      required(:user_id).filled(:string)
      required(:action_type).filled(:string)
      required(:user_segment).filled(:string)
    end
    
    # ✨ Event-level cardinality protection (right next to schema!)
    metric :counter,
           name: 'user_actions_total',
           tags: [:user_segment, :action_type],  # ← Safe labels
           cardinality_limit: 100  # Max 100 series
    
    # Forbidden labels (high cardinality)
    forbidden_metric_labels :user_id, :session_id
    
    # Safe labels (low cardinality)
    safe_metric_labels :user_segment, :action_type, :status
  end
end
```

**Inheritance for cardinality protection:**

```ruby
# Base class with common cardinality rules
module Events
  class BaseUserEvent < E11y::Event::Base
    # Common for ALL user events
    forbidden_metric_labels :user_id, :email, :ip_address
    safe_metric_labels :user_segment, :country, :plan
    
    # Default cardinality limit
    default_cardinality_limit 100
  end
end

# Inherit from base
class Events::UserAction < Events::BaseUserEvent
  schema do
    required(:user_id).filled(:string)
    required(:action_type).filled(:string)
  end
  
  metric :counter,
         name: 'user_actions_total',
         tags: [:user_segment, :action_type]  # ← Uses safe labels
  # ← Inherits: forbidden_metric_labels + safe_metric_labels
end

class Events::UserProfileUpdated < Events::BaseUserEvent
  schema do
    required(:user_id).filled(:string)
    required(:field_name).filled(:string)
  end
  
  metric :counter,
         name: 'profile_updates_total',
         tags: [:user_segment, :field_name]
  # ← Inherits: forbidden_metric_labels + safe_metric_labels
end
```

**Preset modules for cardinality protection:**

```ruby
# lib/e11y/presets/metric_safe_event.rb
module E11y
  module Presets
    module MetricSafeEvent
      extend ActiveSupport::Concern
      included do
        # Common forbidden labels (high cardinality)
        forbidden_metric_labels :user_id, :order_id, :session_id,
                                :trace_id, :request_id, :email,
                                :ip_address, :uuid
        
        # Common safe labels (low cardinality)
        safe_metric_labels :status, :severity, :country,
                           :plan, :segment, :method
        
        # Default cardinality limit
        default_cardinality_limit 100
        
        # Auto-aggregate on limit
        cardinality_monitoring do
          warn_threshold 0.7
          auto_aggregate true
        end
      end
    end
  end
end

# Usage:
class Events::OrderPlaced < E11y::Event::Base
  include E11y::Presets::MetricSafeEvent  # ← Cardinality rules inherited!
  
  schema do
    required(:order_id).filled(:string)
    required(:user_id).filled(:string)
    required(:status).filled(:string)
  end
  
  metric :counter,
         name: 'orders_total',
         tags: [:status]  # ← Only safe labels (status)
  # ← Inherits: forbidden_metric_labels (user_id blocked!)
end
```

**Tag extractors (aggregation):**

```ruby
# app/events/user_action.rb
module Events
  class UserAction < E11y::Event::Base
    schema do
      required(:user_id).filled(:string)
      required(:action_type).filled(:string)
    end
    
    # ✨ Event-level tag extractors (aggregate user_id → segment)
    metric :counter,
           name: 'user_actions_total',
           tags: [:user_segment, :action_type],
           tag_extractors: {
             user_segment: ->(event) {
               user = User.find(event.payload[:user_id])
               user.segment  # 'free', 'paid', 'enterprise'
             }
           },
           cardinality_limit: 30  # 3 segments × 10 actions
  end
end
```

**Conventions for cardinality (sensible defaults):**

```ruby
# Convention: Default cardinality limit = 100 series per metric
# Convention: Common forbidden labels auto-blocked

# Zero-config event (uses conventions):
class Events::OrderCreated < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:status).filled(:string)
  end
  
  metric :counter,
         name: 'orders_total',
         tags: [:status]  # ← Safe (low cardinality)
  # ← Auto: cardinality_limit = 100 (default)
  # ← Auto: order_id blocked (common forbidden label)
end

# Override convention:
class Events::OrderCreated < E11y::Event::Base
  schema do; required(:order_id).filled(:string); end
  
  metric :counter,
         name: 'orders_total',
         tags: [:status],
         cardinality_limit: 50  # ← Override: 50 (not 100)
end
```

**Precedence (event-level overrides global):**

```ruby
# Global config (infrastructure):
E11y.configure do |config|
  config.cardinality_protection do
    forbidden_labels :user_id, :order_id  # Global defaults
    default_cardinality_limit 100
  end
end

# Event-level config (overrides global):
class Events::UserAction < E11y::Event::Base
  forbidden_metric_labels :user_id, :session_id  # ← Override: adds session_id
  default_cardinality_limit 50  # ← Override: 50 (not 100)
end
```

**Benefits:**
- ✅ Locality of behavior (cardinality rules next to schema)
- ✅ DRY via inheritance/presets
- ✅ Sensible defaults (100 series limit)
- ✅ Easy to override when needed
- ✅ Tag extractors co-located with metrics

---

## 🎯 The 4-Layer Defense System

### Layer Processing Flow

> **Implementation:** See [ADR-002 Section 4.1: Four-Layer Defense](../ADR-002-metrics-yabeda.md#41-four-layer-defense) for detailed architecture.

**🔑 Critical: Layers execute SEQUENTIALLY (not simultaneously).**

Each label is processed through all 4 layers **in order**. Once a layer makes a decision (DROP/KEEP), subsequent layers may be skipped:

```
┌────────────────────────────────────────────────────────┐
│ Incoming Event: { user_id: 123, status: 'paid' }      │
└────────────────────────────────────────────────────────┘
                        ↓
         ┌──────────────────────────────┐
         │ For EACH label in event:     │
         └──────────────────────────────┘
                        ↓
    ╔═══════════════════════════════════════╗
    ║ Layer 1: Universal Denylist           ║
    ║ Q: Is label in FORBIDDEN_LABELS?      ║
    ╚═══════════════════════════════════════╝
                        ↓
           ┌───────────┴───────────┐
           │ YES                   │ NO
           ↓                       ↓
      ❌ DROP                 Continue
      (stop here)                  ↓
                        ╔═══════════════════════════════════════╗
                        ║ Layer 2: Safe Allowlist               ║
                        ║ Q: Is label in SAFE_LABELS?           ║
                        ╚═══════════════════════════════════════╝
                                    ↓
                       ┌───────────┴───────────┐
                       │ YES                   │ NO
                       ↓                       ↓
                  ✅ KEEP                 Continue
            (skip Layer 3-4)                   ↓
                                    ╔═══════════════════════════════════════╗
                                    ║ Layer 3: Per-Metric Cardinality Limit ║
                                    ║ Q: Is cardinality < limit?             ║
                                    ╚═══════════════════════════════════════╝
                                                ↓
                                   ┌───────────┴───────────┐
                                   │ YES                   │ NO
                                   ↓                       ↓
                              ✅ KEEP                 Continue
                                                           ↓
                                                ╔═══════════════════════════════════════╗
                                                ║ Layer 4: Dynamic Action                ║
                                                ║ Execute: drop/alert/sample             ║
                                                ╚═══════════════════════════════════════╝
                                                           ↓
                                                  ❌ DROP (or alert)
```

**Example: Processing 3 labels**

```ruby
# Incoming event
Events::OrderPlaced.track(
  user_id: 'user_12345',        # ← Label 1
  status: 'paid',               # ← Label 2
  custom_field: 'special_123'   # ← Label 3
)

# Processing:

# user_id:
#   → Layer 1: in FORBIDDEN_LABELS? ✅ YES → ❌ DROP (stop, skip Layer 2-4)
#   Result: user_id not included in metric

# status:
#   → Layer 1: in FORBIDDEN_LABELS? ❌ NO → continue
#   → Layer 2: in SAFE_LABELS? ✅ YES → ✅ KEEP (skip Layer 3-4)
#   Result: status='paid' included in metric

# custom_field:
#   → Layer 1: in FORBIDDEN_LABELS? ❌ NO → continue
#   → Layer 2: in SAFE_LABELS? ❌ NO → continue
#   → Layer 3: cardinality < limit? ❌ NO (150 > 100) → continue
#   → Layer 4: action = :drop → ❌ DROP
#   Result: custom_field not included in metric

# Final metric:
# order_placed_total{status="paid"} 1
```

**Key Properties:**

1. **Early Exit Optimization:** If Layer 1 drops a label, Layers 2-4 never execute (performance optimization).
2. **Safe Labels Fast Path:** Layer 2 approval skips expensive cardinality tracking (Layers 3-4).
3. **Fallback to Dynamic Action:** Only labels that pass Layer 1-2 but fail Layer 3 reach Layer 4.
4. **Order Matters:** Changing layer order breaks the protection model (e.g., Layer 3 before Layer 1 = wrong).

**Performance Impact:**

| Scenario | Layers Executed | Time | Example |
|---|---|---|---|
| Forbidden label | Layer 1 only | ~0.001ms | `user_id` |
| Safe label | Layer 1-2 | ~0.002ms | `status`, `method` |
| New label (under limit) | Layer 1-3 | ~0.01ms | `custom_field` (90th unique value) |
| Overflow label | Layer 1-4 | ~0.02ms | `custom_field` (101st unique value) |

**Why Sequential?**

```ruby
# ❌ WRONG: Parallel layer execution
# Problem: All layers execute simultaneously, wasting CPU on labels already dropped

# ✅ CORRECT: Sequential execution
# Benefit: Early exit saves 75% CPU for forbidden labels
```

---

### Layer 1: Denylist (Hard Block)

> **⚠️ CRITICAL: Adapter-Specific Filtering**  
> **Implementation:** See [ADR-002 Section 4.2: Layer 1 - Universal Denylist](../ADR-002-metrics-yabeda.md#42-layer-1-universal-denylist) for detailed architecture.
>
> **Cardinality protection (denylist/allowlist) applies ONLY to metrics adapters (Yabeda/Prometheus), NOT to other adapters:**
>
> | Adapter Type | Denylist Applied? | Why? |
> |---|---|---|
> | **Metrics (Yabeda/Prometheus)** | ✅ YES | High-cardinality labels cause memory explosion in time-series databases (1M labels = 1GB RAM). |
> | **Logs (Loki)** | Optional | Loki labels = event_name + severity (low cardinality). Payload (user_id, etc.) in log line. Optional `enable_cardinality_protection` for labels. |
> | **Errors (Sentry)** | ❌ NO | Sentry needs full context for debugging. High cardinality is acceptable for error tracking. |
> | **Audit (File/PostgreSQL)** | ❌ NO | Audit trails require complete, unfiltered data for compliance. |
>
> **Example:**
> ```ruby
> # Event with user_id (forbidden for metrics)
> Events::UserAction.track(user_id: "12345", action: "login")
>
> # What happens:
> # ✅ Prometheus: { action="login" }                    ← user_id DROPPED
> # ✅ Loki:       { user_id="12345", action="login" }   ← user_id PRESERVED
> # ✅ Sentry:     { user_id="12345", action="login" }   ← user_id PRESERVED
> # ✅ Audit:      { user_id="12345", action="login" }   ← user_id PRESERVED
> ```
>
> **Why This Matters:**
> - ✅ **Metrics stay safe:** Prometheus won't OOM due to cardinality explosion
> - ✅ **Debugging stays rich:** Loki/Sentry get full context for troubleshooting
> - ✅ **Compliance stays intact:** Audit logs remain complete and unfiltered
> - ✅ **Best of both worlds:** Safety for metrics + completeness for logs/errors

**Avoid these as metric tags:** user_id, customer_id, order_id, session_id, trace_id, url, ip_address, timestamp.

---

### Layer 2: Safe Labels

**Rule of thumb:**
- ✅ **< 10 values** - Always safe
- 🟡 **10-100 values** - Usually OK, monitor
- 🔴 **> 100 values** - High risk, aggregate!

---

### Layer 3: Per-Metric Limits

**Yabeda adapter supports cardinality limits** via its config. Use low-cardinality tags in event-level metrics.

#### Thread Safety

> **Implementation:** See [ADR-002 Section 4.4: Layer 3 - Per-Metric Cardinality Limits](../ADR-002-metrics-yabeda.md#44-layer-3-per-metric-cardinality-limits) for detailed architecture.
> 
> **Sources:**
> - [Ruby Hash thread safety - Stack Overflow](https://stackoverflow.com/questions/22674498/thread-safety-for-hashes-in-ruby)
> - [Mutex performance overhead - Stack Overflow](https://stackoverflow.com/questions/9761899/why-does-this-code-run-slower-with-multiple-threads-even-on-a-multi-core-mach)
> - [Thread Safety with Mutexes - GoRails](https://gorails.com/episodes/thread-safety-with-mutexes-in-ruby)
> - [Understanding Ruby Threads and Concurrency - Better Stack](https://betterstack.com/community/guides/scaling-ruby/threads-and-concurrency/)

**🔒 Critical: CardinalityTracker is thread-safe by design.**

E11y applications typically handle hundreds of concurrent requests, each potentially emitting events with labels. The `CardinalityTracker` uses a **mutex** to ensure thread-safe tracking of unique label values across concurrent requests.

**Why Thread Safety Matters:**

```ruby
# Scenario: 3 concurrent requests tracking same metric
Thread 1: track('orders_total', status: 'paid')     # ← Same time
Thread 2: track('orders_total', status: 'pending')  # ← Same time
Thread 3: track('orders_total', status: 'paid')     # ← Same time

# Without mutex:
# - Race condition: both Thread 1 & 3 might think 'paid' is new
# - Tracker corruption: @trackers hash modified by 3 threads simultaneously
# - Lost updates: Thread 2's 'pending' might be overwritten
# - RESULT: Incorrect cardinality counts, potential memory leaks

# With mutex (actual E11y implementation):
# - Thread 1 acquires lock → adds 'paid' → releases (1/limit)
# - Thread 2 acquires lock → adds 'pending' → releases (2/limit)
# - Thread 3 acquires lock → sees 'paid' exists → releases (2/limit)
# - RESULT: Correct cardinality = 2
```

**Implementation:**

```ruby
# From ADR-002 Section 4.4
class CardinalityTracker
  def initialize(limit: 100)
    @limit = limit
    @trackers = {}  # { metric_name: { label_name: Set[values] } }
    @mutex = Mutex.new  # ← Thread safety
  end
  
  def check_and_track(metric_name, label_name, value)
    @mutex.synchronize do  # ← Only 1 thread executes this block at a time
      @trackers[metric_name] ||= {}
      @trackers[metric_name][label_name] ||= Set.new
      
      tracker = @trackers[metric_name][label_name]
      
      if tracker.include?(value)
        true  # Already seen
      elsif tracker.size < @limit
        tracker.add(value)
        true  # Added, under limit
      else
        false  # Rejected, over limit
      end
    end
  end
end
```

**Performance Impact:**

⚠️ **Reality Check:** Mutex synchronization has measurable overhead, especially under high concurrency:

- **Single-threaded baseline:** Hash lookup + Set operation ~0.001ms (1 microsecond)
- **With Mutex (low contention):** ~0.005-0.01ms (5-10 microseconds) - 5-10x slower
- **With Mutex (high contention):** Can degrade significantly due to cache coherency overhead

**Why slower?** Each `@mutex.synchronize` call forces CPU to:
1. Acquire lock (coordinate with other cores)
2. Access shared state from RAM (not L1/L2 cache) - ~100x slower than cache
3. Release lock (notify waiting threads)

**Mitigation:** E11y minimizes overhead by:
- Keeping critical section **extremely short** (hash lookup + set add only)
- Using simple data structures (Hash + Set, not complex objects)
- Avoiding I/O or heavy computation inside `synchronize` block

**Real-world impact:** For most applications (100-1000 concurrent requests), mutex overhead is acceptable compared to the catastrophic cost of NOT having thread safety (corrupted cardinality counts, memory leaks, incorrect metrics)

**Monitoring Thread Contention:**

If you suspect mutex contention is becoming a bottleneck, monitor these indicators:

```ruby
# Built-in E11y metrics (no extra config needed)
e11y_cardinality_checks_total          # Total cardinality checks
e11y_cardinality_checks_duration_seconds  # Duration histogram

# Prometheus query to detect contention:
# If p99 latency >> p50, likely contention
histogram_quantile(0.99, rate(e11y_cardinality_checks_duration_seconds_bucket[5m]))
  /
histogram_quantile(0.50, rate(e11y_cardinality_checks_duration_seconds_bucket[5m]))
# Ratio > 10 = high contention
```

**If contention becomes critical:**
- Consider using `Concurrent::Map` from concurrent-ruby gem (lock-free for reads)
- Shard cardinality trackers by metric name (separate mutex per metric)
- Profile with `ruby-prof` to identify exact bottleneck

---

### Layer 4: Dynamic Monitoring

**Auto-detect and alert on high cardinality:**

```ruby
E11y.configure do |config|
  config.metrics do
    cardinality_monitoring do
      # === THRESHOLDS ===
      warn_threshold 0.7      # Alert at 70% of limit
      critical_threshold 0.9  # Critical alert at 90%
      
      # === AUTO-ADJUSTMENT ===
      auto_adjust do
        enabled true
        threshold 0.8         # Trigger at 80%
        action :aggregate     # Auto-switch to aggregate strategy
        notify :slack         # Notify team
      end
      
      # === REPORTING ===
      report_interval 1.minute    # Check every minute
      top_violators_count 10      # Track top 10 high-cardinality metrics
      
      # === ALERTS ===
      on_high_cardinality do |metric_name, current, limit|
        Rails.logger.warn(
          "[E11y] High cardinality: #{metric_name} at #{current}/#{limit}"
        )
        
        # Send to Slack
        SlackNotifier.notify(
          channel: '#observability',
          message: "⚠️ Metric #{metric_name} cardinality: #{current}/#{limit}"
        )
      end
    end
  end
end
```

#### Action Selection Guide

> **Implementation:** See [ADR-002 Section 4.5: Layer 4 - Dynamic Actions](../ADR-002-metrics-yabeda.md#45-layer-4-dynamic-actions) for detailed architecture.

**🎯 When cardinality limit is exceeded, which action should you choose?**

Use this decision tree to select the right strategy:

```
┌─────────────────────────────────────┐
│ Cardinality Limit Exceeded          │
└─────────────────────────────────────┘
                 ↓
        ┌────────────────┐
        │ Critical to    │ ← Question 1
        │ investigate?   │
        └────────────────┘
         ↙            ↘
       YES             NO
        ↓               ↓
   ┌─────────┐   ┌──────────────┐
   │ ALERT   │   │ Can group    │ ← Question 2
   │         │   │ values into  │
   │ + Drop  │   │ categories?  │
   └─────────┘   └──────────────┘
        ↓          ↙          ↘
        │        YES           NO
        │         ↓             ↓
        │    ┌─────────┐   ┌───────┐
        │    │ RELABEL │   │ DROP  │
        │    └─────────┘   └───────┘
        ↓         ↓             ↓
   PagerDuty   Reduced      Silent
   Alert      Cardinality   Removal
```

**Decision Matrix:**

| Action | When to Use | Signal Preserved | Cardinality | Example |
|--------|-------------|------------------|-------------|---------|
| **DROP** | Label not important for analysis | ❌ None (label removed entirely) | 1 (label dropped) | Drop `request_id`, `trace_id` from metrics (keep in logs) |
| **RELABEL** | Clear categories exist (e.g., status codes, paths) | ✅✅✅ High (grouped into buckets) | 5-10 (category count) | `http_status: 200` → `status_class: 2xx` |
| **ALERT** | Unexpected high cardinality, needs investigation | ❌ None + 🚨 (label dropped + ops alerted) | 1 (label dropped) | Sudden spike in unique `customer_id` values |

**Practical Examples:**

**1. DROP - Default for non-critical labels**
```ruby
# ❌ BAD: request_id creates 1M unique metrics
counter_for pattern: 'api.request',
            tags: [:request_id, :endpoint]  # request_id = high cardinality!

# ✅ GOOD: Drop request_id from metrics
counter_for pattern: 'api.request',
            tags: [:endpoint]  # Only low-cardinality tags

cardinality_limit_for 'api.request' do
  max_cardinality 100
  overflow_strategy :drop  # Silent drop if exceeded
end

# Result: request_id still in logs/traces, just not in metrics
```

**2. RELABEL - Best for known categories**
```ruby
# ❌ BAD: 200 unique HTTP status codes
counter_for pattern: 'http.response',
            tags: [:http_status]  # 200, 201, 204, 400, 401, 403, ...

# ✅ GOOD: Relabel to status classes (5 categories)
counter_for pattern: 'http.response',
            tags: [:status_class],
            tag_extractors: {
              status_class: ->(event) {
                status = event.payload[:http_status].to_i
                case status
                when 100..199 then '1xx'
                when 200..299 then '2xx'
                when 300..399 then '3xx'
                when 400..499 then '4xx'
                when 500..599 then '5xx'
                else 'unknown'
                end
              }
            }

# Result: 200 values → 5 categories (99% cardinality reduction)
```

**3. ALERT - For unexpected cardinality spikes**
```ruby
# Payment events should have stable cardinality
cardinality_limit_for 'payments.processed' do
  max_cardinality 50  # Expect ~10 payment methods
  overflow_strategy :alert  # Alert if exceeded
  overflow_sample_rate 0.1  # Sample 10% of overflow events
end

# Scenario: Suddenly 1000 unique payment_method values
# → Alert sent to PagerDuty
# → Label dropped from metrics
# → Ops investigates (possible bug, data corruption, attack)
```

**When NOT to use each action:**

| Action | DON'T Use When | Why |
|--------|---------------|-----|
| DROP | Label is critical for debugging | You lose all visibility into this dimension |
| RELABEL | No clear categories exist | Arbitrary bucketing (e.g., hash-based) loses signal |
| ALERT | High cardinality is expected | Alert fatigue, ops team overwhelmed |

**Common Patterns:**

```ruby
# Pattern 1: DROP non-critical identifiers
# request_id, session_id, trace_id → DROP (keep in logs)
overflow_strategy :drop

# Pattern 2: RELABEL known enums
# http_status, country_code, user_tier → RELABEL (aggregate)
tag_extractors: { status_class: ->(e) { ... } }

# Pattern 3: ALERT on unexpected cardinality
# payment_method, product_sku → ALERT (should be stable)
overflow_strategy :alert
```

**Monitoring Your Decisions:**

```ruby
# Track how often each action triggers
Yabeda.e11y_internal.cardinality_actions_total.values
# => { action: 'drop', metric: 'api.requests' } => 42
# => { action: 'alert', metric: 'payments.processed' } => 1

# Prometheus query:
rate(e11y_cardinality_actions_total{action="alert"}[5m])
# → If >0, investigate what's causing unexpected cardinality
```

---

## 💻 Advanced Techniques

### 1. Aggregation (Best ROI - 99% Reduction)

> **Note:** This section describes **relabeling/normalization** (e.g., `user_id` → `user_segment`) via `tag_extractors`, which is different from `overflow_strategy`. Aggregation reduces cardinality **before** metrics are created, while overflow handling (`drop`/`alert`) deals with exceeding limits **after** creation. See [ADR-002 Section 4.5](../ADR-002-metrics-yabeda.md#45-cardinality-protection) for implementation details.

**Problem:** 1M users = 1M metric series

**Solution:** Aggregate to segments

```ruby
# ❌ BAD: 1,000,000 users = 1,000,000 series
counter_for pattern: 'user.action',
            tags: [:user_id]

# ✅ GOOD: 3 segments = 3 series (99.9997% reduction!)
counter_for pattern: 'user.action',
            tags: [:user_segment],
            tag_extractors: {
              user_segment: ->(event) {
                user_id = event.payload[:user_id]
                user = User.find_by(id: user_id)
                user&.segment || 'unknown'  # 'free', 'paid', 'enterprise'
              }
            }

# Result:
# user_actions_total{user_segment="free"} 500000
# user_actions_total{user_segment="paid"} 400000
# user_actions_total{user_segment="enterprise"} 100000
```

**Common aggregation strategies:**

| High-Cardinality Field | Aggregate To | Values |
|------------------------|--------------|--------|
| `user_id` (1M) | `user_segment` | free, paid, enterprise (3) |
| `order_id` (10M) | `order_status` | pending, paid, shipped (4) |
| `ip_address` (100k) | `country` | US, UK, DE, FR (50) |
| `version` (1000) | `major_version` | 1.x, 2.x, 3.x (3) |
| `url` (10k) | `endpoint_pattern` | /api/users/:id (100) |

---

### 2. Relabeling & Normalization

**Transform high-cardinality values to low-cardinality:**

```ruby
counter_for pattern: 'http.request',
            tags: [:http_status, :endpoint, :version],
            tag_extractors: {
              # Aggregate status codes: 200..299 → 2xx
              http_status: ->(event) {
                status = event.payload[:status]
                "#{status / 100}xx"  # 200 → "2xx", 404 → "4xx"
              },
              
              # Normalize endpoints: /api/users/123 → /api/users/:id
              endpoint: ->(event) {
                path = event.payload[:path]
                path.gsub(/\/\d+/, '/:id')  # Replace numbers with :id
              },
              
              # Major version only: 2.5.7234 → 2.x
              version: ->(event) {
                version = event.payload[:version]
                major = version.split('.').first
                "#{major}.x"
              }
            }

# Before relabeling: 50 status codes × 1000 endpoints × 100 versions = 5M series
# After relabeling: 5 status groups × 100 patterns × 10 major versions = 5k series
# Reduction: 99.9%
```

---

### 3. Exemplars (Best of Both Worlds)

**Low-cardinality metrics + high-cardinality exemplars:**

```ruby
counter_for pattern: 'order.paid',
            name: 'orders_paid_total',
            # LOW-cardinality labels (stored for all events)
            tags: [:currency, :payment_method],
            # HIGH-cardinality exemplars (sampled, not stored as labels)
            exemplars: {
              user_id: ->(event) { event.payload[:user_id] },
              order_id: ->(event) { event.payload[:order_id] },
              trace_id: ->(event) { event.trace_id }
            },
            exemplar_sample_rate: 0.01  # Sample 1% of events

# Result in Prometheus:
# Metric: orders_paid_total{currency="USD",payment_method="stripe"} 1234
# Exemplar (sampled): {user_id="12345",order_id="ord_abc",trace_id="xyz"}
#
# Benefits:
# - Low cardinality for storage/query (2 labels)
# - High cardinality context available (3 exemplars, sampled)
# - Can jump from metric to trace via trace_id
```

---

### 4. Streaming Aggregation

**Aggregate BEFORE sending to metrics backend:**

```ruby
E11y.configure do |config|
  config.metrics do
    # Pre-aggregate high-cardinality dimensions
    streaming_aggregation do
      # Aggregate all http.* events
      aggregate pattern: 'http.*' do
        # Keep these dimensions
        keep_dimensions [:controller, :action, :http_status]
        
        # Drop these dimensions (aggregate out)
        drop_dimensions [:user_id, :session_id, :ip_address]
        
        # Aggregation window
        window 10.seconds
        
        # Flush interval
        flush_interval 5.seconds
      end
    end
  end
end

# How it works:
# 1. Events buffered for 10 seconds
# 2. Aggregate by keep_dimensions (drop others)
# 3. Flush aggregated metrics every 5 seconds
# 4. Result: 90% fewer metric updates
```

---

### 5. Tiered Retention

**Different retention for different cardinality:**

```ruby
E11y.configure do |config|
  config.metrics do
    # High-cardinality: short retention
    retention_for pattern: 'http.request.*',
                  cardinality: :high,
                  duration: 1.hour,
                  aggregation: :mean  # Downsample to mean after 1 hour
    
    # Low-cardinality: long retention
    retention_for pattern: 'orders.paid.*',
                  cardinality: :low,
                  duration: 90.days,
                  aggregation: :none  # Keep raw data
    
    # Auto-classify by actual cardinality
    auto_classify_retention true
    high_cardinality_threshold 1_000
    low_cardinality_threshold 100
  end
end

# Result:
# - High-cardinality metrics: 1 hour raw + 30 days aggregated
# - Low-cardinality metrics: 90 days raw
# - Cost savings: 70% reduction in storage
```

---

### 6. Universal Cardinality Protection (C04 Resolution) ⚠️ CRITICAL

> **⚠️ CRITICAL: C04 Conflict Resolution - Cardinality Protection for ALL Backends**  
> **See:** [ADR-009 Section 8](../ADR-009-cost-optimization.md#8-cardinality-protection-c04-resolution--critical) for detailed architecture and cost impact analysis.  
> **Problem:** Original UC-013 cardinality protection applied ONLY to Yabeda/Prometheus metrics, but NOT to OpenTelemetry span attributes or Loki log labels. High-cardinality values (`user_id`, `order_id`) bypassed protection and caused cost explosions in OTLP backends (Datadog, Honeycomb).  
> **Solution:** Universal `CardinalityFilter` middleware applies protection to **ALL backends** (Yabeda, OpenTelemetry, Loki) with optional per-backend overrides.

**The Problem - Inconsistent Cardinality Protection:**

Before C04 resolution, cardinality protection was **metrics-only**:

```ruby
# ❌ BEFORE C04: Inconsistent protection (cost explosion!)
E11y.configure do |config|
  config.metrics do
    # Cardinality protection for Yabeda/Prometheus ✅
    forbidden_labels :user_id, :order_id
    cardinality_limit_for 'orders_total', max: 100
  end
  
  # OpenTelemetry: NO cardinality protection! ❌
  config.opentelemetry do
    enabled true
    export_traces true  # Spans include ALL attributes
  end
end

# Event tracking (10,000 unique users):
10_000.times do |i|
  Events::OrderCreated.track(
    order_id: "order-#{i}",  # ← 10,000 unique values!
    user_id: "user-#{i}",    # ← 10,000 unique values!
    amount: 99.99
  )
end

# Result:
# ✅ Prometheus: order_id/user_id PROTECTED (only 100 unique values tracked)
# ❌ OpenTelemetry: order_id/user_id NOT PROTECTED (all 10,000 exported!)
# ❌ Loki: order_id/user_id NOT PROTECTED (index bloat!)

# Cost impact:
# - Datadog: $0.10/span × 10,000 = $1,000/day = $30,000/month 💸
# - Backend cardinality limit exceeded → data loss
```

**The Solution - Universal Cardinality Protection:**

After C04 resolution, protection applies to **ALL backends**:

```ruby
# ✅ AFTER C04: Unified protection (cost savings!)
E11y.configure do |config|
  # GLOBAL cardinality protection (applies to ALL backends)
  config.cardinality_protection do
    enabled true
    max_unique_values 100  # Conservative default (Prometheus-safe)
    protected_labels [:user_id, :order_id, :session_id, :tenant_id]
  end
  
  # Optional: Per-backend overrides (if needed)
  config.adapters do
    # Yabeda: Use global settings (default)
    yabeda do
      cardinality_protection.inherit_from :global
    end
    
    # OpenTelemetry: Higher limits OK (OTLP backends handle more)
    opentelemetry do
      cardinality_protection do
        max_unique_values 1000  # OTLP backends can handle more
        protected_labels [:user_id, :order_id]  # Subset of global
      end
    end
    
    # Loki: Use global settings
    loki do
      cardinality_protection.inherit_from :global
    end
  end
end

# Same event tracking (10,000 unique users):
10_000.times do |i|
  Events::OrderCreated.track(
    order_id: "order-#{i}",
    user_id: "user-#{i}",
    amount: 99.99
  )
end

# Result:
# ✅ Prometheus: order_id/user_id → 100 + [OTHER] (protected)
# ✅ OpenTelemetry: order_id/user_id → 1000 + [OTHER] (protected)
# ✅ Loki: order_id/user_id → 100 + [OTHER] (protected)

# Cost impact:
# - Datadog: $0.01/span × 10,000 = $100/day = $3,000/month ✅
# - Monthly savings: $27,000 💰 (90% reduction!)
```

**Configuration Examples:**

**1. Production: Strict Limits (Cost-Sensitive)**

```ruby
# config/environments/production.rb
E11y.configure do |config|
  config.cardinality_protection do
    enabled true
    max_unique_values 100  # Prometheus-safe
    protected_labels [:user_id, :order_id, :session_id, :tenant_id, :ip_address]
  end
  
  # OTLP can handle more (optional override)
  config.adapters.opentelemetry do
    cardinality_protection.max_unique_values 1000
  end
end
```

**2. Development: No Limits (Full Visibility)**

```ruby
# config/environments/development.rb
E11y.configure do |config|
  config.cardinality_protection.enabled false  # Unlimited cardinality
end
```

**3. Staging: Moderate Limits (Balance Cost vs Debugging)**

```ruby
# config/environments/staging.rb
E11y.configure do |config|
  config.cardinality_protection do
    enabled true
    max_unique_values 500  # More than prod, less than unlimited
    protected_labels [:user_id, :order_id]
  end
  
  # OTLP backend can handle even more
  config.adapters.opentelemetry do
    cardinality_protection.max_unique_values 1000
  end
end
```

**Per-Backend Cardinality Budgets:**

Different backends have different cardinality tolerance:

| Backend | Recommended `max_unique_values` | Why |
|---------|----------------------------------|-----|
| **Prometheus (Yabeda)** | 100 | Time-series DB, high memory usage per series |
| **OpenTelemetry (Datadog)** | 1000 | Columnar storage, better cardinality handling |
| **Loki** | 100 | Label cardinality affects index size & query performance |
| **Sentry** | Unlimited | Error tracking needs full context (not cost-sensitive) |
| **Audit (PostgreSQL)** | Unlimited | Compliance requires complete data |

**Example: Different Limits per Backend**

```ruby
E11y.configure do |config|
  # Global default (applies to Yabeda, Loki)
  config.cardinality_protection do
    enabled true
    max_unique_values 100
    protected_labels [:user_id, :order_id]
  end
  
  # OpenTelemetry: 10× higher limit
  config.adapters.opentelemetry do
    cardinality_protection.max_unique_values 1000
  end
  
  # Sentry: No limit (need full context for debugging)
  config.adapters.sentry do
    cardinality_protection.enabled false
  end
  
  # Audit: No limit (compliance)
  config.adapters.audit do
    cardinality_protection.enabled false
  end
end

# Event with high-cardinality fields:
Events::OrderCreated.track(
  order_id: "order-12345",  # High-cardinality
  user_id: "user-67890",    # High-cardinality
  amount: 99.99
)

# Result per backend:
# Prometheus: order_id/user_id → [OTHER] (after 100 unique values)
# OpenTelemetry: order_id/user_id → [OTHER] (after 1000 unique values)
# Loki: order_id/user_id → [OTHER] (after 100 unique values)
# Sentry: order_id="order-12345", user_id="user-67890" (full context)
# Audit: order_id="order-12345", user_id="user-67890" (full context)
```

**Monitoring Cardinality Protection:**

Track cardinality protection effectiveness:

```ruby
# Metrics:
e11y_cardinality_filtered_labels_total{backend="all",label="user_id"}
e11y_cardinality_unique_values{label="order_id"}
e11y_cardinality_limit_breached_total{label="session_id"}

# Prometheus queries:

# 1. Cardinality protection rate (% of labels filtered)
rate(e11y_cardinality_filtered_labels_total[5m])
/
rate(e11y_events_tracked_total[5m]) * 100

# 2. Labels at risk (approaching limit)
e11y_cardinality_unique_values
/ 
100 * 100 > 80  # 80% of max_unique_values (100)

# 3. Top high-cardinality labels
topk(10,
  sum by (label) (
    rate(e11y_cardinality_filtered_labels_total[1h])
  )
)

# 4. Cost savings estimate (assume $0.10 per unique span attribute)
sum(rate(e11y_cardinality_filtered_labels_total[1d])) * 0.10
# Result: Daily $ saved
```

**Trade-offs:**

| Aspect | Pros | Cons | Mitigation |
|--------|------|------|------------|
| **Unified protection** | Consistent across all backends | One size doesn't fit all backends | Per-backend overrides (`max_unique_values`) |
| **[OTHER] grouping** | Prevents cost explosion | Loses context for debugging | Log original values at debug level |
| **Global config** | Simple, DRY | May not fit all backend limits | Environment-specific: prod=100, staging=500, dev=unlimited |
| **max_unique_values 100** | Conservative, safe for Prometheus | May be too strict for OTLP backends | Per-backend override: OTLP=1000, Yabeda=100 |

**Cost Impact:**

Real-world example from C04 analysis:

```
BEFORE C04 (no OTLP protection):
- 10,000 orders/day with unique order_id
- Datadog pricing: $0.10/span with high-cardinality attributes
- Daily cost: $1,000
- Monthly cost: $30,000 ❌

AFTER C04 (universal protection):
- Same 10,000 orders/day
- Cardinality protected: 1000 unique + [OTHER]
- Datadog pricing: $0.01/span with low-cardinality attributes
- Daily cost: $100
- Monthly cost: $3,000 ✅
- Monthly savings: $27,000 💰 (90% reduction!)
```

---

## 📊 Self-Monitoring Metrics

**E11y tracks its own cardinality:**

```ruby
# === CARDINALITY METRICS ===
e11y_internal_metric_cardinality{metric="user_actions_total"}  # Current unique series
e11y_internal_metric_cardinality_limit{metric="user_actions_total"}  # Configured limit
e11y_internal_metric_cardinality_ratio{metric="user_actions_total"}  # current/limit (0-1)

# === OVERFLOW METRICS ===
e11y_internal_metric_overflow_count{metric="user_actions_total"}  # Times limit exceeded
e11y_internal_metric_overflow_events_total{metric="user_actions_total"}  # Events via overflow path

# === VIOLATION METRICS ===
e11y_internal_forbidden_label_violations_total{label="user_id"}  # Denylist violations
e11y_internal_label_value_count{metric="orders_paid_total",label="currency"}  # Unique values per label

# === AGGREGATE METRICS ===
e11y_internal_high_cardinality_metrics_total  # Metrics above threshold
e11y_internal_aggregated_series_total  # Series using "_other" bucket
```

**Prometheus alerting:**

```yaml
# config/prometheus/alerts.yml
groups:
  - name: e11y_cardinality
    rules:
      # Alert at 80% of limit
      - alert: E11yHighCardinality
        expr: e11y_internal_metric_cardinality_ratio > 0.8
        for: 5m
        annotations:
          summary: "Metric {{ $labels.metric }} at {{ $value }}% of limit"
          description: "Consider aggregating or increasing limit"
      
      # Alert on overflow
      - alert: E11yCardinalityOverflow
        expr: rate(e11y_internal_metric_overflow_events_total[5m]) > 10
        for: 2m
        annotations:
          summary: "Metric {{ $labels.metric }} overflowing ({{ $value }} events/sec)"
      
      # Alert on forbidden label usage
      - alert: E11yForbiddenLabelViolation
        expr: increase(e11y_internal_forbidden_label_violations_total[1h]) > 0
        annotations:
          summary: "Forbidden label {{ $labels.label }} used!"
          description: "Check metric configuration"
```

---

## 💻 Implementation Examples

### Example 1: User Analytics (Safe)

```ruby
# ❌ BEFORE: High cardinality
counter_for pattern: 'user.action',
            tags: [:user_id, :action]  # 1M users × 10 actions = 10M series

# ✅ AFTER: Low cardinality
counter_for pattern: 'user.action',
            tags: [:user_segment, :action, :cohort],
            tag_extractors: {
              user_segment: ->(e) {
                User.find(e.payload[:user_id]).segment  # free, paid, enterprise
              },
              cohort: ->(e) {
                User.find(e.payload[:user_id]).cohort_month  # 2024-01, 2024-02
              }
            }
# Result: 3 segments × 10 actions × 12 cohorts = 360 series (99.996% reduction!)
```

---

### Example 2: HTTP Request Tracking

```ruby
counter_for pattern: 'http.request',
            tags: [:controller_action, :http_status_group, :region],
            tag_extractors: {
              # Normalize controller#action
              controller_action: ->(e) {
                "#{e.payload[:controller]}##{e.payload[:action]}"
              },
              
              # Aggregate status codes
              http_status_group: ->(e) {
                status = e.payload[:status]
                case status
                when 200..299 then '2xx'
                when 300..399 then '3xx'
                when 400..499 then '4xx'
                when 500..599 then '5xx'
                else 'unknown'
                end
              }
            }

# With exemplars for debugging
histogram_for pattern: 'http.request',
              value: ->(e) { e.duration_ms / 1000.0 },
              tags: [:controller_action, :http_status_group],
              exemplars: {
                trace_id: ->(e) { e.trace_id },
                user_id: ->(e) { e.context[:user_id] }
              },
              exemplar_sample_rate: 0.01  # 1% sampling
```

---

### Example 3: E-Commerce Orders

```ruby
# Orders by status, payment method, country
counter_for pattern: 'order.paid',
            name: 'orders_paid_total',
            tags: [:status, :payment_method, :country, :amount_bucket],
            tag_extractors: {
              # Bucket amounts
              amount_bucket: ->(e) {
                amount = e.payload[:amount]
                case amount
                when 0..50 then 'small'
                when 51..200 then 'medium'
                when 201..1000 then 'large'
                else 'xlarge'
                end
              },
              
              # Aggregate country to region
              country: ->(e) {
                Country.find(e.payload[:country_code]).region  # US, EU, APAC
              }
            }

# Cardinality:
# 4 statuses × 5 payment methods × 3 regions × 4 amount buckets = 240 series ✅
```

---

## 🧪 Testing

```ruby
# spec/e11y/cardinality_spec.rb
RSpec.describe 'E11y Cardinality Protection' do
  describe 'forbidden labels' do
    it 'raises error on forbidden label usage' do
      E11y.configure do |config|
        config.metrics do
          forbidden_labels :user_id
          enforcement :strict
        end
      end
      
      expect {
        E11y.configure do |config|
          config.metrics do
            counter_for pattern: 'test',
                        tags: [:user_id]
          end
        end
      }.to raise_error(E11y::ForbiddenLabelError, /user_id/)
    end
  end
  
  describe 'cardinality limits' do
    it 'drops overflow events' do
      E11y.configure do |config|
        config.metrics do
          cardinality_limit_for 'test_metric', max: 3
          overflow_strategy :drop
        end
      end
      
      # Track 5 unique label values (exceeds limit of 3)
      5.times do |i|
        Events::TestEvent.track(category: "cat_#{i}")
      end
      
      metric = Yabeda.test_metric
      # Expect only 3 unique (2 dropped)
      expect(metric.values.keys.size).to eq(3)
      
      # Verify drop counter incremented
      expect(Yabeda.e11y_internal.metric_overflow_events_total).to be > 0
    end
  end
  
  describe 'self-monitoring' do
    it 'tracks cardinality ratio' do
      E11y.configure do |config|
        config.metrics do
          cardinality_limit_for 'test_metric', max: 100
        end
      end
      
      50.times { |i| Events::TestEvent.track(category: "cat_#{i}") }
      
      ratio = Yabeda.e11y_internal.metric_cardinality_ratio.get(
        { metric: 'test_metric' }
      )
      expect(ratio).to eq(0.5)  # 50/100
    end
  end
end
```

---

## 💡 Best Practices

### ✅ DO

**1. Use aggregation for high-cardinality dimensions**
```ruby
# ✅ GOOD
tags: [:user_segment]  # free, paid, enterprise (3 values)
```

**2. Monitor cardinality proactively**
```ruby
# ✅ GOOD
cardinality_monitoring do
  warn_threshold 0.7
  alert_channel '#observability'
end
```

**3. Use exemplars for debugging**
```ruby
# ✅ GOOD
exemplars: { trace_id: ->(e) { e.trace_id } }
exemplar_sample_rate: 0.01
```

---

### ❌ DON'T

**1. Don't use unbounded identifiers as labels**
```ruby
# ❌ BAD
tags: [:user_id, :order_id, :session_id]
```

**2. Don't ignore cardinality warnings**
```ruby
# ❌ BAD: Ignoring production alerts
# [E11y WARNING] Metric at 95% of limit
# → Action: Aggregate or increase limit immediately!
```

**3. Don't use timestamps as labels**
```ruby
# ❌ BAD
tags: [:timestamp, :created_at]
# Use histogram buckets instead!
```

---

## 💰 Cost Calculator

```ruby
# Calculate your potential savings
def calculate_cardinality_cost(
  services:,
  dimensions:,
  values_per_dimension:,
  cost_per_series: 0.068  # Datadog pricing
)
  total_series = dimensions.map { |d| values_per_dimension[d] }.reduce(:*)
  total_series *= services
  
  monthly_cost = total_series * cost_per_series
  
  {
    total_series: total_series,
    monthly_cost: monthly_cost,
    yearly_cost: monthly_cost * 12
  }
end

# Example: E-commerce app
before = calculate_cardinality_cost(
  services: 50,
  dimensions: [:user_id, :product_id, :action],
  values_per_dimension: {
    user_id: 100_000,
    product_id: 10_000,
    action: 10
  }
)
# => 50B series, $3.4M/month! 😱

after = calculate_cardinality_cost(
  services: 50,
  dimensions: [:user_segment, :product_category, :action],
  values_per_dimension: {
    user_segment: 3,
    product_category: 20,
    action: 10
  }
)
# => 30k series, $2k/month ✅
# SAVINGS: $3.4M - $2k = $3.398M/month (99.94% reduction!)
```

---

## ❓ Frequently Asked Questions

> **Technical Details:** See [ADR-002 Section 11: FAQ & Critical Clarifications](../ADR-002-metrics-yabeda.md#11-faq--critical-clarifications) for architectural rationale.

### Q1: Does cardinality protection apply to all my logs and metrics?

**A: No, only to metrics (Prometheus/Yabeda). Logs keep full data.**

This is a common source of confusion. Let's clarify:

```ruby
# Same event, different treatment:
Events::OrderCreated.track(
  user_id: '123',      # High-cardinality
  status: 'paid',      # Low-cardinality
  amount: 99.99
)
```

**What happens:**

| Adapter | `user_id` | `status` | `amount` | Why |
|---------|-----------|----------|----------|-----|
| **Prometheus** | ❌ Dropped (denylist) | ✅ Kept | ❌ Dropped (value, not label) | Cardinality protection active |
| **Loki (logs)** | ✅ Kept | ✅ Kept | ✅ Kept | No cardinality limits |
| **Sentry** | ✅ Kept | ✅ Kept | ✅ Kept | Full context needed for debugging |
| **Audit** | ✅ Kept | ✅ Kept | ✅ Kept | Compliance requires full data |

**Why this design?**

- **Metrics (Prometheus):** Cardinality explosions are catastrophic (cost, performance, query failures)
- **Logs (Loki):** High-cardinality fields are fine (indexed differently, stored cheaper)
- **Error tracking (Sentry):** Need full context to debug issues
- **Audit trails:** Regulatory compliance requires complete data

**Practical implication:**

```ruby
# ✅ This is SAFE and RECOMMENDED:
Events::ApiRequest.track(
  request_id: SecureRandom.uuid,  # High-cardinality, but OK!
  endpoint: '/api/users',
  user_id: current_user.id
)

# Result:
# - Metrics: only endpoint tracked (request_id/user_id dropped)
# - Logs: full payload with request_id for debugging
# - Best of both worlds!
```

---

### Q2: Are the 4 layers checked simultaneously or one-by-one?

**A: One-by-one (sequential waterfall), not simultaneously.**

This is critical to understand for debugging and configuration:

```
Processing order for each label:

┌─────────────────────────────────────────┐
│ 1. Layer 1: Denylist Check              │
│    ↓ In denylist? → DROP, stop here     │
│    ↓ Not in denylist? → Continue to L2  │
└─────────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│ 2. Layer 2: Allowlist Check             │
│    ↓ In allowlist? → KEEP, stop here    │
│    ↓ Not in allowlist? → Continue to L3 │
└─────────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│ 3. Layer 3: Cardinality Limit           │
│    ↓ Under limit? → KEEP, stop here     │
│    ↓ Over limit? → Continue to L4       │
└─────────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│ 4. Layer 4: Dynamic Action              │
│    ↓ Apply configured action:           │
│      drop / alert / relabel              │
└─────────────────────────────────────────┘
```

**Example trace through all layers:**

```ruby
# Event: { user_id: '123', status: 'paid', tier: 'premium' }

# Label: user_id
#   Layer 1: ✅ in FORBIDDEN_LABELS → ❌ DROP (stop here, never reaches L2-L4)

# Label: status
#   Layer 1: ✅ not in FORBIDDEN_LABELS → continue to L2
#   Layer 2: ✅ in SAFE_LABELS → ✅ KEEP (stop here, skip L3-L4)

# Label: tier
#   Layer 1: ✅ not in FORBIDDEN_LABELS → continue to L2
#   Layer 2: ✅ not in SAFE_LABELS → continue to L3
#   Layer 3: ❌ cardinality 150 > limit 100 → continue to L4
#   Layer 4: ✅ action=drop → ❌ DROP

# Final metric:
# orders_total{status="paid"} 1
# (user_id and tier dropped)
```

**Why sequential (not simultaneous)?**

- **Performance:** Early exit on denylist (L1) avoids expensive cardinality checks (L3)
- **Predictability:** Clear precedence (denylist > allowlist > cardinality > action)
- **Debuggability:** Easy to trace which layer made the decision

---

### Q3: What should I do when I hit a cardinality limit?

**A: Use relabeling if possible, otherwise drop the label.**

Use this decision process:

**Step 1: Can you group values into clear categories?**

```ruby
# ✅ YES - Use relabeling (best signal preservation):

# Example 1: HTTP status codes (200, 201, 204...) → status classes (2xx, 3xx...)
tag_extractors: {
  status_class: ->(event) {
    case event.payload[:http_status].to_i
    when 200..299 then '2xx'
    when 400..499 then '4xx'
    when 500..599 then '5xx'
    end
  }
}
# Result: 50 values → 5 categories (90% reduction)

# Example 2: Paths (/users/123, /users/456...) → endpoint patterns (/users/:id)
tag_extractors: {
  endpoint: ->(event) {
    event.payload[:path].gsub(/\d+/, ':id')
  }
}
# Result: Infinite values → ~100 endpoints
```

**Step 2: Is this label critical for alerts/dashboards?**

```ruby
# ❌ NO - Just drop it (keep in logs):
cardinality_limit_for 'api.requests' do
  max_cardinality 100
  overflow_strategy :drop  # Silent drop
end

# Result: request_id removed from metrics, but still in logs for debugging
```

**Step 3: Is this an unexpected cardinality spike?**

```ruby
# ✅ YES - Alert ops team:
cardinality_limit_for 'payments.processed' do
  max_cardinality 50
  overflow_strategy :alert  # Alert + drop
end

# Scenario: Suddenly 1000 unique payment_method values
# → Alert sent to PagerDuty/Slack
# → Ops investigates (possible bug, attack, data corruption)
```

**Common patterns:**

| Your Situation | Recommended Action | Example |
|----------------|-------------------|---------|
| Label not needed for analysis | **DROP** | `request_id`, `trace_id` → keep in logs only |
| Clear categories exist | **RELABEL** | `http_status: 200` → `status_class: 2xx` |
| Cardinality should be stable | **ALERT** | Payment methods suddenly spike to 1000 values |
| Need debugging context | **Keep in logs** | Drop from metrics, query logs when debugging |

**Anti-pattern to avoid:**

```ruby
# ❌ DON'T: Keep high-cardinality labels in metrics
counter_for pattern: 'api.request',
            tags: [:endpoint, :user_id]  # user_id = millions of values!

# ✅ DO: Drop from metrics, keep in logs
counter_for pattern: 'api.request',
            tags: [:endpoint]  # Only low-cardinality tags

# user_id still available in Loki logs for debugging:
# 2024-01-15 10:23:45 | api.request | endpoint=/api/users user_id=123 status=200
```

---

### Q4: How do I debug which layer dropped my label?

**A: Check E11y's built-in cardinality metrics:**

```ruby
# See which labels are being dropped:
Yabeda.e11y_internal.cardinality_dropped_labels_total.values
# => { metric: 'api_requests_total', label: 'user_id', reason: 'denylist' } => 1523
# => { metric: 'api_requests_total', label: 'session_id', reason: 'limit_exceeded' } => 42

# See which layer made the decision:
# - reason: 'denylist' → Layer 1
# - reason: 'not_in_allowlist' → Layer 2 (if allowlist configured)
# - reason: 'limit_exceeded' → Layer 3
```

**Prometheus queries for debugging:**

```promql
# Which metrics are dropping labels most frequently?
topk(10, rate(e11y_cardinality_dropped_labels_total[5m]))

# Which labels are being dropped?
sum by (label, reason) (e11y_cardinality_dropped_labels_total)

# Alert on unexpected drops:
rate(e11y_cardinality_dropped_labels_total{reason="limit_exceeded"}[5m]) > 10
```

**Development/staging debugging:**

```ruby
# Temporarily log all cardinality decisions:
E11y.configure do |config|
  config.metrics.cardinality_protection do
    debug_mode true  # Logs every decision (verbose!)
  end
end

# Output:
# [E11y] Cardinality: KEEP label 'status' (Layer 2: allowlist)
# [E11y] Cardinality: DROP label 'user_id' (Layer 1: denylist)
# [E11y] Cardinality: DROP label 'tier' (Layer 3: limit 150/100, action=drop)
```

---

## 🔒 Validations (NEW - v1.1)

> **🎯 Pattern:** Validate cardinality configuration at class load time.

### Cardinality Limit Validation

**Problem:** Invalid cardinality limits → metric explosion.

**Solution:** Validate cardinality_limit is positive integer:

```ruby
# Gem implementation (automatic):
def self.cardinality_limit(max)
  unless max.is_a?(Integer) && max > 0 && max <= 10_000
    raise ArgumentError, "cardinality_limit must be 1..10_000, got: #{max.inspect}"
  end
  self._cardinality_limit = max
end

# Result:
class Events::UserAction < E11y::Event::Base
  metric :counter, name: 'actions_total', cardinality_limit: -100
  # ← ERROR: "cardinality_limit must be 1..10_000, got: -100"
end
```

### Forbidden Labels Validation

**Problem:** Using high-cardinality labels → cost explosion.

**Solution:** Validate against denylist:

```ruby
# Gem implementation (automatic):
FORBIDDEN_LABELS = [:user_id, :order_id, :session_id, :trace_id, :request_id]

def self.metric(type, name:, tags:, **options)
  forbidden = tags & FORBIDDEN_LABELS
  if forbidden.any?
    raise ArgumentError, "Forbidden high-cardinality labels: #{forbidden.join(', ')}. Use aggregation instead!"
  end
  # ...
end

# Result:
class Events::UserAction < E11y::Event::Base
  metric :counter, name: 'actions_total', tags: [:user_id, :action_type]
  # ← ERROR: "Forbidden high-cardinality labels: user_id. Use aggregation instead!"
end
```

### Tag Extractors Validation

**Problem:** Tag extractors returning nil → metric gaps.

**Solution:** Validate extractor return values:

```ruby
# Gem implementation (runtime):
def extract_tag_value(event, extractor)
  value = extractor.call(event)
  if value.nil? || value.to_s.empty?
    raise ArgumentError, "Tag extractor returned nil/empty for event: #{event.name}"
  end
  value.to_s
end
```

---

## 🌍 Environment-Specific Cardinality Protection (NEW - v1.1)

> **🎯 Pattern:** Different cardinality limits per environment.

### Example 1: Stricter Limits in Production

```ruby
class Events::UserAction < E11y::Event::Base
  schema do
    required(:user_id).filled(:string)
    required(:action_type).filled(:string)
  end
  
  # Environment-specific cardinality limits
  metric :counter,
         name: 'user_actions_total',
         tags: [:user_segment, :action_type],
         cardinality_limit: Rails.env.production? ? 100 : 1_000,
         tag_extractors: {
           user_segment: ->(event) {
             if Rails.env.production?
               # Production: strict aggregation
               User.find(event.payload[:user_id]).segment  # 'free', 'paid', 'enterprise'
             else
               # Dev/test: allow user_id for debugging
               event.payload[:user_id]
             end
           }
         }
end
```

### Example 2: Feature Flag for Cardinality Protection

```ruby
class Events::ApiRequest < E11y::Event::Base
  schema do
    required(:endpoint).filled(:string)
    required(:user_id).filled(:string)
  end
  
  # Enable cardinality protection only when flag is on
  if ENV['ENABLE_CARDINALITY_PROTECTION'] == 'true'
    metric :counter,
           name: 'api_requests_total',
           tags: [:endpoint_group],  # Aggregated
           cardinality_limit: 50,
           tag_extractors: {
             endpoint_group: ->(event) {
               # Group /users/123 → /users/:id
               event.payload[:endpoint].gsub(/\/\d+/, '/:id')
             }
           }
  else
    # Dev: no aggregation
    metric :counter,
           name: 'api_requests_total',
           tags: [:endpoint]  # Full endpoint
  end
end
```

---

## 📊 Precedence Rules for Cardinality Protection (NEW - v1.1)

> **🎯 Pattern:** Cardinality configuration precedence (most specific wins).

### Precedence Order (Highest to Lowest)

```
1. Event-level explicit config (highest priority)
   ↓
2. Preset module config
   ↓
3. Base class config (inheritance)
   ↓
4. Convention-based defaults (100 series)
   ↓
5. Global config (lowest priority)
```

### Example: Mixing Inheritance + Presets for Cardinality

```ruby
# Global config (lowest priority)
E11y.configure do |config|
  config.metrics do
    cardinality_limit 1_000  # Default for all metrics
    forbidden_labels :user_id, :session_id
  end
end

# Base class (medium priority)
class Events::BaseUserEvent < E11y::Event::Base
  # Common cardinality protection
  metric :counter,
         name: 'user_events_total',
         tags: [:user_segment, :event_type],
         cardinality_limit: 100,  # Override global (stricter)
         tag_extractors: {
           user_segment: ->(event) { User.find(event.payload[:user_id]).segment }
         }
end

# Preset module (higher priority)
module E11y::Presets::MetricSafeEvent
  extend ActiveSupport::Concern
  included do
    # Override cardinality limit
    metric :counter,
           name: 'safe_events_total',
           tags: [:severity],
           cardinality_limit: 10  # Very strict!
  end
end

# Event (highest priority)
class Events::UserLogin < Events::BaseUserEvent
  include E11y::Presets::MetricSafeEvent
  
  # Override preset (looser limit)
  metric :counter,
         name: 'user_logins_total',
         tags: [:user_segment, :login_method],
         cardinality_limit: 50  # Override preset
  
  # Final config:
  # - cardinality_limit: 50 (event-level override)
  # - tags: [:user_segment, :login_method] (event-level)
  # - tag_extractors: inherited from base
end
```

### Precedence Rules Table

| Config | Global | Convention | Base Class | Preset | Event-Level | Winner |
|--------|--------|------------|------------|--------|-------------|--------|
| `cardinality_limit` | `1_000` | `100` | `100` | `10` | `50` | **`50`** (event) |
| `tags` | - | - | `[:user_segment, :event_type]` | `[:severity]` | `[:user_segment, :login_method]` | **`[:user_segment, :login_method]`** (event) |
| `forbidden_labels` | `[:user_id, :session_id]` | - | - | - | - | **`[:user_id, :session_id]`** (global) |

### Convention-Based Defaults

**Convention:** If no cardinality_limit specified → default `100 series`:

```ruby
class Events::ApiRequest < E11y::Event::Base
  metric :counter, name: 'api_requests_total', tags: [:status]
  # ← Auto: cardinality_limit = 100 (convention!)
end
```

---

## 📚 Related Use Cases

- **[UC-003: Event Metrics](./UC-003-event-metrics.md)** - Metrics in event classes
- **[UC-008: OpenTelemetry Integration](./UC-008-opentelemetry-integration.md)** - OTLP cardinality protection (C04)
- **[UC-015: Cost Optimization](./UC-015-cost-optimization.md)** - Reduce observability costs

---

## 🎯 Summary

### E11y's Competitive Advantage

**ONLY Ruby gem with production-grade cardinality protection:**

| Feature | Yabeda | OTel Ruby | AppSignal | E11y |
|---------|--------|-----------|-----------|------|
| Forbidden labels | ❌ | ❌ | ❌ | ✅ |
| Cardinality limits | ❌ | Basic (2000) | Vendor-specific | ✅ 4-layer defense |
| Auto-aggregation | ❌ | ❌ | ❌ | ✅ |
| Exemplars | ❌ | ❌ | ❌ | ✅ |
| Self-monitoring | ❌ | Partial | Vendor-specific | ✅ 8+ metrics |
| Cost reduction | 0% | ~30% | Vendor lock-in | **99%** |

**Real-world impact:** $67,320/month savings (99% reduction)

---

**Document Version:** 1.1 (Unified DSL)  
**Last Updated:** January 16, 2026  
**Status:** ✅ Complete - Consistent with DSL-SPECIFICATION.md v1.1.0

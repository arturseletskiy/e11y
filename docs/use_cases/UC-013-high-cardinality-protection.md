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
# ❌ CATASTROPHIC: Using user_id as metric label
E11y.configure do |config|
  config.metrics do
    counter_for pattern: 'user.action',
                name: 'user_actions_total',
                tags: [:user_id, :action_type]  # ← 💸💸💸
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

### E11y Solution

**4-Layer Defense System + 99% Cost Reduction:**
```ruby
# ✅ SAFE: Aggregate user_id → user_segment
E11y.configure do |config|
  config.metrics do
    # Layer 1: Denylist (hard block)
    forbidden_labels :user_id, :order_id, :session_id, :trace_id
    
    # Layer 2: Safe aggregation
    counter_for pattern: 'user.action',
                name: 'user_actions_total',
                tags: [:user_segment, :action_type],  # ← 3 segments × 10 actions = 30 series
                tag_extractors: {
                  user_segment: ->(event) {
                    user = User.find(event.payload[:user_id])
                    user.segment  # 'free', 'paid', 'enterprise'
                  }
                }
    
    # Layer 3: Per-metric limits
    cardinality_limit_for 'user_actions_total', max: 100
    
    # Layer 4: Dynamic monitoring
    cardinality_monitoring do
      warn_threshold 0.7   # Alert at 70%
      auto_aggregate true  # Auto-fix if exceeded
    end
  end
end

# Result:
# - 200 services × 10 segments × 5 dimensions = 10,000 series
# - Datadog cost: $680/month
# - Savings: $67,320/month (99% reduction) ✅
```

---

## 🎯 The 4-Layer Defense System

### Layer 1: Denylist (Hard Block)

**Universal denylist - NEVER use these as labels:**

```ruby
E11y.configure do |config|
  config.metrics do
    # === UNBOUNDED IDENTIFIERS (FORBIDDEN) ===
    forbidden_labels :user_id, :customer_id, :account_id,
                     :order_id, :transaction_id, :invoice_id,
                     :session_id, :request_id, :trace_id, :span_id
    
    # === INFRASTRUCTURE (FORBIDDEN) ===
    forbidden_labels :pod_uid, :container_id, :instance_id,
                     :node_name  # If dynamic
    
    # === NETWORK/HTTP (FORBIDDEN) ===
    forbidden_labels :url,          # With query strings
                     :ip_address,
                     :user_agent,
                     :hostname      # If ephemeral
    
    # === TIME-BASED (FORBIDDEN) ===
    forbidden_labels :timestamp, :created_at,
                     :version      # Patch-level: 2.5.7234
    
    # === ENFORCEMENT ===
    enforcement :strict  # ERROR on forbidden label usage
    # OR
    enforcement :warn    # Log warning but allow
    # OR
    enforcement :aggregate  # Auto-aggregate to "_other"
  end
end

# Usage:
counter_for pattern: 'user.action',
            tags: [:user_id]  # ← ERROR: "user_id is forbidden!"

# Development warning:
# [E11y ERROR] Metric 'user.action_total' uses forbidden label 'user_id'
# Cardinality explosion risk! Use 'user_segment' instead.
```

---

### Layer 2: Allowlist (Strict Mode)

**Only allow explicitly safe labels:**

```ruby
E11y.configure do |config|
  config.metrics do
    # Strict mode: ONLY these labels allowed
    allowed_labels_only true
    
    # === BUSINESS DIMENSIONS (< 50 values) ===
    allowed_labels :status,          # pending, paid, failed (4-10 values)
                   :payment_method,  # card, paypal (5-20 values)
                   :plan_tier        # free, pro, enterprise (3-5 values)
    
    # === INFRASTRUCTURE (< 20 values) ===
    allowed_labels :env,             # production, staging, dev (3 values)
                   :region,          # us-east, eu-west (5-20 values)
                   :cluster,         # main, backup (2-5 values)
                   :availability_zone
    
    # === HTTP/SERVICE (< 100 values) ===
    allowed_labels :http_method,     # GET, POST, PUT, DELETE (10 values)
                   :http_status_code, # 200, 404, 500 (50 values)
                   :controller_action # UsersController#show (20-100 values)
  end
end

# Usage:
counter_for pattern: 'order.paid',
            tags: [:currency]  # ← ERROR: "currency not in allowlist!"

# Must explicitly allow:
allowed_labels :currency  # USD, EUR, GBP (3-20 values)
```

**Rule of thumb:**
- ✅ **< 10 values** - Always safe
- 🟡 **10-100 values** - Usually OK, monitor
- 🔴 **> 100 values** - High risk, aggregate!

---

### Layer 3: Per-Metric Limits

**Set cardinality limits per metric:**

```ruby
E11y.configure do |config|
  config.metrics do
    # === GLOBAL DEFAULT ===
    default_cardinality_limit 1_000
    
    # === PER-METRIC LIMITS ===
    cardinality_limit_for 'http.requests' do
      max_cardinality 2_000           # Higher limit for this metric
      overflow_strategy :aggregate    # → Aggregate to "_other" bucket
      overflow_sample_rate 0.1        # Sample 10% of overflow events
    end
    
    cardinality_limit_for 'user.actions' do
      max_cardinality 500             # Lower limit
      overflow_strategy :drop         # Drop overflow events
      overflow_alert true             # Alert on overflow
    end
    
    cardinality_limit_for 'orders.paid' do
      max_cardinality 100
      overflow_strategy :aggregate
      aggregate_label '_other'        # Custom aggregate label
    end
  end
end

# How it works:
# 1. Track unique label combinations per metric
# 2. If exceeds limit:
#    - :aggregate → Group extras into "_other" label
#    - :drop → Discard event (increment drop counter)
#    - :sample → Probabilistic sampling
```

**Overflow strategies:**

| Strategy | Behavior | Use Case |
|----------|----------|----------|
| `:aggregate` | Group extras into `_other` label | Default (preserves signal) |
| `:drop` | Discard overflow events | Non-critical metrics |
| `:sample` | Probabilistic sampling | High-volume metrics |
| `:hash_bucket` | Hash to N buckets | Distributed tracing |

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

---

## 💻 Advanced Techniques

### 1. Aggregation (Best ROI - 99% Reduction)

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

### 4. Hash-Based Bucketing

**Distribute high-cardinality values into fixed buckets:**

```ruby
counter_for pattern: 'user.action',
            tags: [:user_bucket, :action_type],
            tag_extractors: {
              # 1M users → 100 buckets
              user_bucket: ->(event) {
                user_id = event.payload[:user_id]
                bucket = Digest::MD5.hexdigest(user_id.to_s).to_i(16) % 100
                "bucket_#{bucket}"
              }
            }

# Result:
# - 100 buckets × 10 action types = 1,000 series (vs 1M without bucketing)
# - 99.9% reduction
# - Can still analyze per-bucket trends
# - Useful for distributed tracing (consistent hashing)
```

---

### 5. Streaming Aggregation

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

### 6. Tiered Retention

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
    it 'aggregates overflow to _other' do
      E11y.configure do |config|
        config.metrics do
          cardinality_limit_for 'test_metric', max: 3
          overflow_strategy :aggregate
        end
      end
      
      # Track 5 unique label values (exceeds limit of 3)
      5.times do |i|
        Events::TestEvent.track(category: "cat_#{i}")
      end
      
      metric = Yabeda.test_metric
      # Expect 3 unique + 1 "_other"
      expect(metric.values.keys.size).to eq(4)
      expect(metric.values.keys).to include({ category: '_other' })
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

## 📚 Related Use Cases

- **[UC-003: Pattern-Based Metrics](./UC-003-pattern-based-metrics.md)** - Auto-generate metrics
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

**Document Version:** 1.0  
**Last Updated:** January 12, 2026  
**Status:** ✅ Complete

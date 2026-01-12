# UC-003: Pattern-Based Metrics

**Status:** Core Feature (Phase 2)  
**Complexity:** Intermediate  
**Setup Time:** 15-30 minutes  
**Target Users:** DevOps, SRE, Backend Developers

---

## 📋 Overview

### Problem Statement

**Current Approach (Manual Metrics):**
```ruby
# ❌ Manual duplication
Rails.logger.info "Order #{order.id} paid"
OrderMetrics.increment('orders.paid.total', tags: { currency: 'USD' })
OrderMetrics.observe('orders.paid.amount', order.amount, tags: { currency: 'USD' })

# Problems:
# - Duplication (log + metrics)
# - Inconsistent naming (order vs orders)
# - Typos in tags (curency vs currency)
# - Missing tags (forgot payment_method)
# - Maintenance burden (update both places)
```

### E11y Solution

**Pattern-based auto-metrics:**
```ruby
# 1. Track event ONCE
Events::OrderPaid.track(
  order_id: '123',
  amount: 99.99,
  currency: 'USD',
  payment_method: 'stripe'
)

# 2. Configure patterns ONCE (global config)
E11y.configure do |config|
  config.metrics do
    # Auto-create counter
    counter_for pattern: 'order.paid',
                name: 'orders.paid.total',
                tags: [:currency, :payment_method]
    
    # Auto-create histogram
    histogram_for pattern: 'order.paid',
                  name: 'orders.paid.amount',
                  value: ->(e) { e.payload[:amount] },
                  tags: [:currency],
                  buckets: [10, 50, 100, 500, 1000, 5000]
  end
end

# 3. Get metrics automatically
# ✅ orders_paid_total{currency="USD",payment_method="stripe"} = 1
# ✅ orders_paid_amount_bucket{currency="USD",le="100"} = 1
```

---

## 🎯 Use Case Scenarios

### Scenario 1: Multi-Domain Metrics

**Business domains:** Orders, Users, Payments

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.metrics do
    # === GLOBAL METRICS ===
    # All events counter
    counter_for pattern: '*',
                name: 'business_events.total',
                tags: [:event_name, :severity]
    
    # === ORDERS DOMAIN ===
    counter_for pattern: 'order.*',
                name: 'orders.events.total',
                tags: [:event_name]
    
    histogram_for pattern: 'order.paid',
                  name: 'orders.amount',
                  value: ->(e) { e.payload[:amount] },
                  tags: [:currency],
                  buckets: [10, 50, 100, 500, 1000, 5000, 10000]
    
    # Success rate (special metric)
    success_rate_for pattern: 'order.*',
                     name: 'orders.success_rate'
    
    # === USERS DOMAIN ===
    counter_for pattern: 'user.*',
                name: 'users.events.total',
                tags: [:event_name]
    
    # Funnel metric
    funnel_for pattern: 'user.*',
               name: 'users.registration_funnel',
               steps: ['registration.started', 'email.verified', 'profile.completed', 'first.login']
    
    # === PAYMENTS DOMAIN ===
    counter_for pattern: 'payment.*',
                name: 'payments.events.total',
                tags: [:event_name, :payment_method]
    
    histogram_for pattern: 'payment.succeeded',
                  name: 'payments.duration_ms',
                  value: ->(e) { e.duration_ms },
                  tags: [:payment_method],
                  buckets: [100, 250, 500, 1000, 2000, 5000]
    
    success_rate_for pattern: 'payment.*',
                     name: 'payments.success_rate',
                     tags: [:payment_method]
  end
end
```

**Result in Prometheus:**
```promql
# Global
business_events_total{event_name="order.paid",severity="success"} 1234

# Orders
orders_events_total{event_name="order.paid"} 1234
orders_amount_sum{currency="USD"} 123456.78
orders_success_rate 0.998  # 99.8%

# Users
users_events_total{event_name="registration.started"} 5000
users_registration_funnel{step="email.verified"} 4500  # 90% conversion
users_registration_funnel{step="profile.completed"} 4000  # 80% conversion

# Payments
payments_events_total{event_name="payment.succeeded",payment_method="stripe"} 1200
payments_duration_ms_bucket{payment_method="stripe",le="500"} 1100  # p95 < 500ms
payments_success_rate{payment_method="stripe"} 0.997  # 99.7%
```

---

### Scenario 2: Cardinality-Safe Labels

**Problem:** High-cardinality labels (user_id, order_id) cause metric explosions

**Solution:** Pattern-based extraction with aggregation

```ruby
E11y.configure do |config|
  config.metrics do
    # ❌ BAD: user_id as label (1M users = 1M series)
    # counter_for pattern: 'user.action',
    #             tags: [:user_id]  # ← DON'T DO THIS!
    
    # ✅ GOOD: Aggregate to user_segment (3 values = 3 series)
    counter_for pattern: 'user.action',
                name: 'users.actions.total',
                tags: [:action_type, :user_segment],
                tag_extractors: {
                  user_segment: ->(event) {
                    # Aggregate user_id → user_segment
                    user = User.find(event.payload[:user_id])
                    user.segment  # 'free', 'paid', 'enterprise'
                  }
                }
    
    # ✅ GOOD: Bucket amounts (not exact values)
    histogram_for pattern: 'order.paid',
                  name: 'orders.amount_bucket',
                  value: ->(e) {
                    # Bucket: small, medium, large
                    amount = e.payload[:amount]
                    case amount
                    when 0..50 then 'small'
                    when 51..200 then 'medium'
                    else 'large'
                    end
                  },
                  tags: [:currency]
  end
end
```

**Result:**
```promql
# Before (BAD): 1M series
users_actions_total{user_id="user_1",action_type="click"} 1
users_actions_total{user_id="user_2",action_type="click"} 1
# ... 1 million more

# After (GOOD): 6 series (3 segments × 2 action types)
users_actions_total{user_segment="free",action_type="click"} 500000
users_actions_total{user_segment="paid",action_type="click"} 400000
users_actions_total{user_segment="enterprise",action_type="click"} 100000
```

---

### Scenario 3: Custom Metric Types

**Built-in metric types:**
- `counter_for` - monotonically increasing
- `histogram_for` - distribution (with buckets)
- `gauge_for` - point-in-time value
- `success_rate_for` - ratio of :success / (:success + :error)
- `funnel_for` - multi-step conversion tracking

```ruby
E11y.configure do |config|
  config.metrics do
    # === COUNTER ===
    counter_for pattern: 'email.sent',
                name: 'emails.sent.total',
                tags: [:template, :status]
    
    # === HISTOGRAM ===
    histogram_for pattern: 'api.request',
                  name: 'api.request.duration_seconds',
                  value: ->(e) { e.duration_ms / 1000.0 },
                  tags: [:controller, :action],
                  buckets: [0.01, 0.05, 0.1, 0.5, 1.0, 5.0]
    
    # === GAUGE (current state) ===
    gauge_for pattern: 'queue.size',
              name: 'sidekiq.queue.size',
              value: ->(e) { e.payload[:size] },
              tags: [:queue_name]
    
    # === SUCCESS RATE (auto-calculated) ===
    success_rate_for pattern: 'payment.*',
                     name: 'payments.success_rate',
                     tags: [:payment_method]
    # Automatically:
    # - Counts events with severity :success
    # - Counts events with severity :error
    # - Calculates: success / (success + error)
    
    # === FUNNEL (multi-step conversion) ===
    funnel_for pattern: 'checkout.*',
               name: 'checkout.funnel',
               steps: [
                 'checkout.cart_viewed',
                 'checkout.shipping_info_entered',
                 'checkout.payment_info_entered',
                 'checkout.order_placed'
               ]
    # Automatically tracks conversion at each step
  end
end
```

---

## 🔧 Configuration API

### Basic Pattern Syntax

```ruby
# Exact match
counter_for pattern: 'order.paid'

# Wildcard (any suffix)
counter_for pattern: 'order.*'

# Multi-level wildcard
counter_for pattern: 'api.*.request'

# Multiple patterns
counter_for patterns: ['order.paid', 'order.refunded']
```

### Tag Extraction

```ruby
counter_for pattern: 'order.*',
            name: 'orders.events.total',
            tags: [:currency, :payment_method],
            tag_extractors: {
              # Simple: extract from payload
              currency: ->(e) { e.payload[:currency] },
              
              # Complex: aggregate/transform
              payment_method: ->(e) {
                method = e.payload[:payment_method]
                method == 'apple_pay' ? 'mobile' : method
              },
              
              # From context
              region: ->(e) { e.context[:region] }
            }
```

### Conditional Metrics

```ruby
# Only create metric if condition met
counter_for pattern: 'order.*',
            name: 'high_value_orders.total',
            if: ->(event) { event.payload[:amount] > 1000 },
            tags: [:currency]

# Different metrics based on condition
counter_for pattern: 'user.signup',
            name: ->(event) {
              event.payload[:plan] == 'free' ? 'users.free.total' : 'users.paid.total'
            }
```

### Value Extraction

```ruby
# Simple: extract field
histogram_for pattern: 'order.paid',
              value: ->(e) { e.payload[:amount] }

# Transform: convert units
histogram_for pattern: 'api.request',
              value: ->(e) { e.duration_ms / 1000.0 }  # ms → seconds

# Aggregate: bucket values
histogram_for pattern: 'order.paid',
              value: ->(e) {
                amount = e.payload[:amount]
                case amount
                when 0..50 then 25      # Small: avg 25
                when 51..200 then 125   # Medium: avg 125
                else 500                # Large: avg 500
                end
              }
```

---

## 📊 Advanced Use Cases

### Percentile Tracking

```ruby
# Track p50, p95, p99 latency
histogram_for pattern: 'api.request',
              name: 'api.request.duration_seconds',
              value: ->(e) { e.duration_ms / 1000.0 },
              buckets: [0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0, 5.0],
              tags: [:controller, :action]

# Query in Prometheus
histogram_quantile(0.50, rate(api_request_duration_seconds_bucket[5m]))  # p50
histogram_quantile(0.95, rate(api_request_duration_seconds_bucket[5m]))  # p95
histogram_quantile(0.99, rate(api_request_duration_seconds_bucket[5m]))  # p99
```

### Multi-Dimensional Aggregation

```ruby
# Break down by multiple dimensions
counter_for pattern: 'order.paid',
            name: 'orders.paid.total',
            tags: [:currency, :payment_method, :country, :plan_tier]

# Query in Prometheus (flexible slicing)
sum(orders_paid_total{currency="USD"})  # By currency
sum(orders_paid_total{payment_method="stripe"})  # By payment method
sum(orders_paid_total{currency="USD",payment_method="stripe"})  # Combined
sum by (country) (orders_paid_total)  # Group by country
```

### Time-Based Metrics

```ruby
# Track events by time-of-day
counter_for pattern: 'user.login',
            name: 'users.logins.total',
            tags: [:hour_of_day],
            tag_extractors: {
              hour_of_day: ->(e) { e.timestamp.hour }
            }

# Track events by day-of-week
counter_for pattern: 'order.paid',
            name: 'orders.paid.total',
            tags: [:day_of_week],
            tag_extractors: {
              day_of_week: ->(e) { e.timestamp.strftime('%A') }  # Monday, Tuesday, ...
            }
```

---

## 💡 Best Practices

### ✅ DO

**1. Keep cardinality low (<100 unique combinations per label)**
```ruby
# ✅ GOOD: status has 4 values
tags: [:status]  # pending, paid, shipped, delivered

# ❌ BAD: user_id has 1M values
tags: [:user_id]  # DON'T!
```

**2. Use meaningful metric names**
```ruby
# ✅ GOOD: Clear, follows Prometheus conventions
name: 'orders.paid.total'
name: 'api.request.duration_seconds'
name: 'payments.success_rate'

# ❌ BAD: Vague, non-standard
name: 'counter1'
name: 'latency'
name: 'stuff'
```

**3. Tag consistently across domains**
```ruby
# ✅ GOOD: Consistent tags
tags: [:currency]  # All financial events
tags: [:plan_tier]  # All user events
tags: [:region]  # All geo events

# ❌ BAD: Inconsistent
tags: [:curr]  # Some events
tags: [:currency]  # Other events
```

**4. Use appropriate metric types**
```ruby
# ✅ GOOD: Counter for cumulative events
counter_for pattern: 'order.paid'

# ✅ GOOD: Histogram for distributions
histogram_for pattern: 'api.request', value: ->(e) { e.duration_ms }

# ✅ GOOD: Gauge for point-in-time values
gauge_for pattern: 'queue.size', value: ->(e) { e.payload[:size] }
```

---

### ❌ DON'T

**1. Don't use high-cardinality tags**
```ruby
# ❌ BAD: Will create millions of series
tags: [:user_id, :order_id, :session_id]

# ✅ GOOD: Aggregate
tags: [:user_segment]  # free, paid, enterprise (3 values)
```

**2. Don't create duplicate metrics**
```ruby
# ❌ BAD: Same metric twice
counter_for pattern: 'order.paid', name: 'orders.total'
counter_for pattern: 'order.*', name: 'orders.total'  # Duplicate!

# ✅ GOOD: One metric per pattern
counter_for pattern: 'order.*', name: 'orders.events.total'
```

**3. Don't ignore buckets for histograms**
```ruby
# ❌ BAD: Default buckets may not fit your data
histogram_for pattern: 'api.request', value: ->(e) { e.duration_ms }

# ✅ GOOD: Explicit buckets for your scale
histogram_for pattern: 'api.request',
              value: ->(e) { e.duration_ms },
              buckets: [10, 50, 100, 500, 1000, 5000]  # milliseconds
```

---

## 🧪 Testing

```ruby
# spec/e11y/metrics_spec.rb
RSpec.describe 'E11y Metrics' do
  before do
    E11y.configure do |config|
      config.metrics do
        counter_for pattern: 'order.paid',
                    name: 'orders.paid.total',
                    tags: [:currency]
      end
    end
  end
  
  it 'creates counter metric from event' do
    # Track event
    Events::OrderPaid.track(
      order_id: '123',
      amount: 99.99,
      currency: 'USD'
    )
    
    # Verify metric was created
    metric = Yabeda.orders.paid.total
    expect(metric.values).to include(
      { currency: 'USD' } => 1
    )
  end
  
  it 'aggregates multiple events' do
    3.times do
      Events::OrderPaid.track(
        order_id: SecureRandom.uuid,
        amount: rand(100),
        currency: 'USD'
      )
    end
    
    metric = Yabeda.orders.paid.total
    expect(metric.values[{ currency: 'USD' }]).to eq(3)
  end
end
```

---

## 📚 Related Use Cases

- **[UC-002: Business Event Tracking](./UC-002-business-event-tracking.md)** - Event definitions
- **[UC-013: High Cardinality Protection](./UC-013-high-cardinality-protection.md)** - Prevent metric explosions

---

**Document Version:** 1.0  
**Last Updated:** January 12, 2026  
**Status:** ✅ Complete

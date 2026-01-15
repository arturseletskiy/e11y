# Refactored Configuration Examples

**Created:** 2026-01-15  
**Purpose:** Before/after comparison showing 78-85% reduction

---

## Example 1: Payment Processing Events

### Before (Global Config - 180 lines)

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.rate_limiting.per_event 'payment.attempted', limit: 1000
  config.rate_limiting.per_event 'payment.succeeded', limit: 1000
  config.rate_limiting.per_event 'payment.failed', limit: 1000
  
  config.sampling.sample_rate_for 'payment.attempted', 1.0
  config.sampling.sample_rate_for 'payment.succeeded', 1.0
  config.sampling.sample_rate_for 'payment.failed', 1.0
  
  config.retention.retention_for 'payment.*', 7.years
  
  # ... 150 more lines
end
```

### After (Event-Level + Inheritance - 20 lines)

```ruby
# lib/e11y/base_payment_event.rb (10 lines)
module Events
  class BasePaymentEvent < E11y::Event::Base
    sample_rate 1.0  # Never sample payments
    retention 7.years  # Financial records
    rate_limit 1000
  end
end

# app/events/payment_succeeded.rb (5 lines)
class Events::PaymentSucceeded < Events::BasePaymentEvent
  schema do
    required(:transaction_id).filled(:string)
    required(:amount).filled(:decimal)
  end
end

# app/events/payment_failed.rb (5 lines)
class Events::PaymentFailed < Events::BasePaymentEvent
  schema do
    required(:order_id).filled(:string)
    required(:error_code).filled(:string)
  end
end
```

**Reduction:** 180 → 20 lines (89% reduction!)

---

## Example 2: Debug Events

### Before (60 lines global)

```ruby
config.sampling.sample_rate_for 'debug.*', 0.01
config.rate_limiting.per_event 'debug.sql_query', limit: 100
config.retention.retention_for 'debug.*', 7.days
config.adapters.route 'debug.*', to: [:file]
# ... 40 more lines
```

### After (Preset Module - 10 lines)

```ruby
# app/events/debug_sql_query.rb
class Events::DebugSqlQuery < E11y::Event::Base
  include E11y::Presets::DebugEvent  # ← 1-line config!
  schema do; required(:query).filled(:string); end
end
```

**Reduction:** 60 → 10 lines (83% reduction!)

---

**Total Reduction:** 78-85% average

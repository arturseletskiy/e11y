# UC-002: Business Event Tracking

**Status:** Core Feature (MVP)  
**Complexity:** Beginner  
**Setup Time:** 5-15 minutes  
**Target Users:** Ruby/Rails Developers

---

## 📋 Overview

### Problem Statement

**Current Approach (Rails.logger):**
```ruby
# ❌ Unstructured, hard to query
Rails.logger.info "Order 123 paid $99.99 USD via stripe"

# ❌ Manual metrics tracking (duplication)
Rails.logger.info "Order paid: #{order.id}"
OrderMetrics.increment('orders.paid.total')
OrderMetrics.observe('orders.paid.amount', order.amount)

# Problems:
# - Free-form text → hard to parse/query
# - Manual metrics → boilerplate + bugs
# - No schema → typos, inconsistencies
# - No type safety → runtime errors
```

### E11y Solution

**Structured events with automatic metrics:**
```ruby
# ✅ Type-safe, structured, queryable
Events::OrderPaid.track(
  order_id: '123',
  amount: 99.99,
  currency: 'USD',
  payment_method: 'stripe'
)

# Result:
# 1. Structured log in ELK/Loki (JSON)
# 2. Auto-generated metrics (pattern-based)
# 3. Trace context (automatic correlation)
```

---

## 🎯 Use Case Scenarios

### Scenario 1: E-Commerce Order Flow

**Business Events:**
1. Order Created
2. Order Paid
3. Order Shipped
4. Order Delivered

**Implementation:**

```ruby
# Step 1: Define events (app/events/order_created.rb)
module Events
  class OrderCreated < E11y::Event::Base
    # Schema
    schema do
      required(:order_id).filled(:string)
      required(:user_id).filled(:string)
      required(:items_count).filled(:integer)
      required(:total_amount).filled(:decimal)
      optional(:currency).filled(:string)
    end
    
    # Default severity
    severity :success
    
    # Adapters (optional override)
    # If not specified, uses global config.adapters
    # adapters [
    #   E11y::Adapters::LokiAdapter.new(...),
    #   E11y::Adapters::SentryAdapter.new(...)
    # ]
  end
end

# Step 2: Track events in controller
class OrdersController < ApplicationController
  def create
    order = CreateOrderService.call(params)
    
    Events::OrderCreated.track(
      order_id: order.id,
      user_id: current_user.id,
      items_count: order.items.count,
      total_amount: order.total,
      currency: order.currency
    )
    
    render json: order
  end
end

# Step 3: Configure pattern-based metrics (config/initializers/e11y.rb)
E11y.configure do |config|
  config.metrics do
    # Counter: orders.created.total
    counter_for pattern: 'order.created',
                name: 'orders.created.total',
                tags: [:currency]
    
    # Histogram: orders.created.amount
    histogram_for pattern: 'order.created',
                  name: 'orders.created.amount',
                  value: ->(e) { e.payload[:total_amount] },
                  tags: [:currency],
                  buckets: [10, 50, 100, 500, 1000, 5000]
  end
end
```

**Result in Logs (Loki/ELK):**
```json
{
  "timestamp": "2026-01-12T10:30:00Z",
  "event_name": "order.created",
  "severity": "success",
  "trace_id": "abc-123-def",
  "user_id": "user_456",
  "payload": {
    "order_id": "ORD-789",
    "user_id": "user_456",
    "items_count": 3,
    "total_amount": 299.97,
    "currency": "USD"
  },
  "context": {
    "env": "production",
    "service": "api",
    "host": "web-1"
  }
}
```

**Result in Metrics (Prometheus):**
```promql
# Counter
orders_created_total{currency="USD"} 1234

# Histogram
orders_created_amount_bucket{currency="USD",le="100"} 456
orders_created_amount_bucket{currency="USD",le="500"} 1100
orders_created_amount_sum{currency="USD"} 298450.50
orders_created_amount_count{currency="USD"} 1234
```

---

### Scenario 2: User Registration Funnel

**Funnel Events:**
1. Registration Started
2. Email Verified
3. Profile Completed
4. First Login

```ruby
# Events
module Events
  class RegistrationStarted < E11y::Event::Base
    schema do
      required(:user_id).filled(:string)
      required(:source).filled(:string)  # organic, referral, ad
    end
    
    severity :info
  end
  
  class EmailVerified < E11y::Event::Base
    schema do
      required(:user_id).filled(:string)
      required(:verification_method).filled(:string)  # email_link, code
    end
    
    severity :success
  end
  
  class ProfileCompleted < E11y::Event::Base
    schema do
      required(:user_id).filled(:string)
      required(:fields_filled).array(:string)
    end
    
    severity :success
  end
  
  class FirstLogin < E11y::Event::Base
    schema do
      required(:user_id).filled(:string)
      required(:time_since_registration_hours).filled(:integer)
    end
    
    severity :success
  end
end

# Usage in controllers
class RegistrationsController < ApplicationController
  def create
    user = User.create!(registration_params)
    
    Events::RegistrationStarted.track(
      user_id: user.id,
      source: params[:utm_source] || 'organic'
    )
    
    send_verification_email(user)
    render json: user
  end
  
  def verify
    user.verify_email!
    
    Events::EmailVerified.track(
      user_id: user.id,
      verification_method: 'email_link'
    )
    
    redirect_to profile_path
  end
end

# Metrics configuration
E11y.configure do |config|
  config.metrics do
    # Funnel counter
    counter_for pattern: 'registration.*',
                name: 'registration.funnel.total',
                tags: [:event_name, :source]
    
    # Time to first login
    histogram_for pattern: 'first.login',
                  name: 'registration.time_to_first_login_hours',
                  value: ->(e) { e.payload[:time_since_registration_hours] },
                  buckets: [1, 6, 12, 24, 48, 72, 168]  # hours
  end
end
```

**Funnel Analysis (Grafana/Prometheus):**
```promql
# Conversion rate: Started → Verified
sum(registration_funnel_total{event_name="email.verified"}) /
sum(registration_funnel_total{event_name="registration.started"})
* 100

# Conversion rate: Verified → Completed
sum(registration_funnel_total{event_name="profile.completed"}) /
sum(registration_funnel_total{event_name="email.verified"})
* 100

# Median time to first login
histogram_quantile(0.5, rate(registration_time_to_first_login_hours_bucket[7d]))
```

---

### Scenario 3: Payment Processing

**Events:**
1. Payment Initiated
2. Payment Processing
3. Payment Succeeded / Failed

```ruby
module Events
  class PaymentInitiated < E11y::Event::Base
    schema do
      required(:payment_id).filled(:string)
      required(:order_id).filled(:string)
      required(:amount).filled(:decimal)
      required(:currency).filled(:string)
      required(:payment_method).filled(:string)
    end
    
    severity :info
  end
  
  class PaymentSucceeded < E11y::Event::Base
    schema do
      required(:payment_id).filled(:string)
      required(:order_id).filled(:string)
      required(:amount).filled(:decimal)
      required(:currency).filled(:string)
      required(:payment_method).filled(:string)
      required(:processor_id).filled(:string)  # Stripe charge ID
      required(:duration_ms).filled(:integer)
    end
    
    severity :success  # ← Key: success events easy to filter
  end
  
  class PaymentFailed < E11y::Event::Base
    schema do
      required(:payment_id).filled(:string)
      required(:order_id).filled(:string)
      required(:amount).filled(:decimal)
      required(:error_code).filled(:string)
      required(:error_message).filled(:string)
    end
    
    severity :error
  end
end

# Usage
class ProcessPaymentJob < ApplicationJob
  def perform(payment_id)
    payment = Payment.find(payment_id)
    
    Events::PaymentInitiated.track(
      payment_id: payment.id,
      order_id: payment.order_id,
      amount: payment.amount,
      currency: payment.currency,
      payment_method: payment.method
    )
    
    # Track with duration measurement
    Events::PaymentSucceeded.track(
      payment_id: payment.id,
      order_id: payment.order_id,
      amount: payment.amount,
      currency: payment.currency,
      payment_method: payment.method,
      processor_id: response.id
    ) do
      # Block execution time automatically measured
      response = StripeClient.charge(payment.token, payment.amount)
      payment.update!(status: 'succeeded', processor_id: response.id)
    end
    
  rescue Stripe::CardError => e
    Events::PaymentFailed.track(
      payment_id: payment.id,
      order_id: payment.order_id,
      amount: payment.amount,
      error_code: e.code,
      error_message: e.message
    )
    raise
  end
end

# Metrics
E11y.configure do |config|
  config.metrics do
    # Success rate (critical metric!)
    success_rate_for pattern: 'payment.*',
                     name: 'payments.success_rate',
                     tags: [:payment_method]
    # Auto-calculates: succeeded / (succeeded + failed) * 100
    
    # Payment duration (performance)
    histogram_for pattern: 'payment.succeeded',
                  value: ->(e) { e.duration_ms },
                  name: 'payments.duration_ms',
                  tags: [:payment_method],
                  buckets: [100, 250, 500, 1000, 2000, 5000]
    
    # Failed payments by error code (debugging)
    counter_for pattern: 'payment.failed',
                name: 'payments.failed.total',
                tags: [:error_code, :payment_method]
  end
end
```

**Alerts (Prometheus):**
```yaml
groups:
  - name: payments
    rules:
      - alert: PaymentSuccessRateLow
        expr: payments_success_rate{payment_method="stripe"} < 95
        for: 5m
        annotations:
          summary: "Payment success rate below 95%"
      
      - alert: PaymentHighLatency
        expr: histogram_quantile(0.95, rate(payments_duration_ms_bucket[5m])) > 1000
        annotations:
          summary: "Payment p95 latency >1s"
```

---

## 🔧 Configuration

### Basic Event Definition

```ruby
# app/events/user_logged_in.rb
module Events
  class UserLoggedIn < E11y::Event::Base
    # Schema definition with Dry::Schema
    schema do
      required(:user_id).filled(:string)
      required(:ip_address).filled(:string, format?: /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/)
      optional(:user_agent).filled(:string)
    end
    
    # Optional: default severity
    severity :info
  end
end

# Usage
Events::UserLoggedIn.track(
  user_id: 'user_123',
  ip_address: '192.168.1.1',
  user_agent: request.user_agent
)
```

---

### Event-Level Configuration (NEW - v1.1)

> **🎯 CONTRADICTION_01 Resolution:** Move configuration from global initializer to event classes.
>
> **Goal:** Reduce global config from 1400+ lines to <300 lines by distributing settings across events.

**Event-level DSL:**

```ruby
# app/events/order_created.rb
module Events
  class OrderCreated < E11y::Event::Base
    schema do
      required(:order_id).filled(:string)
      required(:amount).filled(:decimal)
      required(:currency).filled(:string)
    end
    
    # ✨ Event-level configuration (right next to schema!)
    severity :success
    rate_limit 1000, window: 1.second  # Max 1000 events/sec
    sample_rate 0.1                     # 10% sampling
    retention 30.days                   # Keep for 30 days
    adapters [:loki, :elasticsearch]    # Override global adapters
    
    # Metric definition
    metric :counter,
           name: 'orders.created.total',
           tags: [:currency]
  end
end
```

**Available event-level settings:**

| Setting | Type | Example | Default |
|---------|------|---------|---------|
| `severity` | Symbol | `:success, :error, :debug` | Inferred from name |
| `rate_limit` | Integer + window | `1000, window: 1.second` | 1000/sec |
| `sample_rate` | Float | `0.1` (10%) | By severity |
| `retention` | Duration | `30.days, 7.years` | By severity |
| `adapters` | Array | `[:loki, :sentry]` | By severity |
| `adapters_strategy` | Symbol | `:replace, :append` | `:replace` |

**Precedence (event-level overrides global):**

```ruby
# Global config (infrastructure):
E11y.configure do |config|
  config.register_adapter :loki, Loki.new(url: ENV['LOKI_URL'])
  config.default_adapters = [:loki]
  config.default_sample_rate = 0.1  # 10%
end

# Event-level config (overrides global):
class Events::CriticalError < E11y::Event::Base
  severity :fatal
  sample_rate 1.0  # ← Override: 100% (not 10%)
  adapters [:sentry, :pagerduty]  # ← Override: not [:loki]
end
```

---

### Event Inheritance (NEW - v1.1)

> **🎯 Pattern:** Use base classes to share common configuration across related events.

**Base class for payment events:**

```ruby
# app/events/base_payment_event.rb
module Events
  class BasePaymentEvent < E11y::Event::Base
    # Common configuration for ALL payment events
    severity :success
    rate_limit 1000
    sample_rate 1.0  # Never sample payments (high-value)
    retention 7.years  # Financial records
    adapters [:loki, :sentry, :s3_archive]
    
    # Common PII filtering
    contains_pii true
    pii_filtering do
      hashes :email, :user_id  # Pseudonymize
      allows :order_id, :amount, :currency  # Non-PII
    end
    
    # Common metric
    metric :counter,
           name: 'payments.total',
           tags: [:currency, :payment_method]
  end
end

# Inherit from base (1-2 lines per event!)
class Events::PaymentSucceeded < Events::BasePaymentEvent
  schema do
    required(:transaction_id).filled(:string)
    required(:order_id).filled(:string)
    required(:amount).filled(:decimal)
    required(:currency).filled(:string)
    required(:payment_method).filled(:string)
  end
  # ← Inherits ALL config from BasePaymentEvent!
end

class Events::PaymentFailed < Events::BasePaymentEvent
  severity :error  # ← Override base (errors, not success)
  
  schema do
    required(:transaction_id).filled(:string)
    required(:order_id).filled(:string)
    required(:amount).filled(:decimal)
    required(:error_code).filled(:string)
    required(:error_message).filled(:string)
  end
  # ← Inherits: rate_limit, sample_rate, retention, adapters, PII
end
```

**Benefits:**
- ✅ 1-2 lines per event (just schema!)
- ✅ DRY (common config shared)
- ✅ Consistency (all payments have same config)
- ✅ Easy to change (update base → all events updated)

**More base class examples:**

```ruby
# Base for audit events
module Events
  class BaseAuditEvent < E11y::Event::Base
    severity :warn
    audit_event true
    adapters [:audit_encrypted]
    # ← Auto-set by audit_event:
    #    retention = E11y.config.audit_retention (default: 7.years, configurable!)
    #    rate_limiting = false (LOCKED!)
    #    sampling = false (LOCKED!)
    
    signing do
      enabled true
      algorithm :ed25519
    end
  end
end

# Base for debug events
module Events
  class BaseDebugEvent < E11y::Event::Base
    severity :debug
    rate_limit 100
    sample_rate 0.01  # 1%
    retention 7.days
    adapters [:file]  # Local only
    contains_pii false
  end
end
```

---

### Preset Modules (NEW - v1.1)

> **🎯 Pattern:** Use preset modules for 1-line configuration includes (Rails-style concerns).

**Built-in presets:**

```ruby
# E11y provides built-in presets:
module E11y
  module Presets
    module HighValueEvent
      extend ActiveSupport::Concern
      included do
        rate_limit 10_000
        sample_rate 1.0  # Never sample
        retention 7.years
        adapters [:loki, :sentry, :s3_archive]
      end
    end
    
    module DebugEvent
      extend ActiveSupport::Concern
      included do
        severity :debug
        rate_limit 100
        sample_rate 0.01
        retention 7.days
        adapters [:file]
      end
    end
    
    module AuditEvent
      extend ActiveSupport::Concern
      included do
        audit_event true
        adapters [:audit_encrypted]
        retention 7.years
        rate_limiting false
        sampling false
      end
    end
  end
end
```

**Usage (1-line includes!):**

```ruby
class Events::PaymentProcessed < E11y::Event::Base
  include E11y::Presets::HighValueEvent  # ← All config inherited!
  
  schema do
    required(:transaction_id).filled(:string)
    required(:amount).filled(:decimal)
  end
end

class Events::DebugSqlQuery < E11y::Event::Base
  include E11y::Presets::DebugEvent  # ← All config inherited!
  
  schema do
    required(:query).filled(:string)
    required(:duration_ms).filled(:float)
  end
end
```

**Custom presets (project-specific):**

```ruby
# app/events/presets/critical_business_event.rb
module Events
  module Presets
    module CriticalBusinessEvent
      extend ActiveSupport::Concern
      included do
        severity :success
        rate_limit 5000
        sample_rate 1.0
        retention 7.years
        adapters [:loki, :elasticsearch, :s3_archive, :slack_business]
        
        metric :counter,
               name: 'critical_business_events.total',
               tags: [:event_name]
      end
    end
  end
end

# Usage:
class Events::LargeOrderPlaced < E11y::Event::Base
  include Events::Presets::CriticalBusinessEvent
  
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:decimal)
  end
end
```

---

### Conventions & Sensible Defaults (NEW - v1.1)

> **Philosophy:** "Explicit over implicit" + conventions = best balance.
>
> E11y applies **sensible defaults** to eliminate 80% of configuration.

**Convention 1: Event Name → Severity**

```ruby
# *Failed, *Error → :error
class Events::PaymentFailed < E11y::Event::Base
  # ← Auto: severity = :error
end

# *Paid, *Succeeded, *Completed → :success
class Events::OrderPaid < E11y::Event::Base
  # ← Auto: severity = :success
end

# *Started, *Processing → :info
class Events::OrderProcessing < E11y::Event::Base
  # ← Auto: severity = :info
end

# Debug* → :debug
class Events::DebugQuery < E11y::Event::Base
  # ← Auto: severity = :debug
end
```

**Convention 2: Severity → Adapters**

```ruby
# :error/:fatal → [:sentry]
# :success/:info/:warn → [:loki]
# :debug → [:file] (dev), [:loki] (prod)
```

**Convention 3: Severity → Sample Rate**

```ruby
# :error/:fatal → 1.0 (100%)
# :warn → 0.5 (50%)
# :success/:info → 0.1 (10%)
# :debug → 0.01 (1%)
```

**Convention 4: Severity → Retention**

```ruby
# :error/:fatal → 90 days
# :info/:success → 30 days
# :debug → 7 days
```

**Result: Zero-Config Events**

```ruby
# 90% of events need ONLY schema!
class Events::OrderCreated < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:decimal)
  end
  # ← That's it! All config from conventions:
  #    severity: :success (from name)
  #    adapters: [:loki] (from severity)
  #    sample_rate: 0.1 (from severity)
  #    retention: 30.days (from severity)
  #    rate_limit: 1000 (default)
end
```

**Override when needed:**

```ruby
class Events::OrderCreated < E11y::Event::Base
  schema do; required(:order_id).filled(:string); end
  
  severity :info  # ← Override convention
  sample_rate 1.0  # ← Never sample
  retention 7.years  # ← Financial records
end
```

### Event Naming Conventions

**Recommended pattern:** `<entity>.<past_tense_verb>`

```ruby
# ✅ GOOD naming
Events::OrderCreated      # order.created
Events::OrderPaid         # order.paid
Events::OrderShipped      # order.shipped
Events::UserRegistered    # user.registered
Events::PaymentProcessed  # payment.processed

# ❌ BAD naming
Events::CreateOrder       # Present tense (not an event!)
Events::OrderCreate       # Wrong order
Events::Order             # Too generic
Events::OrderEvent        # Redundant suffix
```

---

## 🔧 Adapter Routing (Per-Event)

### Override Adapters for Specific Events

**Step 1: Define adapters in global config (one place!):**
```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  # Register named adapters (created once with connections)
  config.register_adapter :loki, E11y::Adapters::LokiAdapter.new(
    url: ENV['LOKI_URL']
  )
  
  config.register_adapter :file, E11y::Adapters::FileAdapter.new(
    path: 'log/e11y'
  )
  
  config.register_adapter :sentry, E11y::Adapters::SentryAdapter.new(
    dsn: ENV['SENTRY_DSN'],
    environment: Rails.env
  )
  
  config.register_adapter :pagerduty, E11y::Adapters::PagerDutyAdapter.new(
    api_key: ENV['PAGERDUTY_KEY'],
    service_id: ENV['PAGERDUTY_SERVICE_ID']
  )
  
  config.register_adapter :slack, E11y::Adapters::SlackAdapter.new(
    webhook_url: ENV['SLACK_WEBHOOK_URL'],
    channel: '#alerts'
  )
  
  # Default adapters (used by all events unless overridden)
  config.default_adapters = [:loki, :file]
end
```

**Step 2: Reference adapters by name in events:**
```ruby
# app/events/critical_error.rb
module Events
  class CriticalError < E11y::Event::Base
    severity :fatal
    
    schema do
      required(:error).filled(:string)
      required(:context).filled(:hash)
    end
    
    # Override: Send ONLY to Sentry (reference by name!)
    adapters [:sentry]
  end
end

# Usage
Events::CriticalError.track(
  error: 'Database connection lost',
  context: { db_host: 'prod-db-1' }
)
# → Sent ONLY to :sentry adapter ✅
# → NOT sent to :loki or :file ✅
```

### Use Cases for Adapter Override

**1. Security Events → Separate Audit Log**
```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  # Register security audit adapter
  config.register_adapter :security_audit, E11y::Adapters::FileAdapter.new(
    path: 'log/security_audit',
    permissions: 0600  # Restricted access
  )
  
  # Other adapters...
  config.register_adapter :loki, E11y::Adapters::LokiAdapter.new(...)
  config.default_adapters = [:loki]
end

# app/events/security_audit_event.rb
module Events
  class SecurityAuditEvent < E11y::Event::Base
    severity :warn
    
    # Route to secure audit log ONLY (reference by name!)
    adapters [:security_audit]
  end
  
  class UserPermissionChanged < SecurityAuditEvent
    schema do
      required(:user_id).filled(:string)
      required(:old_role).filled(:string)
      required(:new_role).filled(:string)
      required(:changed_by).filled(:string)
    end
  end
end

# Goes to :security_audit adapter ONLY
Events::UserPermissionChanged.track(
  user_id: 'user_123',
  old_role: 'user',
  new_role: 'admin',
  changed_by: 'admin_456'
)
```

**2. High-Volume Debug Events → Local File Only**
```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  # Register debug file adapter
  config.register_adapter :debug_file, E11y::Adapters::FileAdapter.new(
    path: 'log/sql_queries',
    rotation: :daily
  )
  
  config.register_adapter :loki, E11y::Adapters::LokiAdapter.new(...)
  config.default_adapters = [:loki]  # Default: Loki for all
end

# app/events/debug_sql_query.rb
module Events
  class DebugSqlQuery < E11y::Event::Base
    severity :debug
    
    # Don't send to Loki (too expensive!)
    # Write to local file only (reference by name!)
    adapters [:debug_file]
    
    schema do
      required(:query).filled(:string)
      required(:duration_ms).filled(:float)
    end
  end
end

# High-volume events don't flood Loki
1000.times do
  Events::DebugSqlQuery.track(query: 'SELECT ...', duration_ms: 1.2)
end
# → All written to :debug_file adapter ✅
# → Loki bills stay low ✅
```

**3. Critical Alerts → Multiple Destinations**
```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  # Register all adapters once
  config.register_adapter :sentry, E11y::Adapters::SentryAdapter.new(
    dsn: ENV['SENTRY_DSN']
  )
  
  config.register_adapter :pagerduty, E11y::Adapters::PagerDutyAdapter.new(
    api_key: ENV['PAGERDUTY_KEY'],
    service_id: ENV['PAGERDUTY_SERVICE_ID']
  )
  
  config.register_adapter :slack_fraud, E11y::Adapters::SlackAdapter.new(
    webhook_url: ENV['SLACK_WEBHOOK_URL'],
    channel: '#fraud-alerts'
  )
  
  config.register_adapter :fraud_audit, E11y::Adapters::FileAdapter.new(
    path: 'log/fraud_audit',
    permissions: 0600
  )
  
  config.register_adapter :loki, E11y::Adapters::LokiAdapter.new(...)
  config.default_adapters = [:loki]
end

# app/events/payment_fraud_detected.rb
module Events
  class PaymentFraudDetected < E11y::Event::Base
    severity :fatal
    
    # Send to multiple destinations! (reference by name)
    adapters [:sentry, :pagerduty, :slack_fraud, :fraud_audit]
    
    schema do
      required(:transaction_id).filled(:string)
      required(:user_id).filled(:string)
      required(:fraud_score).filled(:float)
      required(:reasons).array(:string)
    end
  end
end

# One event → 4 destinations!
Events::PaymentFraudDetected.track(
  transaction_id: 'tx_123',
  user_id: 'user_456',
  fraud_score: 0.95,
  reasons: ['velocity_check_failed', 'suspicious_location']
)
# → :sentry alert ✅
# → :pagerduty incident ✅
# → :slack_fraud notification ✅
# → :fraud_audit log written ✅
```

**4. Inherit + Extend Global Adapters**
```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.register_adapter :loki, E11y::Adapters::LokiAdapter.new(...)
  config.register_adapter :file, E11y::Adapters::FileAdapter.new(...)
  config.register_adapter :slack_business, E11y::Adapters::SlackAdapter.new(
    webhook_url: ENV['SLACK_WEBHOOK_URL'],
    channel: '#business-events'
  )
  
  config.default_adapters = [:loki, :file]
end

# app/events/important_business_event.rb
module Events
  class ImportantBusinessEvent < E11y::Event::Base
    # Strategy: add to default adapters (not replace)
    adapters_strategy :append  # :append or :replace (default)
    
    # Add Slack to global adapters
    adapters [:slack_business]
  end
  
  class LargeOrderPlaced < ImportantBusinessEvent
    schema do
      required(:order_id).filled(:string)
      required(:amount).filled(:decimal)
    end
  end
end

# Goes to: :loki (global) + :file (global) + :slack_business (added) ✅
Events::LargeOrderPlaced.track(
  order_id: 'ord_123',
  amount: 10000.00
)
```

**5. Environment-Specific Routing**
```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  # Register adapters per environment
  case Rails.env
  when 'production'
    config.register_adapter :loki, E11y::Adapters::LokiAdapter.new(
      url: ENV['LOKI_URL']
    )
    config.register_adapter :s3_archive, E11y::Adapters::S3Adapter.new(
      bucket: 'payment-archive'
    )
    config.default_adapters = [:loki]
    
  when 'staging'
    config.register_adapter :loki, E11y::Adapters::LokiAdapter.new(
      url: ENV['STAGING_LOKI_URL']
    )
    config.default_adapters = [:loki]
    
  when 'development'
    config.register_adapter :console, E11y::Adapters::ConsoleAdapter.new(
      colored: true
    )
    config.default_adapters = [:console]
    
  when 'test'
    config.register_adapter :memory, E11y::Adapters::MemoryAdapter.new
    config.default_adapters = [:memory]
  end
end

# app/events/payment_processed.rb
module Events
  class PaymentProcessed < E11y::Event::Base
    schema do
      required(:transaction_id).filled(:string)
      required(:amount).filled(:decimal)
    end
    
    # Production: also archive to S3
    if Rails.env.production?
      adapters [:loki, :s3_archive]
    end
    # Other envs: use default_adapters
  end
end
```

---

## 📊 Metrics Configuration

### Pattern-Based Auto-Metrics

```ruby
E11y.configure do |config|
  config.metrics do
    # Global counter for ALL events
    counter_for pattern: '*',
                name: 'business_events.total',
                tags: [:event_name, :severity]
    
    # Domain-specific counters
    counter_for pattern: 'order.*',
                name: 'orders.events.total',
                tags: [:event_name]
    
    counter_for pattern: 'user.*',
                name: 'users.events.total',
                tags: [:event_name]
    
    # Histograms for amounts/durations
    histogram_for pattern: '*.paid',
                  name: 'payments.amount',
                  value: ->(e) { e.payload[:amount] },
                  tags: [:currency],
                  buckets: [10, 50, 100, 500, 1000, 5000, 10000]
    
    # Success rate (special metric type)
    success_rate_for pattern: 'payment.*',
                     name: 'payments.success_rate'
    # Automatically calculates from :success and :error events
  end
end
```

---

## ⚙️ Advanced: Custom Middleware

> **Implementation:** See [ADR-001 Section 7: Extension Points](../ADR-001-architecture.md#7-extension-points) for detailed architecture.

E11y allows you to extend the event processing pipeline with custom middleware. This is useful for:
- Adding custom enrichment logic
- Implementing custom filtering/transformation
- Integrating with third-party services
- Adding business-specific validation

### Custom Middleware Example

**Step 1: Define Custom Middleware**

```ruby
# lib/e11y/middleware/priority_enrichment.rb
module E11y
  module Middleware
    class PriorityEnrichment < E11y::Middleware
      def call(event_data)
        # Add priority field based on business logic
        if event_data[:payload][:user_role] == 'admin'
          event_data[:payload][:priority] = 'high'
        elsif event_data[:payload][:amount].to_f > 10_000
          event_data[:payload][:priority] = 'high'
        else
          event_data[:payload][:priority] = 'normal'
        end
        
        # Continue pipeline
        @app.call(event_data)
      end
    end
  end
end
```

**Step 2: Register Middleware**

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  # Register in correct order (see UC-001 for order requirements)
  config.pipeline.use E11y::Middleware::TraceContext
  config.pipeline.use E11y::Middleware::Validation
  config.pipeline.use E11y::Middleware::PiiFilter
  config.pipeline.use E11y::Middleware::PriorityEnrichment  # ← Custom middleware
  config.pipeline.use E11y::Middleware::Routing
end
```

**Step 3: Use Enriched Data**

```ruby
# Events now have priority field
Events::OrderPaid.track(
  order_id: 'ORD-123',
  amount: 15_000.00,
  user_role: 'admin'
)

# Result:
# {
#   event_name: "order.paid",
#   payload: {
#     order_id: "ORD-123",
#     amount: 15000.0,
#     user_role: "admin",
#     priority: "high"  # ← Automatically added by middleware!
#   }
# }
```

### Use Cases for Custom Middleware

**1. Tenant/Organization Isolation**

```ruby
class TenantMiddleware < E11y::Middleware
  def call(event_data)
    # Add tenant_id from current context
    event_data[:payload][:tenant_id] = Current.tenant_id
    event_data[:tenant_id] = Current.tenant_id  # Top-level for filtering
    
    @app.call(event_data)
  end
end

# Now all events automatically tagged with tenant
Events::OrderCreated.track(order_id: 'ORD-123')
# → { event_name: "order.created", tenant_id: "tenant_456", payload: {...} }
```

**2. A/B Test Tracking**

```ruby
class ExperimentMiddleware < E11y::Middleware
  def call(event_data)
    # Add experiment variant from session
    if Current.user && Current.user.experiment_variants.present?
      event_data[:payload][:experiments] = Current.user.experiment_variants
    end
    
    @app.call(event_data)
  end
end

# Events now include A/B test info
Events::CheckoutCompleted.track(order_id: 'ORD-123')
# → { payload: { ..., experiments: { checkout_flow: "variant_b" } } }
```

**3. Custom Rate Limiting**

```ruby
class CustomRateLimiter < E11y::Middleware
  def initialize(app)
    super
    @limiter = RateLimiter.new
  end
  
  def call(event_data)
    key = "#{event_data[:event_name]}:#{event_data[:payload][:user_id]}"
    
    if @limiter.exceeded?(key, limit: 100, period: 60)
      # Drop event (don't call @app.call)
      E11y.logger.warn("Rate limit exceeded for #{key}")
      return :rate_limited
    end
    
    @limiter.increment(key)
    @app.call(event_data)
  end
end
```

**4. Conditional Adapter Routing**

```ruby
class DynamicRoutingMiddleware < E11y::Middleware
  def call(event_data)
    # Route high-priority events to PagerDuty
    if event_data[:payload][:priority] == 'critical'
      event_data[:adapters] ||= []
      event_data[:adapters] << :pagerduty
    end
    
    @app.call(event_data)
  end
end
```

### Middleware Order Matters!

> ⚠️ **CRITICAL:** Middleware order determines the sequence of processing. See [UC-001 Configuration](./UC-001-request-scoped-debug-buffering.md#-configuration) for detailed explanation of middleware order requirements.

**General Order Rules:**
1. **Enrichment** (trace context, tenant_id) → FIRST
2. **Validation** (schema checks) → EARLY (fail fast)
3. **Security** (PII filtering) → BEFORE business logic
4. **Business Logic** (custom enrichment, rate limiting) → MIDDLE
5. **Routing** (buffer/adapter selection) → LAST

**Example Correct Order:**

```ruby
E11y.configure do |config|
  # 1. Enrichment
  config.pipeline.use E11y::Middleware::TraceContext
  config.pipeline.use TenantMiddleware
  
  # 2. Validation
  config.pipeline.use E11y::Middleware::Validation
  
  # 3. Security
  config.pipeline.use E11y::Middleware::PiiFilter
  
  # 4. Business Logic
  config.pipeline.use PriorityEnrichment
  config.pipeline.use ExperimentMiddleware
  config.pipeline.use CustomRateLimiter
  
  # 5. Routing (LAST!)
  config.pipeline.use E11y::Middleware::Routing
end
```

---

## 🧪 Testing

### Unit Test Event Class

```ruby
# spec/events/order_created_spec.rb
RSpec.describe Events::OrderCreated do
  it 'validates required attributes' do
    expect {
      described_class.track(
        order_id: nil,  # Invalid!
        user_id: 'user_123',
        total_amount: 99.99
      )
    }.to raise_error(E11y::ValidationError)
  end
  
  it 'validates amount is positive' do
    expect {
      described_class.track(
        order_id: 'ORD-123',
        user_id: 'user_123',
        total_amount: -10  # Invalid!
      )
    }.to raise_error(E11y::ValidationError, /must be greater than/)
  end
  
  it 'tracks valid event' do
    expect(E11y::Collector).to receive(:collect).with(
      have_attributes(
        name: 'order.created',
        severity: :success,
        payload: hash_including(order_id: 'ORD-123')
      )
    )
    
    described_class.track(
      order_id: 'ORD-123',
      user_id: 'user_123',
      items_count: 3,
      total_amount: 99.99,
      currency: 'USD'
    )
  end
end
```

### Integration Test Controller

```ruby
# spec/controllers/orders_controller_spec.rb
RSpec.describe OrdersController, type: :controller do
  it 'tracks order creation event' do
    expect(Events::OrderCreated).to receive(:track).with(
      hash_including(
        order_id: anything,
        user_id: current_user.id
      )
    )
    
    post :create, params: { sku: 'ABC123', quantity: 1 }
    
    expect(response).to be_successful
  end
end
```

---

## 💡 Best Practices

### ✅ DO

1. **Use past tense for event names**
   ```ruby
   Events::OrderCreated  # ✅
   Events::CreateOrder   # ❌
   ```

2. **Include business-meaningful attributes**
   ```ruby
   # ✅ Good: can answer business questions
   Events::OrderPaid.track(
     order_id: order.id,
     amount: order.total,
     currency: order.currency,
     payment_method: 'stripe',
     user_segment: user.segment  # NEW, HIGH, RETURNING
   )
   
   # ❌ Bad: only technical details
   Events::OrderPaid.track(order_id: order.id)
   ```

3. **Use :success severity for completed operations**
   ```ruby
   Events::OrderPaid.track(..., severity: :success)  # ✅
   Events::OrderPaid.track(..., severity: :info)     # ❌ Harder to filter
   ```

4. **Measure duration for long-running operations**
   ```ruby
   Events::PaymentProcessed.track(...) do
     # Duration automatically measured
     process_payment
   end
   ```

5. **Override adapters for special event types**
   ```ruby
   # ✅ Good: Critical events to multiple destinations (reference by name!)
   class CriticalError < E11y::Event::Base
     adapters [:sentry, :pagerduty, :slack]
   end
   
   # ✅ Good: High-volume debug to local file only
   class DebugEvent < E11y::Event::Base
     adapters [:debug_file]
   end
   ```

### ❌ DON'T

1. **Don't log technical details as business events**
   ```ruby
   # ❌ Technical, not business event
   Events::DatabaseQuery.track(sql: '...', severity: :debug)
   
   # ✅ Use :debug severity and request-scoped buffering
   Events::DatabaseQuery.track(sql: '...', severity: :debug)
   ```

2. **Don't include PII in event names/attributes without filtering**
   ```ruby
   # ❌ PII leak!
   Events::UserRegistered.track(
     email: 'user@example.com',  # ← Will be filtered if configured
     password: 'secret123'        # ← NEVER include passwords!
   )
   
   # ✅ PII filtered by Rails config
   # config/application.rb
   config.filter_parameters += [:email, :password]
   ```

3. **Don't create too many event types**
   ```ruby
   # ❌ Over-engineering
   Events::OrderCreatedInProduction
   Events::OrderCreatedInStaging
   Events::OrderCreatedInDev
   
   # ✅ Use context enrichment
   Events::OrderCreated  # context[:env] auto-added
   ```

4. **Don't override adapters for every event**
   ```ruby
   # ❌ Bad: Repetitive adapter references
   class OrderCreated < E11y::Event::Base
     adapters [:loki]  # Same as default!
   end
   
   class OrderPaid < E11y::Event::Base
     adapters [:loki]  # Duplication!
   end
   
   # ✅ Good: Use default_adapters, override only when needed
   # config/initializers/e11y.rb
   config.default_adapters = [:loki]
   
   # Most events just use defaults (no adapters line needed!)
   class OrderCreated < E11y::Event::Base
     # Uses default_adapters automatically ✅
   end
   
   # Override only for special cases
   class CriticalError < E11y::Event::Base
     adapters [:sentry]  # Different from default!
   end
   ```

5. **Don't create adapter instances in event classes**
   ```ruby
   # ❌ Bad: Creating adapter instances (defeats the purpose!)
   class MyEvent < E11y::Event::Base
     adapters [
       E11y::Adapters::LokiAdapter.new(url: ...)  # ← NO!
     ]
   end
   
   # ✅ Good: Reference by name (adapters created once in config)
   class MyEvent < E11y::Event::Base
     adapters [:loki]  # ← YES!
   end
   ```

---

## ⚡ Performance Guarantees

> **Implementation:** See [ADR-001 Section 8: Performance Requirements](../ADR-001-architecture.md#8-performance-requirements) for detailed architecture targets.

E11y is designed for **high-performance production environments** with strict SLAs:

### Service Level Objectives (SLOs)

| Metric | Target | Critical? |
|--------|--------|-----------|
| **Event Track Latency (p99)** | <1ms | ✅ Critical |
| **Memory Footprint @ Steady State** | <100MB | ✅ Critical |
| **Sustained Throughput** | 1000 events/sec | ✅ Critical |
| **Burst Throughput** | 5000 events/sec (5s) | ⚠️ Important |
| **CPU Usage @ 1000 evt/s** | <5% | ⚠️ Important |

### What This Means for Your Application

**1. Track() Calls are Near-Zero Overhead**

```ruby
# Benchmark: 1000 events/sec
Benchmark.ips do |x|
  x.report("E11y.track") do
    Events::OrderPaid.track(
      order_id: 'ORD-123',
      amount: 99.99
    )
  end
end

# Results:
# E11y.track: 100,000 i/s → ~0.01ms per call
# p99 latency: <1ms ✅
```

**2. Memory-Efficient (No Memory Leaks)**

```ruby
# Memory profile @ 1000 events/sec for 1 hour
# - Before E11y: 200MB RSS
# - After E11y: 290MB RSS (+90MB)
# - E11y footprint: ~90MB (within <100MB target ✅)

# No memory growth over time:
# Hour 1: 290MB
# Hour 24: 291MB (stable)
# Week 1: 290MB (no leaks ✅)
```

**3. Non-Blocking Architecture**

```ruby
# track() is async - doesn't block request thread
def create_order
  order = Order.create!(params)
  
  # This call returns immediately (<1ms)
  Events::OrderCreated.track(order_id: order.id)  
  # ↑ Event buffered, flushed in background
  
  render json: order  # Response not delayed ✅
end
```

### Measurement & Monitoring

**How to Verify SLOs in Your App:**

```ruby
# 1. Enable self-monitoring
E11y.configure do |config|
  config.self_monitoring do
    enabled true
    
    # Track E11y's own performance
    histogram :track_latency_ms,
              comment: 'Event track() call latency',
              buckets: [0.1, 0.5, 1, 2, 5, 10]
    
    gauge :memory_usage_mb,
          comment: 'E11y memory footprint (RSS)'
    
    counter :events_tracked_total,
            comment: 'Total events tracked'
  end
end

# 2. Query SLOs in Prometheus
# p99 track latency (should be <1ms)
histogram_quantile(0.99, 
  rate(e11y_track_latency_ms_bucket[5m])
)

# Memory usage (should be <100MB)
e11y_memory_usage_mb

# Throughput (events/sec)
rate(e11y_events_tracked_total[1m])
```

**Alerting Rules:**

```yaml
# prometheus/alerts.yml
groups:
  - name: e11y_slo
    rules:
      - alert: E11yHighLatency
        expr: histogram_quantile(0.99, rate(e11y_track_latency_ms_bucket[5m])) > 1
        for: 5m
        annotations:
          summary: "E11y p99 latency >1ms (SLO violation)"
      
      - alert: E11yHighMemory
        expr: e11y_memory_usage_mb > 100
        for: 10m
        annotations:
          summary: "E11y memory usage >100MB (SLO violation)"
      
      - alert: E11yLowThroughput
        expr: rate(e11y_events_tracked_total[1m]) < 1000 and rate(app_requests_total[1m]) > 1000
        annotations:
          summary: "E11y can't keep up with event load"
```

### What If SLOs are Not Met?

**Common Causes & Solutions:**

| Symptom | Likely Cause | Solution |
|---------|--------------|----------|
| **p99 >1ms** | Too many events in buffer | Increase flush interval or reduce event volume |
| **Memory >100MB** | Request buffer limit too high | Reduce `buffer_limit` (default: 100) |
| **Throughput <1000/s** | Adapter bottleneck | Check adapter latency, enable batching |
| **CPU >5%** | Expensive middleware | Profile middleware, optimize or remove |

**Debugging Performance Issues:**

```ruby
# Enable detailed profiling
E11y.configure do |config|
  config.profiling do
    enabled true  # Production: false (overhead!)
    
    # Profile middleware latency
    profile_middleware true
    
    # Profile adapter write latency
    profile_adapters true
  end
end

# Check profiling results
E11y::Profiler.report
# Output:
# Middleware Latency:
#   TraceContext: 0.05ms (5%)
#   Validation: 0.20ms (20%)
#   PiiFilter: 0.30ms (30%)  ← Bottleneck!
#   Routing: 0.10ms (10%)
# 
# Adapter Latency:
#   LokiAdapter: 15ms (avg)
#   SentryAdapter: 25ms (avg)
```

### Performance Best Practices

**✅ DO:**
- Keep event payload small (<1KB per event)
- Use batching for high-volume events
- Monitor E11y's own metrics
- Set reasonable `buffer_limit` (50-100)

**❌ DON'T:**
- Track >10,000 unique events/sec (scale horizontally instead)
- Create middleware with blocking I/O (use async adapters)
- Set `flush_interval` <50ms (too aggressive)
- Disable batching for high-volume adapters

---

## 🔒 Validations (NEW - v1.1)

> **🎯 Pattern:** Validate configuration at class load time (fail fast!).

### Schema Presence Validation

**Problem:** Events without schema → runtime errors.

**Solution:** Validate schema presence at class load:

```ruby
# Gem implementation (automatic):
class E11y::Event::Base
  def self.inherited(subclass)
    super
    at_exit do
      unless subclass.respond_to?(:schema) && subclass.schema
        raise "#{subclass} missing schema! All events must define schema."
      end
    end
  end
end

# Result:
class Events::OrderPaid < E11y::Event::Base
  # ← ERROR at load time: "Events::OrderPaid missing schema!"
end
```

### Severity Level Validation

**Problem:** Typos in severity levels → silent failures.

**Solution:** Validate severity against whitelist:

```ruby
# Gem implementation (automatic):
VALID_SEVERITIES = [:debug, :info, :success, :warn, :error, :fatal]

def self.severity(level)
  unless VALID_SEVERITIES.include?(level)
    raise ArgumentError, "Invalid severity: #{level}. Valid: #{VALID_SEVERITIES.join(', ')}"
  end
  self._severity = level
end

# Result:
class Events::OrderPaid < E11y::Event::Base
  severity :critical  # ← ERROR: "Invalid severity: :critical. Valid: debug, info, success, warn, error, fatal"
end
```

### Adapters Registration Validation

**Problem:** Typos in adapter names → events lost.

**Solution:** Validate adapters against registered list:

```ruby
# Gem implementation (automatic):
def self.adapters(list)
  list.each do |adapter|
    unless E11y.registered_adapters.include?(adapter)
      raise ArgumentError, "Unknown adapter: #{adapter}. Registered: #{E11y.registered_adapters.keys.join(', ')}"
    end
  end
  self._adapters = list
end

# Result:
class Events::OrderPaid < E11y::Event::Base
  adapters [:loki, :sentri]  # ← ERROR: "Unknown adapter: :sentri. Registered: loki, sentry, file"
end
```

### Audit Event Locked Settings Validation

**Problem:** Overriding audit event settings → compliance violations.

**Solution:** Lock `rate_limiting` and `sampling` for audit events:

```ruby
# Gem implementation (automatic):
def self.rate_limiting(enabled)
  if self._audit_event && enabled
    raise ArgumentError, "Cannot enable rate_limiting for audit events! Audit events must never be rate limited."
  end
  self._rate_limiting = enabled
end

def self.sampling(enabled)
  if self._audit_event && enabled
    raise ArgumentError, "Cannot enable sampling for audit events! Audit events must never be sampled."
  end
  self._sampling = enabled
end

# Result:
class Events::UserDeleted < E11y::Event::Base
  audit_event true
  rate_limiting true  # ← ERROR: "Cannot enable rate_limiting for audit events!"
  sampling true       # ← ERROR: "Cannot enable sampling for audit events!"
end
```

---

## 🌍 Environment-Specific Configuration (NEW - v1.1)

> **🎯 Pattern:** Use Ruby conditionals for environment-specific config.

### Example 1: Debug Events (File in Dev, Loki in Prod)

```ruby
class Events::DebugQuery < E11y::Event::Base
  schema do
    required(:query).filled(:string)
    required(:duration_ms).filled(:integer)
  end
  
  # Environment-specific adapters
  adapters Rails.env.production? ? [:loki] : [:file]
  
  # Environment-specific sampling
  sample_rate Rails.env.production? ? 0.01 : 1.0  # 1% prod, 100% dev
end
```

### Example 2: High-Volume Events (Different Rates)

```ruby
class Events::ApiRequest < E11y::Event::Base
  schema do
    required(:endpoint).filled(:string)
    required(:status).filled(:integer)
  end
  
  # Environment-specific rate limiting
  rate_limit case Rails.env
             when 'production' then 10_000
             when 'staging' then 1_000
             else 100
             end
end
```

### Example 3: Audit Retention (Jurisdiction-Specific)

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  # Configurable audit retention (GDPR: 7 years, other: custom)
  config.audit_retention = case ENV['JURISDICTION']
                           when 'EU' then 7.years
                           when 'US' then 10.years  # Financial regulations
                           else 5.years
                           end
end

# Event uses configured value:
class Events::UserDeleted < E11y::Event::Base
  audit_event true
  # ← Auto: retention = E11y.config.audit_retention (7/10/5 years)
end
```

---

## 📊 Precedence Rules (NEW - v1.1)

> **🎯 Pattern:** Configuration precedence (most specific wins).

### Precedence Order (Highest to Lowest)

```
1. Event-level explicit config (highest priority)
   ↓
2. Preset module config
   ↓
3. Base class config (inheritance)
   ↓
4. Convention-based defaults
   ↓
5. Global config (lowest priority)
```

### Example: Mixing Inheritance + Presets

```ruby
# Global config (lowest priority)
E11y.configure do |config|
  config.adapters = [:file]  # Default for all events
  config.sample_rate = 0.1   # 10% default
end

# Base class (medium priority)
class Events::BasePaymentEvent < E11y::Event::Base
  severity :success
  adapters [:loki, :sentry]  # Override global
  sample_rate 1.0            # Never sample payments
end

# Preset module (higher priority)
module E11y::Presets::HighValueEvent
  extend ActiveSupport::Concern
  included do
    rate_limit 10_000
    retention 7.years
    # Does NOT override adapters/sample_rate (not defined in preset)
  end
end

# Event (highest priority)
class Events::CriticalPayment < Events::BasePaymentEvent
  include E11y::Presets::HighValueEvent
  
  adapters [:loki, :sentry, :s3_archive]  # Override base (add S3)
  
  # Final config:
  # - severity: :success (from base)
  # - adapters: [:loki, :sentry, :s3_archive] (event-level override)
  # - sample_rate: 1.0 (from base)
  # - rate_limit: 10_000 (from preset)
  # - retention: 7.years (from preset)
end
```

### Precedence Rules Table

| Config | Global | Convention | Base Class | Preset | Event-Level | Winner |
|--------|--------|------------|------------|--------|-------------|--------|
| `severity` | - | `:success` | `:warn` | - | `:error` | **`:error`** (event) |
| `adapters` | `[:file]` | `[:loki]` | `[:sentry]` | - | - | **`[:sentry]`** (base) |
| `sample_rate` | `0.1` | `0.5` | - | `1.0` | - | **`1.0`** (preset) |
| `rate_limit` | `1000` | - | - | - | - | **`1000`** (global) |

---

## 📚 Related Use Cases

- **[UC-001: Request-Scoped Debug Buffering](./UC-001-request-scoped-debug-buffering.md)** - Debug vs business events
- **[UC-003: Pattern-Based Metrics](./UC-003-pattern-based-metrics.md)** - Auto-generate metrics
- **[UC-005: PII Filtering](./UC-005-pii-filtering.md)** - Secure event data

---

**Document Version:** 1.0  
**Last Updated:** January 12, 2026  
**Status:** ✅ Complete

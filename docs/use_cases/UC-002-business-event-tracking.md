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
  class RegistrationStarted < E11y::Event
    attribute :user_id, Types::String
    attribute :source, Types::String  # organic, referral, ad
    default_severity :info
  end
  
  class EmailVerified < E11y::Event
    attribute :user_id, Types::String
    attribute :verification_method, Types::String  # email_link, code
    default_severity :success
  end
  
  class ProfileCompleted < E11y::Event
    attribute :user_id, Types::String
    attribute :fields_filled, Types::Array.of(Types::String)
    default_severity :success
  end
  
  class FirstLogin < E11y::Event
    attribute :user_id, Types::String
    attribute :time_since_registration_hours, Types::Integer
    default_severity :success
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
  class PaymentInitiated < E11y::Event
    attribute :payment_id, Types::String
    attribute :order_id, Types::String
    attribute :amount, Types::Decimal
    attribute :currency, Types::String
    attribute :payment_method, Types::String
    default_severity :info
  end
  
  class PaymentSucceeded < E11y::Event
    attribute :payment_id, Types::String
    attribute :order_id, Types::String
    attribute :amount, Types::Decimal
    attribute :currency, Types::String
    attribute :payment_method, Types::String
    attribute :processor_id, Types::String  # Stripe charge ID
    attribute :duration_ms, Types::Integer
    default_severity :success  # ← Key: success events easy to filter
  end
  
  class PaymentFailed < E11y::Event
    attribute :payment_id, Types::String
    attribute :order_id, Types::String
    attribute :amount, Types::Decimal
    attribute :error_code, Types::String
    attribute :error_message, Types::String
    default_severity :error
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
  class UserLoggedIn < E11y::Event
    # Required: define attributes
    attribute :user_id, Types::String
    attribute :ip_address, Types::String
    attribute :user_agent, Types::String.optional
    
    # Optional: default severity
    default_severity :info
    
    # Optional: validation
    validates :user_id, presence: true
    validates :ip_address, format: { with: /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/ }
  end
end

# Usage
Events::UserLoggedIn.track(
  user_id: 'user_123',
  ip_address: '192.168.1.1',
  user_agent: request.user_agent
)
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

## 📚 Related Use Cases

- **[UC-001: Request-Scoped Debug Buffering](./UC-001-request-scoped-debug-buffering.md)** - Debug vs business events
- **[UC-003: Pattern-Based Metrics](./UC-003-pattern-based-metrics.md)** - Auto-generate metrics
- **[UC-005: PII Filtering](./UC-005-pii-filtering.md)** - Secure event data

---

**Document Version:** 1.0  
**Last Updated:** January 12, 2026  
**Status:** ✅ Complete

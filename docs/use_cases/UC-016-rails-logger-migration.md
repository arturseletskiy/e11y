# UC-016: Rails Logger Migration

**Status:** MVP Feature  
**Complexity:** Beginner  
**Setup Time:** 15-20 minutes  
**Target Users:** All Developers, DevOps Teams

---

## 📋 Overview

### Problem Statement

**The migration challenge:**
```ruby
# ❌ BEFORE: Existing Rails.logger usage everywhere
# controllers/orders_controller.rb
Rails.logger.info "Order #{order.id} created by user #{current_user.id}"

# services/payment_service.rb
Rails.logger.debug "Charging card: #{card.last4}"
Rails.logger.error "Payment failed: #{error.message}"

# jobs/process_order_job.rb
Rails.logger.info "Processing order #{order_id}"

# Problems:
# 1. 1000+ Rails.logger calls across codebase
# 2. Can't just replace all at once (risky!)
# 3. Need gradual migration path
# 4. Must support both systems during transition
# 5. Don't want to lose existing logs
```

### E11y Solution

**Gradual, safe migration strategy:**
```ruby
# ✅ AFTER: Coexistence mode (Phase 1)
E11y.configure do |config|
  config.rails_logger do
    # Intercept Rails.logger calls
    intercept_rails_logger true
    
    # Mirror to both systems during migration
    mirror_to_rails_logger true
    
    # Convert to structured events
    auto_convert_to_events true
  end
end

# Existing code works unchanged!
Rails.logger.info "Order created"
# → Sent to both Rails.logger AND E11y ✅

# New code uses E11y directly
Events::OrderCreated.track(order_id: order.id)
# → Only E11y (no duplication) ✅

# Phase 2: Turn off mirroring
config.mirror_to_rails_logger = false
# → All logs now go to E11y only ✅
```

---

## 🎯 Migration Strategy

> **Implementation:** See [ADR-008 Section 7: Rails Logger Bridge](../ADR-008-rails-integration.md#7-rails-logger-bridge) for Logger::Bridge architecture, dual logging, and 3-phase migration strategy (shadow → conversion → full).

### Phase 1: Shadow Mode (Week 1-2)

**E11y runs alongside Rails.logger, doesn't break anything:**
```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  # Phase 1: Shadow mode
  config.rails_logger do
    # Intercept Rails.logger (but keep original too!)
    intercept_rails_logger true
    mirror_to_rails_logger true  # ← Keep Rails.logger working!
    
    # Auto-convert to E11y events
    auto_convert_to_events true
    
    # Map severity levels
    severity_mapping do
      debug -> :debug
      info -> :info
      warn -> :warn
      error -> :error
      fatal -> :fatal
    end
  end
  
  # Send to both Stdout (Rails.logger) and Loki (E11y)
  config.adapters = [
    E11y::Adapters::StdoutAdapter.new,  # Development
    E11y::Adapters::LokiAdapter.new(...)  # E11y backend
  ]
end

# Existing code continues to work!
Rails.logger.info "User logged in"
# → Goes to BOTH:
#   1. Rails.logger (stdout, as before)
#   2. E11y (Loki, new!)

# Verification:
# - Rails logs still appear in stdout ✅
# - E11y logs appear in Grafana ✅
# - No errors, no breakage ✅
```

---

### Phase 2: Gradual Conversion (Week 3-6)

**Replace Rails.logger with E11y events, one feature at a time:**
```ruby
# Step 1: Start with new features (safe!)
class OrdersController < ApplicationController
  def create
    order = Order.create!(order_params)
    
    # ✅ NEW: Use E11y for new code
    Events::OrderCreated.track(
      order_id: order.id,
      user_id: current_user.id,
      amount: order.total
    )
    
    render json: order
  end
end

# Step 2: Replace high-value areas (authentication, payments)
class SessionsController < ApplicationController
  def create
    # ❌ OLD: Rails.logger
    # Rails.logger.info "User #{user.id} logged in from #{request.ip}"
    
    # ✅ NEW: E11y structured event
    Events::UserLoggedIn.track(
      user_id: user.id,
      ip_address: request.ip,
      user_agent: request.user_agent
    )
  end
end

# Step 3: Leave low-value areas as-is (for now)
class HealthController < ApplicationController
  def show
    # Keep Rails.logger for simple health checks (low priority)
    Rails.logger.debug "Health check"
    render json: { status: 'ok' }
  end
end

# Progress tracking:
# - Week 3: Authentication (5 controllers) ✅
# - Week 4: Orders & Payments (10 controllers) ✅
# - Week 5: Background Jobs (15 jobs) ✅
# - Week 6: Core Services (20 services) ✅
```

---

### Phase 3: Full Migration (Week 7+)

**Turn off Rails.logger mirroring, E11y only:**
```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.rails_logger do
    intercept_rails_logger true
    mirror_to_rails_logger false  # ← Turn off mirroring!
    
    # Auto-convert remaining Rails.logger calls
    auto_convert_to_events true
  end
end

# Now:
# - E11y events → E11y only ✅
# - Rails.logger calls → Auto-converted to E11y ✅
# - No more duplication ✅

# Optional: Deprecation warnings for remaining Rails.logger
config.rails_logger do
  warn_on_rails_logger_usage true
  # → Logs warning when Rails.logger is used
  # "DEPRECATION: Rails.logger at app/controllers/users_controller.rb:42"
end
```

---

## 💻 Implementation Examples

### Example 1: Auto-Conversion (Quick Start)

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.rails_logger do
    # Intercept ALL Rails.logger calls
    intercept_rails_logger true
    
    # Auto-convert to E11y events
    auto_convert_to_events true
    
    # Extract structured data from log messages
    extract_structured_data do
      # Pattern: "Order 123 created by user 456"
      pattern /Order (\d+) created by user (\d+)/ do |match|
        {
          event_name: 'order.created',
          order_id: match[1],
          user_id: match[2]
        }
      end
      
      # Pattern: "Payment failed: Card declined"
      pattern /Payment failed: (.+)/ do |match|
        {
          event_name: 'payment.failed',
          error: match[1],
          severity: :error
        }
      end
      
      # Default: Generic log event
      fallback do |message, severity|
        {
          event_name: 'rails.log',
          message: message,
          severity: severity
        }
      end
    end
  end
end

# Existing code (unchanged):
Rails.logger.info "Order 123 created by user 456"

# Auto-converted to:
Events::OrderCreated.track(
  order_id: '123',
  user_id: '456'
)

# In Grafana:
# {event_name="order.created",order_id="123",user_id="456"}
```

---

### Example 2: Manual Migration (Controllers)

```ruby
# === BEFORE ===
# app/controllers/orders_controller.rb
class OrdersController < ApplicationController
  def create
    Rails.logger.info "Creating order for user #{current_user.id}"
    
    order = Order.create!(order_params)
    
    Rails.logger.info "Order #{order.id} created with total #{order.total}"
    
    render json: order
  rescue => e
    Rails.logger.error "Failed to create order: #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end
end

# === AFTER ===
# app/events/order_creation_started.rb
module Events
  class OrderCreationStarted < E11y::Event::Base
    schema do
      required(:user_id).filled(:string)
    end
  end
end

# app/events/order_created.rb
module Events
  class OrderCreated < E11y::Event::Base
    severity :success
    
    schema do
      required(:order_id).filled(:string)
      required(:user_id).filled(:string)
      required(:total).filled(:decimal)
      required(:items_count).filled(:integer)
    end
    
    metric :counter, name: 'orders.created.total', tags: [:user_segment]
  end
end

# app/events/order_creation_failed.rb
module Events
  class OrderCreationFailed < E11y::Event::Base
    severity :error
    
    schema do
      required(:user_id).filled(:string)
      required(:error).filled(:string)
    end
  end
end

# app/controllers/orders_controller.rb
class OrdersController < ApplicationController
  def create
    # ✅ Structured event (better than Rails.logger!)
    Events::OrderCreationStarted.track(user_id: current_user.id)
    
    order = Order.create!(order_params)
    
    # ✅ Rich structured data + automatic metrics
    Events::OrderCreated.track(
      order_id: order.id,
      user_id: current_user.id,
      total: order.total,
      items_count: order.items.count
    )
    
    render json: order
  rescue => e
    # ✅ Error tracking with context
    Events::OrderCreationFailed.track(
      user_id: current_user.id,
      error: e.message
    )
    
    render json: { error: e.message }, status: :unprocessable_entity
  end
end

# Benefits:
# ✅ Structured data (can query by order_id, user_id)
# ✅ Automatic metrics (orders.created.total counter)
# ✅ Type-safe (schema validation)
# ✅ Searchable in Grafana
```

---

### Example 3: Background Jobs Migration

```ruby
# === BEFORE ===
# app/jobs/process_order_job.rb
class ProcessOrderJob < ApplicationJob
  def perform(order_id)
    Rails.logger.info "Starting order processing: #{order_id}"
    
    order = Order.find(order_id)
    
    Rails.logger.debug "Checking inventory for order #{order_id}"
    check_inventory(order)
    
    Rails.logger.debug "Capturing payment for order #{order_id}"
    capture_payment(order)
    
    Rails.logger.info "Order #{order_id} processed successfully"
  rescue => e
    Rails.logger.error "Order processing failed: #{order_id} - #{e.message}"
    raise
  end
end

# === AFTER ===
# app/jobs/process_order_job.rb
class ProcessOrderJob < ApplicationJob
  def perform(order_id)
    # E11y auto-tracks job start/end (UC-010)
    # Just track business events!
    
    order = Order.find(order_id)
    
    Events::InventoryCheckStarted.track(order_id: order.id)
    check_inventory(order)
    Events::InventoryCheckCompleted.track(
      order_id: order.id,
      items_available: true
    )
    
    Events::PaymentCaptureStarted.track(order_id: order.id)
    capture_payment(order)
    Events::PaymentCaptured.track(
      order_id: order.id,
      amount: order.total,
      severity: :success
    )
    
  rescue => e
    Events::OrderProcessingFailed.track(
      order_id: order_id,
      error: e.message,
      severity: :error
    )
    raise
  end
end

# Benefits:
# ✅ Job lifecycle auto-tracked (start, end, retries)
# ✅ Trace ID preserved from enqueue
# ✅ Business events clearly separated
# ✅ Can build metrics/dashboards easily
```

---

### Example 4: Service Objects Migration

```ruby
# === BEFORE ===
# app/services/payment_service.rb
class PaymentService
  def call(order)
    Rails.logger.info "Processing payment for order #{order.id}"
    
    Rails.logger.debug "Card: #{order.card.last4}"
    Rails.logger.debug "Amount: #{order.total}"
    
    result = StripeGateway.charge(
      amount: order.total,
      card: order.card.token
    )
    
    Rails.logger.info "Payment succeeded: #{result.id}"
    
    result
  rescue StripeGateway::Error => e
    Rails.logger.error "Payment failed: #{e.message}"
    raise
  end
end

# === AFTER ===
# app/services/payment_service.rb
class PaymentService
  def call(order)
    Events::PaymentProcessingStarted.track(
      order_id: order.id,
      amount: order.total,
      payment_method: 'stripe'
    )
    
    result = StripeGateway.charge(
      amount: order.total,
      card: order.card.token
    )
    
    Events::PaymentSucceeded.track(
      order_id: order.id,
      transaction_id: result.id,
      amount: order.total,
      card_last4: order.card.last4,
      severity: :success
    )
    
    result
  rescue StripeGateway::Error => e
    Events::PaymentFailed.track(
      order_id: order.id,
      amount: order.total,
      error_code: e.code,
      error_message: e.message,
      severity: :error
    )
    raise
  end
end

# Benefits:
# ✅ No sensitive data logged (card details filtered)
# ✅ Structured data (can aggregate by error_code)
# ✅ Success tracking (severity: :success)
# ✅ Automatic metrics
```

---

## 🔧 Configuration

### Migration Configuration

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.rails_logger do
    # === PHASE 1: SHADOW MODE ===
    # Intercept Rails.logger but keep original behavior
    intercept_rails_logger true
    mirror_to_rails_logger true  # ← Both systems!
    
    # === PHASE 2: GRADUAL CONVERSION ===
    # Auto-convert Rails.logger to E11y events
    auto_convert_to_events true
    
    # Pattern extraction (parse log messages)
    extract_patterns do
      # Order events
      pattern /Order (\d+) created/, event: 'order.created' do |match|
        { order_id: match[1] }
      end
      
      # User events
      pattern /User (\d+) logged in/, event: 'user.logged_in' do |match|
        { user_id: match[1] }
      end
      
      # Payment events
      pattern /Payment (\w+) for order (\d+)/, event: 'payment.status' do |match|
        { status: match[1], order_id: match[2] }
      end
      
      # Generic fallback
      fallback event: 'rails.log' do |message, severity|
        { message: message, original_severity: severity }
      end
    end
    
    # Severity mapping
    severity_mapping do
      debug -> :debug
      info -> :info
      warn -> :warn
      error -> :error
      fatal -> :fatal
      unknown -> :warn
    end
    
    # === PHASE 3: FULL MIGRATION ===
    # Turn off mirroring (E11y only!)
    # mirror_to_rails_logger false
    
    # Deprecation warnings
    warn_on_rails_logger_usage true
    deprecation_message "Please use E11y events instead of Rails.logger"
    
    # Exceptions (still use Rails.logger)
    ignore_callers [
      /vendor\/bundle/,      # Gems
      /config\/initializers/, # Initializers
      /health_check/         # Health checks
    ]
  end
end
```

---

## 📊 Migration Progress Tracking

### Built-in Metrics

```ruby
# Automatic metrics for migration progress
# e11y_rails_logger_intercepted_total{severity} - Rails.logger calls intercepted
# e11y_rails_logger_converted_total{pattern} - Auto-converted to events
# e11y_rails_logger_fallback_total - Calls using fallback (not matched)
# e11y_direct_events_total{event_name} - Direct EventClass.track calls

# Grafana Dashboard:
# Panel 1: Migration Progress
# (e11y_direct_events_total / (e11y_direct_events_total + e11y_rails_logger_intercepted_total)) * 100

# Panel 2: Rails.logger Usage (should decrease over time)
# sum(rate(e11y_rails_logger_intercepted_total[1h]))

# Panel 3: Pattern Coverage (how many logs are structured?)
# e11y_rails_logger_converted_total / e11y_rails_logger_intercepted_total
```

---

## 🧪 Testing

```ruby
# spec/support/e11y_migration_helper.rb
RSpec.configure do |config|
  config.around(:each, :e11y_migration) do |example|
    # Test both modes
    
    # Test 1: Shadow mode (both systems)
    E11y.configure do |c|
      c.rails_logger.mirror_to_rails_logger = true
    end
    example.run
    
    # Test 2: E11y only mode
    E11y.configure do |c|
      c.rails_logger.mirror_to_rails_logger = false
    end
    example.run
  end
end

# spec/controllers/orders_controller_spec.rb
RSpec.describe OrdersController, :e11y_migration do
  describe 'POST #create' do
    it 'tracks order creation' do
      # Works with both Rails.logger and E11y
      expect {
        post :create, params: { order: order_params }
      }.to track_event('order.created')
    end
  end
end

# spec/migration/rails_logger_coverage_spec.rb
RSpec.describe 'Rails.logger migration coverage' do
  it 'has converted all critical paths' do
    # Check that critical areas don't use Rails.logger
    critical_files = [
      'app/controllers/orders_controller.rb',
      'app/services/payment_service.rb',
      'app/jobs/process_order_job.rb'
    ]
    
    critical_files.each do |file|
      content = File.read(Rails.root.join(file))
      expect(content).not_to match(/Rails\.logger/)
    end
  end
  
  it 'tracks migration progress' do
    # Count Rails.logger usage
    rails_logger_count = 0
    e11y_track_count = 0
    
    Dir['app/**/*.rb'].each do |file|
      content = File.read(file)
      rails_logger_count += content.scan(/Rails\.logger/).count
      e11y_track_count += content.scan(/Events::\w+\.track/).count
    end
    
    # Expect at least 80% migrated
    migration_pct = (e11y_track_count.to_f / (rails_logger_count + e11y_track_count)) * 100
    expect(migration_pct).to be >= 80
  end
end
```

---

## 💡 Best Practices

### ✅ DO

**1. Migrate in phases (safe!)**
```ruby
# ✅ GOOD: Gradual migration
# Week 1-2: Shadow mode (both systems)
# Week 3-6: Convert high-value areas
# Week 7+: Turn off mirroring
```

**2. Start with new features**
```ruby
# ✅ GOOD: New code uses E11y from day 1
class NewFeatureController < ApplicationController
  def action
    Events::NewFeatureUsed.track(...)  # ← E11y!
  end
end
```

**3. Convert high-value areas first**
```ruby
# ✅ GOOD: Priority order
# 1. Authentication (security)
# 2. Payments (money!)
# 3. Orders (business critical)
# 4. Background jobs (async visibility)
# 5. Everything else
```

**4. Use auto-conversion for long tail**
```ruby
# ✅ GOOD: Auto-convert remaining Rails.logger
config.rails_logger do
  auto_convert_to_events true  # Handles stragglers
end
```

---

### ❌ DON'T

**1. Don't migrate everything at once**
```ruby
# ❌ BAD: Big bang migration (risky!)
# - Replace all 1000+ Rails.logger calls in one PR
# - Deploy to production
# - Hope nothing breaks 🤞

# ✅ GOOD: Incremental migration
# - Week 1: Shadow mode
# - Week 2: 10 controllers
# - Week 3: 15 jobs
# - etc.
```

**2. Don't break existing functionality**
```ruby
# ❌ BAD: Turn off Rails.logger immediately
config.rails_logger.mirror_to_rails_logger = false
# → Existing code breaks! 💥

# ✅ GOOD: Keep mirroring during migration
config.rails_logger.mirror_to_rails_logger = true
# → Both systems work ✅
```

**3. Don't lose log context**
```ruby
# ❌ BAD: Unstructured conversion
Rails.logger.info "Order 123 created by user 456"
# → Events::RailsLog.track(message: "Order 123 created by user 456")
# Still unstructured! 😞

# ✅ GOOD: Extract structure
Events::OrderCreated.track(
  order_id: '123',
  user_id: '456'
)
# Queryable, structured! 🎉
```

---

## 📚 Related Use Cases

- **[UC-002: Business Event Tracking](./UC-002-business-event-tracking.md)** - E11y events basics
- **[UC-017: Local Development](./UC-017-local-development.md)** - Development setup
- **[UC-018: Testing Events](./UC-018-testing-events.md)** - Testing strategies

---

## 🎯 Summary

### Migration Timeline

| Phase | Duration | Risk | Status |
|-------|----------|------|--------|
| **Phase 1: Shadow Mode** | 1-2 weeks | Low (no changes) | Both systems run |
| **Phase 2: Gradual Conversion** | 4-6 weeks | Low (incremental) | Convert high-value areas |
| **Phase 3: Full Migration** | 1+ weeks | Medium (turn off mirror) | E11y only |
| **TOTAL** | **6-9 weeks** | **Low overall** | Gradual, safe |

### Benefits After Migration

| Before (Rails.logger) | After (E11y) |
|----------------------|--------------|
| Unstructured text | Structured events |
| Hard to search | Easy queries (Grafana) |
| No metrics | Automatic metrics |
| No correlation | Trace ID everywhere |
| Manual parsing | Type-safe schemas |
| No validation | Schema validation |

**Developer Experience:**
- Migration: 6-9 weeks for typical Rails app
- Per feature: 15-30 min to convert
- Testing: Works with both systems
- Risk: Low (gradual, reversible)

---

**Document Version:** 1.0  
**Last Updated:** January 12, 2026  
**Status:** ✅ Complete

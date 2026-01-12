# UC-020: Event Versioning & Schema Evolution

**Status:** Core Feature (MVP)  
**Complexity:** Intermediate  
**Setup Time:** 15-30 minutes  
**Target Users:** Backend Developers, API Designers, Platform Engineers

---

## 📋 Overview

### Problem Statement

**Current Pain Points:**

1. **Breaking schema changes break production**
   - Add required field → old code crashes
   - Remove field → downstream consumers fail
   - Rename field → data loss

2. **No backward compatibility**
   - Can't deploy new event schema without coordinating all consumers
   - Microservices must upgrade simultaneously (impossible!)
   - Rollback is dangerous (data already sent with new schema)

3. **No schema evolution strategy**
   - How to deprecate old fields?
   - How to support multiple versions simultaneously?
   - How to migrate consumers gradually?

### E11y Solution

**Event Versioning with Backward Compatibility:**

- Events have explicit version numbers
- Multiple versions can coexist
- Automatic version detection from payload
- Gradual migration path

**Result:** Safe schema evolution without breaking production.

---

## 🎯 Use Case Scenarios

### Scenario 1: Adding Required Field (Breaking Change)

**Problem:** Need to add required `currency` field to `OrderPaid` event.

**Without versioning (BREAKS PRODUCTION!):**
```ruby
class OrderPaid < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:decimal)
    required(:currency).filled(:string)  # ← NEW! Breaks old code!
  end
end

# Old code (deployed):
OrderPaid.track(order_id: '123', amount: 99.99)
# ❌ ValidationError: currency is required
```

**With versioning (SAFE!):**
```ruby
# V1: Original version (no version suffix!)
class OrderPaid < E11y::Event::Base
  version 1  # Optional for v1, but recommended
  event_name 'order.paid'
  
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:decimal)
    # No currency (backward compatible)
  end
end

# V2: New version with currency (suffix V2)
class OrderPaidV2 < E11y::Event::Base
  version 2
  event_name 'order.paid'
  
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:decimal)
    required(:currency).filled(:string)  # ← New required field
  end
end

# Old code (still deployed):
OrderPaid.track(order_id: '123', amount: 99.99)
# ✅ Works! Sends version: 1

# New code (gradual rollout):
OrderPaidV2.track(order_id: '123', amount: 99.99, currency: 'USD')
# ✅ Works! Sends version: 2

# Downstream consumers can handle both versions!
```

---

### Scenario 2: Renaming Field (Breaking Change)

**Problem:** Need to rename `user_id` → `customer_id` for consistency.

```ruby
# V1: Original version (no suffix)
class UserSignup < E11y::Event::Base
  version 1
  event_name 'user.signup'
  
  schema do
    required(:user_id).filled(:string)  # ← Old name
    required(:email).filled(:string)
  end
  
  # Optional: Auto-map to V2 format
  def to_v2
    UserSignupV2.new(
      customer_id: payload[:user_id],  # Map old → new
      email: payload[:email]
    )
  end
end

# V2: New field name (V2 suffix)
class UserSignupV2 < E11y::Event::Base
  version 2
  event_name 'user.signup'
  
  schema do
    required(:customer_id).filled(:string)  # ← Renamed
    required(:email).filled(:string)
  end
end

# Migration path:
# 1. Deploy V2 event class (both versions coexist)
# 2. Update tracking calls gradually (service by service)
# 3. Monitor: no more V1 events for 30 days
# 4. Deprecate V1 class
```

---

### Scenario 3: Removing Field (Breaking Change)

**Problem:** Remove sensitive field that shouldn't have been logged.

```ruby
# V1: Old version with sensitive field (DEPRECATED)
class PaymentProcessed < E11y::Event::Base
  version 1
  event_name 'payment.processed'
  deprecated true  # Mark as deprecated
  deprecation_warning 'Use PaymentProcessedV2. V1 will be removed 2026-06-01'
  
  schema do
    required(:transaction_id).filled(:string)
    required(:amount).filled(:decimal)
    optional(:card_number).filled(:string)  # ← SECURITY ISSUE!
  end
  
  # Emit deprecation warning
  after_track do |event|
    Rails.logger.warn "DEPRECATED: PaymentProcessed (v1). Use PaymentProcessedV2."
  end
end

# V2: Removed sensitive field (V2 suffix)
class PaymentProcessedV2 < E11y::Event::Base
  version 2
  event_name 'payment.processed'
  
  schema do
    required(:transaction_id).filled(:string)
    required(:amount).filled(:decimal)
    # card_number REMOVED (was security issue!)
  end
end
```

---

## 🏗️ Architecture

### Version Management

```
┌─────────────────────────────────────────────────────────────────┐
│ Event Registry (tracks all versions)                            │
│                                                                  │
│  event_name: 'order.paid'                                       │
│    ├─ V1: OrderPaidV1                                           │
│    ├─ V2: OrderPaidV2 (current)                                 │
│    └─ V3: OrderPaidV3 (future)                                  │
│                                                                  │
│  current_version: 2                                             │
│  deprecated_versions: [1]                                       │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ Event Payload (includes version)                                │
│                                                                  │
│  {                                                               │
│    "@timestamp": "2026-01-12T10:30:00Z",                        │
│    "event_name": "order.paid",                                  │
│    "event_version": 2,        ← Version included!               │
│    "payload": {                                                  │
│      "order_id": "123",                                          │
│      "amount": 99.99,                                            │
│      "currency": "USD"        ← New field in V2                 │
│    }                                                             │
│  }                                                               │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔧 Configuration

### Basic Setup

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.versioning do
    enabled true
    
    # Include version in event payload
    include_version_in_payload true
    version_field :event_version  # Field name
    
    # Deprecation warnings
    warn_on_deprecated_version true
    deprecation_log_level :warn  # :info, :warn, :error
    
    # Automatic version detection
    auto_detect_version true  # From payload structure
  end
end
```

### Advanced: Version Migration

```ruby
E11y.configure do |config|
  config.versioning do
    enabled true
    
    # Auto-upgrade old versions
    auto_upgrade_to_current do
      enabled false  # Disabled by default (explicit migration)
      
      # If enabled, V1 events auto-converted to V2
      upgrade 'order.paid' do
        from_version 1
        to_version 2
        
        transform do |v1_payload|
          v2_payload = v1_payload.dup
          v2_payload[:currency] = 'USD'  # Add default for missing field
          v2_payload
        end
      end
    end
    
    # Deprecation enforcement
    deprecation_enforcement do
      # After this date, V1 events rejected
      enforce_after '2026-06-01'
      
      # What to do with deprecated versions after enforce_after
      on_deprecated_version :reject  # :reject, :warn, :upgrade
    end
  end
end
```

---

## 📝 Event Definition Examples

### Example 1: Simple Versioning

```ruby
# app/events/order_paid.rb (V1 - no suffix!)
module Events
  class OrderPaid < E11y::Event::Base
    version 1  # Explicit version (recommended)
    event_name 'order.paid'
    
    schema do
      required(:order_id).filled(:string)
      required(:amount).filled(:decimal)
    end
  end
end

# app/events/order_paid_v2.rb (V2+ - with suffix!)
module Events
  class OrderPaidV2 < E11y::Event::Base
    version 2
    event_name 'order.paid'
    
    schema do
      required(:order_id).filled(:string)
      required(:amount).filled(:decimal)
      required(:currency).filled(:string)  # New required field
    end
    
    # Default version (latest)
    default_version true
  end
end

# Usage:
# Old code:
Events::OrderPaid.track(order_id: '123', amount: 99.99)  # V1

# New code:
Events::OrderPaidV2.track(order_id: '123', amount: 99.99, currency: 'USD')  # V2

# Or use version-agnostic routing (requires config):
E11y::Registry.track('order.paid', order_id: '123', ...)  # → Routes to default_version (V2)
```

### Example 2: With Deprecation

```ruby
module Events
  # V1 (no suffix, but deprecated)
  class UserLogin < E11y::Event::Base
    version 1
    event_name 'user.login'
    
    # Mark as deprecated
    deprecated true
    deprecation_date '2026-03-01'
    deprecation_message 'Use UserLoginV2 with ip_address field'
    
    schema do
      required(:user_id).filled(:string)
      required(:success).filled(:bool)
    end
    
    # Emit warning on each track
    after_track do |event|
      Rails.logger.warn "[DEPRECATED] UserLogin (v1) used. Migrate to V2 by 2026-03-01"
    end
  end
  
  # V2+ (with suffix)
  class UserLoginV2 < E11y::Event::Base
    version 2
    event_name 'user.login'
    default_version true
    
    schema do
      required(:user_id).filled(:string)
      required(:success).filled(:bool)
      required(:ip_address).filled(:string)  # New security requirement
    end
  end
end
```

### Example 3: With Auto-Migration

```ruby
module Events
  # V1 (no suffix)
  class OrderShipped < E11y::Event::Base
    version 1
    event_name 'order.shipped'
    
    schema do
      required(:order_id).filled(:string)
      required(:tracking_number).filled(:string)
    end
    
    # Define migration to V2
    def migrate_to_v2
      OrderShippedV2.new(
        order_id: payload[:order_id],
        tracking_number: payload[:tracking_number],
        carrier: 'USPS'  # Default for old events
      )
    end
  end
  
  # V2+ (with suffix)
  class OrderShippedV2 < E11y::Event::Base
    version 2
    event_name 'order.shipped'
    default_version true
    
    schema do
      required(:order_id).filled(:string)
      required(:tracking_number).filled(:string)
      required(:carrier).filled(:string)  # New required field
    end
  end
end

# Configuration for auto-migration:
E11y.configure do |config|
  config.versioning.auto_upgrade do
    upgrade 'order.shipped' do
      from_version 1
      to_version 2
      transform_method :migrate_to_v2  # Call event.migrate_to_v2
    end
  end
end
```

---

## 💡 Best Practices

### ✅ DO

**1. Always increment version for breaking changes**
```ruby
# ✅ GOOD: New version for breaking change
class OrderPaidV2 < E11y::Event::Base
  version 2  # ← Incremented
  event_name 'order.paid'
  
  schema do
    required(:currency).filled(:string)  # ← New required field
  end
end
```

**2. Keep old versions for backward compatibility**
```ruby
# ✅ GOOD: Keep V1 around during migration
class OrderPaid < E11y::Event::Base  # V1 (no suffix)
  version 1
  deprecated true  # Mark as deprecated
  deprecation_date '2026-06-01'
end

class OrderPaidV2 < E11y::Event::Base  # V2+ (with suffix)
  version 2
  default_version true
end

# Remove OrderPaid (v1) after deprecation_date + grace period
```

**3. Document breaking changes**
```ruby
# ✅ GOOD: Clear documentation
class PaymentProcessedV2 < E11y::Event::Base
  version 2
  
  # BREAKING CHANGES from V1:
  # - Removed: card_number (security)
  # - Added: payment_method_id (reference)
  # - Renamed: user_id → customer_id
  
  schema do
    required(:customer_id).filled(:string)  # Was: user_id
    required(:payment_method_id).filled(:string)  # New
  end
end
```

**4. Use semantic versioning for major changes**
```ruby
# ✅ GOOD: Major version for major changes
class OrderPaidV1 < E11y::Event::Base
  version 1  # Initial version
end

class OrderPaidV2 < E11y::Event::Base
  version 2  # Added currency field
end

class OrderPaidV3 < E11y::Event::Base
  version 3  # Restructured to support multi-currency
end
```

---

### ❌ DON'T

**1. Don't change schema without versioning**
```ruby
# ❌ BAD: Changed schema without version increment
class OrderPaid < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:decimal)
    required(:currency).filled(:string)  # ← Added without version++
  end
end
# This BREAKS old code in production!
```

**2. Don't delete old versions prematurely**
```ruby
# ❌ BAD: Deleted V1 (OrderPaid) immediately
# Old services still sending V1 events → errors!

# ✅ GOOD: Deprecate first, delete after grace period
class OrderPaid < E11y::Event::Base  # V1
  deprecated true
  deprecation_date '2026-06-01'
end

# Monitor for 30 days after deprecation_date
# Delete OrderPaid (v1) class only when no more V1 events tracked
```

**3. Don't use version for non-breaking changes**
```ruby
# ❌ BAD: Version increment for optional field
class OrderPaidV2 < E11y::Event::Base
  version 2  # ← Unnecessary!
  
  schema do
    required(:order_id).filled(:string)
    optional(:notes).filled(:string)  # ← Optional = not breaking!
  end
end

# ✅ GOOD: Just add optional field to existing version
class OrderPaid < E11y::Event::Base
  version 1  # Same version
  
  schema do
    required(:order_id).filled(:string)
    optional(:notes).filled(:string)  # ← Optional = backward compatible
  end
end
```

---

## 🎯 Migration Strategy

### Phase 1: Deploy New Version (Coexistence)

```ruby
# Week 1: Deploy both versions
# - V1 still works (backward compatible)
# - V2 available for new code

# app/events/order_paid.rb (existing V1 - no suffix)
class OrderPaid < E11y::Event::Base
  version 1
end

# app/events/order_paid_v2.rb (new V2 - with suffix)
class OrderPaidV2 < E11y::Event::Base
  version 2
  default_version true  # New default
end
```

### Phase 2: Gradual Migration

```ruby
# Week 2-4: Migrate services one by one

# Service A (updated):
Events::OrderPaidV2.track(order_id: '123', amount: 99.99, currency: 'USD')

# Service B (not updated yet):
Events::OrderPaid.track(order_id: '456', amount: 49.99)  # V1 still works!

# Monitor:
# - % of V1 vs V2 events
# - Which services still use V1
```

### Phase 3: Deprecation Warning

```ruby
# Week 5: Mark V1 as deprecated
class OrderPaid < E11y::Event::Base  # V1
  version 1
  deprecated true
  deprecation_date '2026-06-01'  # 30 days from now
  
  after_track do |event|
    # Emit warning
    Rails.logger.warn "DEPRECATED: OrderPaid (v1). Migrate by 2026-06-01"
    
    # Track deprecation usage
    Events::DeprecatedEventUsed.track(
      event_class: 'OrderPaid',
      event_version: 1,
      service: ENV['SERVICE_NAME']
    )
  end
end
```

### Phase 4: Enforcement

```ruby
# After 2026-06-01: Reject V1 events
E11y.configure do |config|
  config.versioning.deprecation_enforcement do
    enforce_after '2026-06-01'
    on_deprecated_version :reject  # Reject V1 events
  end
end

# Or auto-upgrade:
E11y.configure do |config|
  config.versioning.auto_upgrade do
    upgrade 'order.paid' do
      from_version 1
      to_version 2
      transform { |v1| v1.merge(currency: 'USD') }  # Default currency
    end
  end
end
```

### Phase 5: Cleanup

```ruby
# 30 days after enforcement: Delete V1 class
# 1. Verify zero V1 events in last 30 days
# 2. Remove OrderPaid (v1) class file: app/events/order_paid.rb
# 3. Rename OrderPaidV2 → OrderPaid (optional, for next v3 migration)
# 4. Update documentation
```

---

## 📊 Monitoring & Metrics

### Version Usage Metrics

```ruby
# E11y automatically tracks version usage
E11y.metrics do
  counter :events_by_version_total,
          tags: [:event_name, :version],
          comment: 'Events tracked by version'
  
  gauge :deprecated_events_active,
        tags: [:event_name, :version],
        comment: 'Deprecated versions still in use'
end

# Prometheus queries:
# events_by_version_total{event_name="order.paid", version="1"}
# events_by_version_total{event_name="order.paid", version="2"}

# Alert when deprecated version usage > 0 after deprecation_date
```

### Deprecation Dashboard

```ruby
# Grafana dashboard queries:

# % of events by version
sum(rate(events_by_version_total{event_name="order.paid"}[5m])) by (version)

# Services still using deprecated versions
sum(deprecated_events_active) by (service, event_name, version)

# Days until deprecation enforcement
(deprecation_date - now()) / 86400
```

---

## 🔗 Related Use Cases

- **[UC-002: Business Event Tracking](./UC-002-business-event-tracking.md)** - Event schema definition
- **[UC-018: Testing Events](./UC-018-testing-events.md)** - Testing versioned events
- **[UC-016: Rails Logger Migration](./UC-016-rails-logger-migration.md)** - Migration strategies

---

## 🚀 Quick Start Checklist

- [ ] Enable versioning in config
- [ ] Define V2 event class with new schema
- [ ] Keep V1 event class (backward compatible)
- [ ] Update tracking calls gradually
- [ ] Monitor version usage metrics
- [ ] Mark V1 as deprecated
- [ ] Set deprecation_date
- [ ] Enforce after grace period
- [ ] Delete old version after 30 days no usage

---

**Status:** ✅ Core Feature  
**Priority:** High (schema evolution is critical)  
**Complexity:** Intermediate

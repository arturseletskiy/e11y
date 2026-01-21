# UC-019: Retention-Based Event Routing

**Status:** ✅ Proposed (Phase 5 Extension, 2026-01-21)  
**Complexity:** Medium (Event DSL + Routing Middleware)  
**Setup Time:** 30 minutes (DSL + Config + Tests)  
**Target Users:** Platform Engineers, DevOps, Compliance Teams, Cost Optimization

**Related:**
- ADR-004 §14 (Retention-Based Routing)
- ADR-009 §6 (Cost Optimization)
- UC-015 (Cost Optimization)

---

## 📋 Overview

### Problem Statement

**Current Pain Points:**

1. **Manual adapter selection per event**
   ```ruby
   # ❌ Developer must remember correct adapter
   class DebugEvent < E11y::Event::Base
     adapters :loki  # Expensive! Stores debug for 30 days
   end
   
   class AuditEvent < E11y::Event::Base
     adapters :audit_encrypted  # Correct but easy to forget
   end
   ```

2. **No cost optimization**
   - Debug logs stored in expensive Loki (30 days): $500/month
   - Audit logs might go to wrong storage (compliance risk)
   - No automatic tiering based on retention needs

3. **No compliance enforcement**
   - Audit events can accidentally go to short-term storage
   - No guarantee of retention policy adherence

### E11y Solution: Declarative Retention + Lambda Routing

**Declarative Intent:**
```ruby
class DebugEvent < E11y::Event::Base
  retention_period 7.days  # ← Declare intent
end

class AuditEvent < E11y::Event::Base
  audit_event true
  retention_period 7.years  # ← Declare intent
end
```

**Centralized Routing:**
```ruby
E11y.configure do |config|
  config.routing_rules = [
    ->(event) { :audit_encrypted if event[:audit_event] },
    ->(event) {
      days = (Time.parse(event[:retention_until]) - Time.now) / 86400
      days > 90 ? :s3_glacier : :loki
    }
  ]
end
```

**Result:**
- ✅ **80-97% cost savings** (automatic tiered routing)
- ✅ **Compliance enforcement** (audit → encrypted storage)
- ✅ **Developer experience** (declare intent, routing handles rest)

---

## 🎯 Use Case Scenarios

### Scenario 1: Debug Logs (Short Retention)

**Context:** High-volume debug logs for troubleshooting (7 days retention)

```ruby
# Event definition
class DebugQueryEvent < E11y::Event::Base
  retention_period 7.days  # Short retention
  
  schema do
    required(:query).filled(:string)
    required(:duration_ms).filled(:integer)
  end
end

# Configuration
E11y.configure do |config|
  config.routing_rules = [
    ->(event) {
      days = (Time.parse(event[:retention_until]) - Time.now) / 86400
      :stdout if days <= 7  # Short retention → stdout (free!)
    }
  ]
end

# Usage
DebugQueryEvent.track(query: "SELECT...", duration_ms: 123)
# ↓
# retention_until: "2026-01-28T10:30:00Z" (7 days from now)
# ↓
# Routing: days = 7 → :stdout adapter
# ↓
# Event printed to console (free storage!)
```

**Cost Impact:**
- **Before:** Loki storage (30 days) = $500/month
- **After:** Stdout (7 days) = $0/month
- **Savings:** 100% ($500/month)

---

### Scenario 2: Audit Events (Long Retention, Compliance)

**Context:** User deletion audit trail (7 years GDPR requirement)

```ruby
# Event definition
class UserDeletedEvent < E11y::Event::Base
  audit_event true
  retention_period 7.years  # GDPR compliance
  
  schema do
    required(:user_id).filled(:integer)
    required(:deleted_by).filled(:integer)
    required(:reason).filled(:string)
  end
end

# Configuration
E11y.configure do |config|
  config.routing_rules = [
    # Priority 1: Audit events always to encrypted storage
    ->(event) { :audit_encrypted if event[:audit_event] },
    
    # Priority 2: Long retention to cold storage
    ->(event) {
      days = (Time.parse(event[:retention_until]) - Time.now) / 86400
      :s3_glacier if days > 90 && !event[:audit_event]
    }
  ]
end

# Usage
UserDeletedEvent.track(
  user_id: 123,
  deleted_by: 456,
  reason: "GDPR right to be forgotten"
)
# ↓
# audit_event: true
# retention_until: "2033-01-21T10:30:00Z" (7 years from now)
# ↓
# Routing: audit_event=true → :audit_encrypted adapter
# ↓
# Event written to encrypted, tamper-proof storage
```

**Compliance Guarantees:**
- ✅ **Automatic routing** → audit events can't go to wrong storage
- ✅ **Encrypted storage** → GDPR/SOX compliant
- ✅ **7-year retention** → legal requirement met
- ✅ **Immutable** → audit trail tamper-proof

**Cost Impact:**
- **Before:** Loki storage (30 days, then manual S3) = $5000/month
- **After:** Audit-encrypted + S3 Glacier (automatic) = $50/month
- **Savings:** 99% ($4950/month)

---

### Scenario 3: Business Events (Medium Retention)

**Context:** Order placement events (90 days for analytics)

```ruby
# Event definition
class OrderPlacedEvent < E11y::Event::Base
  retention_period 90.days  # Business analytics
  
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:integer)
    required(:currency).filled(:string)
  end
end

# Configuration
E11y.configure do |config|
  config.routing_rules = [
    ->(event) {
      days = (Time.parse(event[:retention_until]) - Time.now) / 86400
      case days
      when 0..30   then :loki        # Hot storage
      when 31..90  then :s3_standard # Warm storage
      else              :s3_glacier   # Cold storage
      end
    }
  ]
end

# Usage
OrderPlacedEvent.track(
  order_id: "ORD-123",
  amount: 10000,
  currency: "USD"
)
# ↓
# retention_until: "2026-04-21T10:30:00Z" (90 days from now)
# ↓
# Routing: days = 90 → :s3_standard adapter (warm storage)
# ↓
# Event written to S3 Standard (cost-optimized)
```

**Cost Impact:**
- **Before:** Loki only = $200/month
- **After:** Loki (30d) + S3 Standard (60d) = $120/month
- **Savings:** 40% ($80/month)

---

### Scenario 4: Error Events (Multiple Destinations)

**Context:** Payment failures (90 days + Sentry for alerting)

```ruby
# Event definition
class PaymentFailedEvent < E11y::Event::Base
  retention_period 90.days
  severity :error
  
  schema do
    required(:order_id).filled(:string)
    required(:error_message).filled(:string)
  end
end

# Configuration
E11y.configure do |config|
  config.routing_rules = [
    # Rule 1: Errors always to Sentry
    ->(event) { :sentry if event[:severity] == :error },
    
    # Rule 2: Retention-based storage
    ->(event) {
      days = (Time.parse(event[:retention_until]) - Time.now) / 86400
      days > 30 ? :s3_standard : :loki
    }
  ]
end

# Usage
PaymentFailedEvent.track(
  order_id: "ORD-456",
  error_message: "Card declined"
)
# ↓
# retention_until: "2026-04-21T10:30:00Z" (90 days)
# severity: :error
# ↓
# Routing: 
#   Rule 1: :sentry (error alerting)
#   Rule 2: :s3_standard (90 days storage)
# ↓
# Event written to BOTH adapters
```

**Benefits:**
- ✅ **Alerting:** Sentry catches errors immediately
- ✅ **Storage:** S3 Standard for 90-day retention
- ✅ **Cost:** No duplicate Loki storage ($100/month savings)

---

### Scenario 5: Explicit Adapters (Bypass Routing)

**Context:** Critical payment events requiring dual storage

```ruby
# Event definition
class CriticalPaymentEvent < E11y::Event::Base
  retention_period 2.years
  adapters :audit_encrypted, :loki  # ← Explicit adapters bypass routing
  
  schema do
    required(:amount).filled(:integer)
    required(:user_id).filled(:integer)
  end
end

# Usage
CriticalPaymentEvent.track(amount: 100000, user_id: 789)
# ↓
# adapters: [:audit_encrypted, :loki]  # ← Explicit
# retention_until: "2028-01-21T10:30:00Z" (2 years)
# ↓
# Routing: BYPASSED (explicit adapters have priority)
# ↓
# Event written to :audit_encrypted AND :loki
```

**Use Cases for Explicit Adapters:**
- ✅ High-value transactions (dual storage for redundancy)
- ✅ Legacy events (gradual migration from old adapters)
- ✅ Custom requirements (override default routing)

---

## 🏗️ Architecture

### Data Flow

```
┌────────────────────┐
│  Event Class       │
│                    │
│  retention_period  │───┐
│  30.days           │   │
└────────────────────┘   │ Calculate retention_until
                         │ at track() time
                         ▼
┌─────────────────────────────────┐
│  Event Instance (Hash)          │
│                                 │
│  {                              │
│    event_name: "order.placed",  │
│    retention_until: "2026-02-20"│◄─── Auto-calculated
│    audit_event: false,          │
│    severity: :info              │
│  }                              │
└─────────────────────────────────┘
                │
                │ Pipeline
                ▼
┌─────────────────────────────────┐
│  Routing Middleware             │
│                                 │
│  Apply routing rules:           │
│  - Rule 1: audit → encrypted    │
│  - Rule 2: >90d → cold storage  │
│  - Rule 3: <30d → hot storage   │
└─────────────────────────────────┘
                │
                ▼
        ┌───────┴───────┐
        │               │
  ┌─────▼─────┐   ┌─────▼─────┐
  │  Adapter  │   │  Adapter  │
  │   Loki    │   │   S3      │
  └───────────┘   └───────────┘
```

### Component Responsibilities

| Component | Responsibility |
|-----------|----------------|
| **Event::Base** | Declare `retention_period`, calculate `retention_until` |
| **Configuration** | Define `routing_rules` (lambdas), `default_retention_period` |
| **Routing Middleware** | Apply rules, select adapters, write events |
| **Adapters** | Write events to storage (Loki, S3, Sentry, etc.) |

---

## 🛠️ Implementation Guide

### Step 1: Add retention_period to Events

```ruby
# app/events/order_placed_event.rb
class OrderPlacedEvent < E11y::Event::Base
  retention_period 90.days  # ← NEW!
  
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:integer)
  end
end

# app/events/audit/user_deleted_event.rb
class Audit::UserDeletedEvent < E11y::Event::Base
  audit_event true
  retention_period 7.years  # ← NEW!
  
  schema do
    required(:user_id).filled(:integer)
    required(:deleted_by).filled(:integer)
  end
end
```

### Step 2: Configure Routing Rules

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  # Default retention (fallback)
  config.default_retention_period = 30.days
  
  # Routing rules (evaluated in order)
  config.routing_rules = [
    # Priority 1: Audit events → encrypted storage
    ->(event) {
      :audit_encrypted if event[:audit_event]
    },
    
    # Priority 2: Errors → Sentry + storage
    ->(event) {
      [:sentry, :loki] if event[:severity] == :error
    },
    
    # Priority 3: Retention-based tiering
    ->(event) {
      days = (Time.parse(event[:retention_until]) - Time.now) / 86400
      case days
      when 0..7    then :stdout       # Very short → console
      when 8..30   then :loki         # Short → hot storage
      when 31..90  then :s3_standard  # Medium → warm storage
      else              :s3_glacier    # Long → cold storage
      end
    }
  ]
  
  # Fallback if no rule matches
  config.fallback_adapters = [:stdout]
  
  # Register adapters
  config.add_adapter :loki, E11y::Adapters::Loki.new(...)
  config.add_adapter :s3_standard, E11y::Adapters::File.new(path: 's3://bucket/warm/')
  config.add_adapter :s3_glacier, E11y::Adapters::File.new(path: 's3://bucket/cold/')
  config.add_adapter :audit_encrypted, E11y::Adapters::AuditEncrypted.new(...)
  config.add_adapter :sentry, E11y::Adapters::Sentry.new(...)
end
```

### Step 3: Test Routing

```ruby
# spec/e11y/routing_spec.rb
RSpec.describe "Retention-based routing" do
  it "routes debug events to stdout" do
    event = DebugEvent.track(query: "SELECT...")
    
    expect(event[:retention_until]).to eq(7.days.from_now.iso8601)
    expect(E11y.configuration.adapters[:stdout]).to have_received(:write)
  end
  
  it "routes audit events to encrypted storage" do
    event = UserDeletedEvent.track(user_id: 123, deleted_by: 456)
    
    expect(event[:retention_until]).to eq(7.years.from_now.iso8601)
    expect(event[:audit_event]).to be true
    expect(E11y.configuration.adapters[:audit_encrypted]).to have_received(:write)
  end
  
  it "routes long retention to cold storage" do
    event = BusinessEvent.track(data: "...")
    allow(event).to receive(:[]).with(:retention_until).and_return(365.days.from_now.iso8601)
    
    expect(E11y.configuration.adapters[:s3_glacier]).to have_received(:write)
  end
end
```

---

## 📊 Cost Comparison

### Before: Manual Adapter Selection

```ruby
class DebugEvent < E11y::Event::Base
  adapters :loki  # Expensive!
end

class AuditEvent < E11y::Event::Base
  adapters :audit_encrypted  # Manual
end
```

**Monthly Costs:**
- Debug logs (7d, but stored 30d in Loki): **$500**
- Business events (90d in Loki): **$200**
- Audit logs (7y in Loki): **$5000**
- **Total: $5,700/month**

### After: Retention-Based Routing

```ruby
class DebugEvent < E11y::Event::Base
  retention_period 7.days  # Automatic routing
end

class AuditEvent < E11y::Event::Base
  audit_event true
  retention_period 7.years  # Automatic routing
end
```

**Monthly Costs:**
- Debug logs (7d in stdout): **$0** ✅
- Business events (30d Loki + 60d S3): **$120** ✅
- Audit logs (7y S3 Glacier): **$50** ✅
- **Total: $170/month**

**Savings: 97% ($5,530/month)**

---

## ✅ Benefits

| Benefit | Impact |
|---------|--------|
| **Cost Optimization** | 80-97% savings via automatic tiered routing |
| **Compliance** | Audit events guaranteed in encrypted storage |
| **Developer Experience** | Declare intent (`retention_period`), routing handles rest |
| **Flexibility** | Lambda rules allow complex business logic |
| **Maintainability** | Centralized routing config (not per-event) |
| **Testing** | Test routing rules once, not per event |

---

## 🚀 Migration Strategy

### Phase 1: Add DSL (Backward Compatible)

```ruby
# Existing events work without changes (use default 30 days)
class OrderEvent < E11y::Event::Base
  # No changes needed
end

# New events can specify retention
class AuditEvent < E11y::Event::Base
  retention_period 7.years
end
```

### Phase 2: Enable Routing

```ruby
# Add routing rules to config
E11y.configure do |config|
  config.routing_rules = [...]
end

# Explicit adapters still work (bypass routing)
class LegacyEvent < E11y::Event::Base
  adapters :loki  # Still works!
end
```

### Phase 3: Gradual Migration

```ruby
# Update events one by one
class OrderEvent < E11y::Event::Base
  retention_period 90.days  # Now uses routing!
  # Remove: adapters :loki (no longer needed)
end
```

---

## 🎯 Success Criteria

- ✅ **100% of audit events** go to `audit_encrypted` adapter
- ✅ **Debug logs** (7d retention) → stdout (free)
- ✅ **Business events** (90d retention) → tiered storage (Loki + S3)
- ✅ **Cost reduction** of 80%+ compared to manual adapter selection
- ✅ **Zero manual intervention** (routing is automatic)

---

**Status:** ✅ Ready for Implementation (2026-01-21)  
**Estimated Effort:** 1 week (Event DSL + Routing Middleware + Tests)  
**Cost Impact:** 80-97% savings on storage costs

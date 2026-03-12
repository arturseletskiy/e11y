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

**Routing at collection** (where to write now):
```ruby
E11y.configure do |config|
  config.routing_rules = [
    ->(event) { :audit_encrypted if event[:audit_event] },
    ->(event) {
      days = (Time.parse(event[:retention_until]) - Time.now) / 86400
      days <= 7 ? :stdout : :loki  # Short retention → cheap storage at collection
    }
  ]
end
```

**Result:**
- ✅ **Cost savings** (short retention → stdout, not Loki)
- ✅ **Compliance** (audit → encrypted storage)
- ✅ **Developer experience** (declare intent, routing handles rest)

> **Archival is a separate moment.** E11y collects events in real time and writes to Loki (hot storage). Each event carries `retention_until` (ISO8601) in its payload. **Archival** (hot → warm → cold) is done by a **separate job** (cron, Loki compaction, export script) — not at collection time. The job filters logs by `retention_until`: `WHERE retention_until > ?` — simple, no custom logic, easy cost control.

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
    
    # Other events → Loki (archival job handles cold tier later)
    ->(event) { :loki }
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
- **Before:** Loki storage (30 days, manual export) = $5000/month
- **After:** Audit-encrypted at collection; archival job (separate) exports to cold tier by `retention_until` = $50/month
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

# At collection: all events → Loki. retention_until in payload.
# Archival job (cron, separate): filters Loki by retention_until, exports to warm/cold.
E11y.configure do |config|
  config.routing_rules = [->(_event) { :loki }]
end

# Usage
OrderPlacedEvent.track(order_id: "ORD-123", amount: 10000, currency: "USD")
# → Written to Loki with retention_until: "2026-04-21T..."
# → Archival job (runs later): WHERE retention_until > now + 30d → export to cold
```

**Cost Impact:**
- **Before:** Loki only, no tiering = $200/month
- **After:** Loki at collection; archival job exports by `retention_until` to cheaper storage = $120/month
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

# At collection: errors → Sentry + Loki. retention_until in payload for archival.
E11y.configure do |config|
  config.routing_rules = [
    ->(event) { [:sentry, :loki] if event[:severity] == :error },
    ->(_event) { :loki }
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
#   Rule 2: :loki (archival job handles tiers later)
# ↓
# Event written to BOTH adapters
```

**Benefits:**
- ✅ **Alerting:** Sentry catches errors immediately
- ✅ **Storage:** Loki at collection; archival job (separate) exports by `retention_until`
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
│  - Rule 2: errors → Sentry + Loki  │
│  - Rule 3: default → Loki          │
└─────────────────────────────────┘
                │
                ▼
        ┌───────┴───────┐
        │               │
  ┌─────▼─────┐   ┌─────▼─────┐
  │   Loki    │   │  Sentry   │  (at collection)
  └───────────┘   └───────────┘
        │
        │ retention_until in payload
        ▼
  ┌─────────────────────────────┐
  │ Archival job (separate)     │
  │ Filters by retention_until │
  │ → export to cold storage    │
  └─────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility |
|-----------|----------------|
| **Event::Base** | Declare `retention_period`, calculate `retention_until` |
| **Configuration** | Define `routing_rules` (lambdas), `default_retention_period` |
| **Routing Middleware** | Apply rules, select adapters, write events |
| **Adapters** | Write events to storage (Loki, File, Sentry, etc.) |

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
# At collection: route to Loki (or stdout for very short retention).
# retention_until is in every event payload — archival job (separate) uses it later.
E11y.configure do |config|
  config.default_retention_period = 30.days
  
  config.routing_rules = [
    ->(event) { :audit_encrypted if event[:audit_event] },
    ->(event) { [:sentry, :loki] if event[:severity] == :error },
    ->(event) {
      days = (Time.parse(event[:retention_until]) - Time.now) / 86400
      days <= 7 ? :stdout : :loki  # Short → cheap, long → Loki
    }
  ]
  
  config.fallback_adapters = [:stdout]
  config.adapters[:loki] = E11y::Adapters::Loki.new(...)
  config.adapters[:audit_encrypted] = E11y::Adapters::AuditEncrypted.new(...)
  config.adapters[:sentry] = E11y::Adapters::Sentry.new(...)
end
```

### Step 3: Archival Job (Separate Process)

Archival runs **later**, not at collection. Example cron job:

```ruby
# lib/tasks/archival.rake or separate service
# Runs daily: reads Loki, filters by retention_until, exports to cold storage
# SELECT * FROM logs WHERE retention_until > ? AND timestamp < ?
# → export to S3 / object storage
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
- Business events (Loki + archival job exports by retention_until): **$120** ✅
- Audit logs (audit_encrypted + archival job): **$50** ✅
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
- ✅ **Business events** (90d retention) → Loki at collection; archival job exports by `retention_until`
- ✅ **Cost reduction** of 80%+ compared to manual adapter selection
- ✅ **Zero manual intervention** (routing is automatic)

---

**Status:** ✅ Ready for Implementation (2026-01-21)  
**Estimated Effort:** 1 week (Event DSL + Routing Middleware + Tests)  
**Cost Impact:** 80-97% savings on storage costs

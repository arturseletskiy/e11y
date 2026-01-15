# ADR-012: Event Evolution & Versioning

**Status:** Draft  
**Date:** January 13, 2026  
**Covers:** UC-020 (Event Versioning)  
**Depends On:** ADR-001 (Core), ADR-022 (Event Registry)

---

## 📋 Table of Contents

1. [Context & Problem](#1-context--problem)
2. [Solution: Parallel Versions](#2-solution-parallel-versions)
3. [Naming Convention](#3-naming-convention)
4. [Version in Payload](#4-version-in-payload)
5. [Schema Evolution Guidelines](#5-schema-evolution-guidelines)
6. [Event Registry Integration](#6-event-registry-integration)
7. [Migration Strategy](#7-migration-strategy)
8. [Schema Migrations and DLQ Replay (C15 Resolution)](#8-schema-migrations-and-dlq-replay-c15-resolution) ⚠️
9. [Trade-offs](#9-trade-offs)
10. [Summary](#10-summary)

---

## 1. Context & Problem

### 1.1. When Do You Need Versioning?

**90% of changes DON'T need versioning:**

```ruby
# ✅ Just add optional field - NO versioning!
optional(:currency).filled(:string)
```

**10% of changes DO need versioning:**

```ruby
# ❌ Adding REQUIRED field breaks old code
required(:currency).filled(:string)  # Old code doesn't have this!

# ✅ Solution: Create V2
class Events::OrderPaidV2 < E11y::Event::Base
  schema do
    required(:currency).filled(:string)
  end
end
```

### 1.2. Architecture Decision: Optional Middleware

**Versioning is opt-in (not everyone needs it):**

```ruby
# config/initializers/e11y.rb

# ✅ Enable versioning middleware (optional)
E11y.configure do |config|
  config.middleware.use E11y::Middleware::Versioning
end

# Result: Adds `v:` field to events (only if version > 1)
{
  event_name: "Events::OrderPaidV2",
  v: 2,  # Added by middleware
  payload: { ... }
}
```

**Benefits:**
- ✅ **Opt-in:** Only enabled if you need it
- ✅ **Zero overhead:** If disabled, no performance cost
- ✅ **Clean separation:** Versioning logic in middleware, not in Base class

### 1.3. Core Principles

1. **Version ONLY for breaking changes** (add/remove required field, change type)
2. **No automatic migration** (just keep V1 and V2 alive in parallel)
3. **Version in payload only if > 1** (reduces noise for V1 events)
4. **Gradual rollout** (deploy V2, update code, delete V1)

---

## 2. Solution: Parallel Versions

### 2.1. Core Concept

**Two versions live in parallel:**

```ruby
# app/events/order_paid.rb
class Events::OrderPaid < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float)
  end
end

# app/events/order_paid_v2.rb
class Events::OrderPaidV2 < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float)
    required(:currency).filled(:string)  # NEW
  end
end

# Old code (unchanged)
Events::OrderPaid.track(order_id: '123', amount: 99.99)

# New code (updated)
Events::OrderPaidV2.track(order_id: '123', amount: 99.99, currency: 'USD')

# Both work! No migration needed!
```

### 2.2. Gradual Rollout

```ruby
# === Phase 1: Deploy V2 (Week 1) ===
# - Add OrderPaidV2 class
# - Keep OrderPaid class (don't delete!)

# === Phase 2: Update Code (Week 2-4) ===
# controllers/orders_controller.rb
def create
  # Old code (still works)
  # Events::OrderPaid.track(...)
  
  # New code (updated)
  Events::OrderPaidV2.track(
    order_id: order.id,
    amount: order.amount,
    currency: order.currency
  )
end

# === Phase 3: Monitor Usage (Week 5) ===
# Check metrics:
E11y::Metrics.get('e11y.events_tracked_total', event_name: 'Events::OrderPaid')
# => 0 (no longer used)

# === Phase 4: Delete V1 (Week 6) ===
# Delete app/events/order_paid.rb (V1 class)
# Keep OrderPaidV2 as the only version
```

---

## 3. Naming Convention

### 3.1. Version from Class Name

**Rule:** Version number is implicit from class name.

```ruby
# V1: No suffix (implicit version 1)
class Events::OrderPaid < E11y::Event::Base
  # Version 1 (extracted from class name: OrderPaid → v1)
end

# V2: "V2" suffix (explicit version 2)
class Events::OrderPaidV2 < E11y::Event::Base
  # Version 2 (extracted from class name: OrderPaidV2 → v2)
end

# V3: "V3" suffix (explicit version 3)
class Events::OrderPaidV3 < E11y::Event::Base
  # Version 3 (extracted from class name: OrderPaidV3 → v3)
end
```

### 3.2. Version Extraction Logic

```ruby
# lib/e11y/versioning/version_extractor.rb
module E11y
  module Versioning
    class VersionExtractor
      # Extract version number from class name
      def self.extract_version(class_name)
        # "Events::OrderPaidV2" → 2
        # "Events::OrderPaid" → 1
        # "Events::OrderPaidV10" → 10
        
        if class_name =~ /V(\d+)$/
          $1.to_i
        else
          1  # No suffix = V1
        end
      end
      
      # Extract base name (without version)
      def self.extract_base_name(class_name)
        # "Events::OrderPaidV2" → "Events::OrderPaid"
        # "Events::OrderPaid" → "Events::OrderPaid"
        
        class_name.sub(/V\d+$/, '')
      end
    end
  end
end
```

---

## 4. Version in Payload

### 4.1. Middleware Implementation

**Versioning as optional middleware:**

```ruby
# lib/e11y/middleware/versioning.rb
module E11y
  module Middleware
    # Optional middleware to normalize event names and add version field
    # 
    # Usage:
    #   E11y.configure do |config|
    #     config.middleware.use E11y::Middleware::Versioning
    #   end
    class Versioning
      def call(event_data)
        class_name = event_data[:event_name]
        
        # Extract version from class name
        version = extract_version(class_name)
        
        # Normalize event_name to base name (without version suffix)
        # "Events::OrderPaidV2" → "Events::OrderPaid"
        event_data[:event_name] = extract_base_name(class_name)
        
        # Only add `v:` field if version > 1 (reduce noise)
        event_data[:v] = version if version > 1
        
        # Pass to next middleware
        yield event_data
      end
      
      private
      
      def extract_version(class_name)
        # "Events::OrderPaidV2" → 2
        # "Events::OrderPaid" → 1
        class_name =~ /V(\d+)$/ ? $1.to_i : 1
      end
      
      def extract_base_name(class_name)
        # "Events::OrderPaidV2" → "Events::OrderPaid"
        # "Events::OrderPaid" → "Events::OrderPaid"
        class_name.sub(/V\d+$/, '')
      end
    end
  end
end
```

### 4.2. Configuration & Middleware Order

**Versioning MUST be last middleware (before adapters):**

```ruby
# config/initializers/e11y.rb

E11y.configure do |config|
  # Default middleware stack (in order):
  config.middleware.use E11y::Middleware::TraceContext      # 1. Add trace_id
  config.middleware.use E11y::Middleware::SchemaValidation  # 2. Validate schema
  config.middleware.use E11y::Middleware::PIIFiltering      # 3. Filter PII
  config.middleware.use E11y::Middleware::RateLimiting      # 4. Check limits
  config.middleware.use E11y::Middleware::AdaptiveSampling  # 5. Sample
  
  # ✅ Versioning LAST (normalize event_name before adapters)
  config.middleware.use E11y::Middleware::Versioning        # 6. Normalize
  
  # Then: adapters receive normalized event_name
end
```

**Why versioning must be last?**

```ruby
# ✅ Correct order (versioning last):
1. Validation: Uses Events::OrderPaidV2 schema ✅
2. PII Filtering: Uses Events::OrderPaidV2 rules ✅
3. Rate Limiting: Uses Events::OrderPaidV2 limits ✅
4. Sampling: Uses Events::OrderPaidV2 config ✅
5. Versioning: Normalize to Events::OrderPaid ✅
6. Adapters: Receive normalized name (easy queries) ✅

# ❌ Wrong order (versioning first):
1. Versioning: Normalize to Events::OrderPaid
2. Validation: Can't find Events::OrderPaid schema (was V2!) ❌
3. PII Filtering: Uses wrong V1 rules (needs V2!) ❌
4. Rate Limiting: Uses wrong V1 limits (needs V2!) ❌
```

**When to enable:**
- ✅ You have multiple event versions (OrderPaid, OrderPaidV2)
- ✅ Need to track version adoption in analytics
- ✅ Need to differentiate versions in Grafana/Loki

**When to disable (default):**
- ✅ No versioned events yet (all V1)
- ✅ Don't need version tracking
- ✅ Want zero overhead

### 4.3. Payload Examples

```ruby
# V1 event (no `v:` field)
Events::OrderPaid.track(order_id: '123', amount: 99.99)

# Result:
{
  event_name: "Events::OrderPaid",  # ✅ Base name (without version)
  payload: { order_id: '123', amount: 99.99 },
  timestamp: "2026-01-13T10:00:00Z",
  trace_id: "trace-abc123"
  # No `v:` field (version 1 implicit)
}

# V2 event (with `v:` field)
Events::OrderPaidV2.track(order_id: '123', amount: 99.99, currency: 'USD')

# Result:
{
  event_name: "Events::OrderPaid",  # ✅ Same base name (V2 suffix removed!)
  v: 2,                              # ✅ Version in separate field
  payload: { order_id: '123', amount: 99.99, currency: 'USD' },
  timestamp: "2026-01-13T10:00:00Z",
  trace_id: "trace-abc123"
}
```

**Key Insight:** `event_name` is **normalized to base name** (without version suffix).

- ✅ **Same `event_name`** for all versions → easy to query
- ✅ **Version in `v:` field** → easy to filter
- ✅ **Semantically correct** → it's the same event, just different schema

### 4.4. Querying Events by Version

**Loki queries (simple!):**

```logql
# All OrderPaid events (both V1 and V2)
{event_name="Events::OrderPaid"}

# Only V1 events
{event_name="Events::OrderPaid"} | json | v != "2"

# Only V2 events
{event_name="Events::OrderPaid"} | json | v == "2"

# ✅ No need for: {event_name=~"Events::OrderPaid|Events::OrderPaidV2"}
```

**Prometheus metrics:**

```promql
# Total events by version
sum by(event_name, v) (rate(e11y_events_total[5m]))

# V1 vs V2 adoption rate
sum(rate(e11y_events_total{event_name="Events::OrderPaid", v="2"}[5m]))
/
sum(rate(e11y_events_total{event_name="Events::OrderPaid"}[5m]))
* 100

# Result: "75% of OrderPaid events are now V2"
```

**Grafana dashboard:**

```sql
-- Single panel for all versions (with version breakdown)
SELECT 
  event_name,
  COALESCE(v, 1) as version,  -- NULL = V1
  COUNT(*) as count
FROM events
WHERE event_name = 'Events::OrderPaid'
GROUP BY event_name, version
ORDER BY version
```

### 4.5. Why Not Always Include `v:`?

**Reasons:**
1. ✅ **Reduce noise:** 90% of events will be V1 (no versions needed)
2. ✅ **Backward compatible:** Existing consumers don't expect `v:` field
3. ✅ **Storage savings:** One less field per event (~5-10 bytes)
4. ✅ **Implicit V1:** If no `v:` field → assume V1

**When to use `v:`:**
- ✅ Track version adoption rate (V1 vs V2)
- ✅ Debug: "Which version caused this issue?"
- ✅ Analytics: Compare behavior between versions

---

## 5. Schema Evolution Guidelines

### 5.1. Non-Breaking Changes (NO versioning needed!)

**Pattern 1: Add Optional Field**

```ruby
# Before
class Events::OrderPaid < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float)
  end
end

# After (NO V2 needed!)
class Events::OrderPaid < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float)
    optional(:currency).filled(:string)  # ✅ Just add it!
  end
end

# Old code still works:
Events::OrderPaid.track(order_id: '123', amount: 99.99)

# New code uses new field:
Events::OrderPaid.track(order_id: '123', amount: 99.99, currency: 'USD')
```

**Pattern 2: Add Enum Value**

```ruby
# Before
class Events::OrderStatusChanged < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:status).filled(:string)  # 'pending', 'paid', 'shipped'
  end
end

# After (NO V2 needed!)
class Events::OrderStatusChanged < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:status).filled(:string)  # 'pending', 'paid', 'shipped', 'delivered'
  end
end

# ✅ Old consumers ignore new 'delivered' status
```

**Pattern 3: Deprecate Field (keep both)**

```ruby
# Before
class Events::UserRegistered < E11y::Event::Base
  schema do
    required(:user_id).filled(:string)
    required(:phone).filled(:string)
  end
end

# After (NO V2 needed!)
class Events::UserRegistered < E11y::Event::Base
  schema do
    required(:user_id).filled(:string)
    optional(:phone).filled(:string)       # @deprecated Use phone_number
    optional(:phone_number).filled(:string)  # New field
  end
end

# ✅ Both fields exist, old code still works
```

### 5.2. Breaking Changes (Versioning required!)

**Pattern 1: Add Required Field**

```ruby
# V1
class Events::OrderPaid < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float)
  end
end

# V2: Add REQUIRED field
class Events::OrderPaidV2 < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float)
    required(:currency).filled(:string)  # ✅ Required!
  end
end

# Why V2? Old code can't provide 'currency' → breaks!
```

**Pattern 2: Remove Required Field**

```ruby
# V1
class Events::UserRegistered < E11y::Event::Base
  schema do
    required(:user_id).filled(:string)
    required(:email).filled(:string)
    required(:phone).filled(:string)
  end
end

# V2: GDPR compliance - remove phone
class Events::UserRegisteredV2 < E11y::Event::Base
  schema do
    required(:user_id).filled(:string)
    required(:email).filled(:string)
    # phone REMOVED
  end
end

# Why V2? Consumers expect 'phone' → breaks if removed!
```

**Pattern 3: Change Field Type**

```ruby
# V1: Amount in dollars (float)
class Events::PaymentProcessed < E11y::Event::Base
  schema do
    required(:amount).filled(:float)  # 99.99
  end
end

# V2: Amount in cents (integer)
class Events::PaymentProcessedV2 < E11y::Event::Base
  schema do
    required(:amount_cents).filled(:integer)  # 9999
  end
end

# Why V2? Type changed, field renamed → breaks consumers!
```

### 5.3. When to Version: Decision Matrix

| Change | Breaking? | Version? | Example |
|--------|-----------|----------|---------|
| Add **optional** field | ❌ No | ❌ No | `optional(:currency)` |
| Add enum value | ❌ No | ❌ No | `'delivered'` status |
| Deprecate field (keep) | ❌ No | ❌ No | Keep `phone` + add `phone_number` |
| Add **required** field | ✅ Yes | ✅ Yes | `required(:currency)` |
| Remove **required** field | ✅ Yes | ✅ Yes | Remove `phone` (GDPR) |
| Change field type | ✅ Yes | ✅ Yes | `float` → `integer` |
| Rename field | ✅ Yes | ✅ Yes | `amount` → `amount_cents` |

---

## 6. Event Registry Integration

### 6.1. Auto-Registration

```ruby
# lib/e11y/event/base.rb
module E11y
  module Event
    class Base
      # Auto-register on class inheritance
      def self.inherited(subclass)
        super
        
        # Extract version from class name
        version = E11y::Versioning::VersionExtractor.extract_version(subclass.name)
        base_name = E11y::Versioning::VersionExtractor.extract_base_name(subclass.name)
        
        # Register in registry
        E11y::Registry.register(
          base_name: base_name,
          version: version,
          event_class: subclass
        )
      end
    end
  end
end
```

### 6.2. Registry API

```ruby
# Get all versions of an event
E11y::Registry.all_versions('Events::OrderPaid')
# => [
#   { version: 1, class: Events::OrderPaid, active: true },
#   { version: 2, class: Events::OrderPaidV2, active: true }
# ]

# Get latest version
E11y::Registry.latest_version('Events::OrderPaid')
# => { version: 2, class: Events::OrderPaidV2 }

# Get specific version
E11y::Registry.get_version('Events::OrderPaid', 1)
# => { version: 1, class: Events::OrderPaid }

# List all events with multiple versions
E11y::Registry.versioned_events
# => ['Events::OrderPaid', 'Events::PaymentProcessed']
```

### 6.3. Metrics Integration

```ruby
# Track version usage
E11y::Metrics.increment('e11y.events_tracked_total', {
  event_name: 'Events::OrderPaid',
  version: 1
})

# Grafana query:
# sum by(event_name, version) (rate(e11y_events_tracked_total[5m]))

# See V1 vs V2 adoption:
# Events::OrderPaid v1: 100 req/min (old code)
# Events::OrderPaidV2 v2: 50 req/min (new code)
```

---

## 7. Migration Strategy

### 7.1. Phase 1: Add V2 (Keep V1)

```ruby
# Week 1: Deploy V2

# app/events/order_paid_v2.rb (NEW FILE)
class Events::OrderPaidV2 < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float)
    required(:currency).filled(:string)  # NEW
  end
end

# app/events/order_paid.rb (KEEP EXISTING)
class Events::OrderPaid < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float)
  end
end

# ✅ Both classes deployed, no breaking changes
```

### 7.2. Phase 2: Update Code Gradually

```ruby
# Week 2-4: Update calling code

# controllers/orders_controller.rb
def create
  order = Order.create!(order_params)
  
  # ❌ Old code (before)
  # Events::OrderPaid.track(
  #   order_id: order.id,
  #   amount: order.amount
  # )
  
  # ✅ New code (after)
  Events::OrderPaidV2.track(
    order_id: order.id,
    amount: order.amount,
    currency: order.currency || 'USD'
  )
end

# Update in batches:
# - Week 2: Update 25% of code
# - Week 3: Update 50% of code
# - Week 4: Update 100% of code
```

### 7.3. Phase 3: Monitor V1 Usage

```ruby
# Week 5: Check if V1 still used

# Grafana query:
sum(rate(e11y_events_tracked_total{event_name="Events::OrderPaid"}[1d]))
# Result: 0 (no V1 events in last 24h)

# Or via Rails console:
E11y::Registry.version_usage('Events::OrderPaid')
# => {
#   1 => { count: 0, last_tracked_at: nil },
#   2 => { count: 1234, last_tracked_at: 5.minutes.ago }
# }
```

### 7.4. Phase 4: Delete V1 Class

```ruby
# Week 6: Delete V1 class

# ✅ Delete app/events/order_paid.rb
# ✅ V1 class no longer exists
# ✅ Only OrderPaidV2 remains

# Optionally: Rename V2 → V1
# git mv app/events/order_paid_v2.rb app/events/order_paid.rb
# class Events::OrderPaid < E11y::Event::Base
#   # This is now V1 again (for next iteration)
# end
```

### 7.5. DLQ Replay During Migration

```ruby
# === Scenario: V1 event in DLQ during migration ===

# Phase 2: V1 and V2 both exist
# DLQ has V1 event: { event_name: 'Events::OrderPaid', payload: {...} }

# Replay:
event_class = 'Events::OrderPaid'.constantize  # ✅ Class still exists!
event_class.track(dlq_event[:payload])          # ✅ Just replay as V1

# Phase 4: V1 deleted
# If DLQ still has V1 events → ❌ Replay fails
# Solution: Wait for DLQ to empty before deleting V1
```

---

## 8. Schema Migrations and DLQ Replay (C15 Resolution) ⚠️

**Reference:** [CONFLICT-ANALYSIS.md - C15: Event Versioning × DLQ Replay](../researches/CONFLICT-ANALYSIS.md#c15-event-versioning--dlq-replay)

### Decision: User Responsibility (Not an E11y Problem)

**E11y Position:**

> Schema migrations during DLQ replay are **NOT an E11y responsibility**. This is an **operational edge case** that occurs only when DLQ is poorly managed (events sitting for weeks between deployments).

**Why this is NOT a problem:**

1. **DLQ is for transient failures** (minutes/hours, not weeks!)
   - Loki down 30 seconds → retry → success
   - Loki down 2 hours → DLQ → replay after fix (same deployment, same schema!)
   
2. **DLQ should be cleared between deployments**
   - Replay DLQ before deploying schema changes
   - If DLQ has events sitting for **weeks** → operational failure, not E11y problem

3. **Real-world timeline:**
   ```
   09:00 - Loki down (transient failure)
   09:02 - Events go to DLQ
   09:05 - Loki back online
   09:10 - DLQ replay ✅ (same schema, same deployment)
   ```

   **NOT:**
   ```
   Week 1 - Events in DLQ
   Week 2 - Deploy new code with schema changes
   Week 3 - Replay DLQ ❌ (BAD OPERATIONS!)
   ```

**If you MUST replay old-schema events (edge case):**

This is **app-specific** and requires **user-implemented** migration logic:

```ruby
# Option 1: Lenient validation (skip schema validation for replayed events)
E11y.configure do |config|
  config.dlq_replay do
    skip_validation true  # Allow old schemas
  end
end

# Option 2: Transform old events before replay (user code)
E11y::DeadLetterQueue.replay do |old_event|
  # User implements migration logic
  if old_event[:event_version] == 1
    # Transform v1 → v2
    {
      order_id: old_event[:order_id],
      amount_cents: (old_event[:amount] * 100).to_i  # amount → amount_cents
    }
  else
    old_event
  end
end
```

**E11y provides:**
- ✅ DLQ replay mechanism (UC-021)
- ✅ Event version metadata (stored with event)
- ✅ Validation bypass option (`skip_validation`)

**User provides:**
- 🔧 Migration logic (app-specific transformations)
- 🔧 Operational discipline (clear DLQ between deployments)

**Trade-off:**
- ✅ **Pro:** E11y stays simple, no complex migration framework
- ✅ **Pro:** User has full control over migration logic
- ⚠️ **Con:** User must implement migrations for edge cases (poorly managed DLQ)

---

## 9. Trade-offs

### 9.1. Key Decisions

| Decision | Pro | Con | Rationale |
|----------|-----|-----|-----------|
| **Normalize event_name** | Same name for all versions, easy queries | Need to extract base name | Semantically correct |
| **Optional Middleware** | Opt-in, zero overhead if disabled | Need to enable manually | Not everyone needs versioning |
| **No auto-migration** | Simple, predictable | Manual code updates | YAGNI - not needed in practice |
| **Parallel versions** | Zero downtime, gradual rollout | Multiple classes to maintain | Standard practice |
| **`v:` only if > 1** | Reduces noise, storage | Need to infer V1 | 90% of events are V1 |
| **Version from class name** | Single source of truth | Can't rename classes | Consistent, explicit |
| **No dual emission** | Simple | Need to update consumers | Consumers are under our control |
| **DLQ replay with old schemas: User responsibility (C15)** ⚠️ | Simple gem, no migration framework | Edge case if DLQ poorly managed | Operational discipline > gem complexity |

### 9.2. Alternatives Considered

**A) event_name = class name (with version suffix)**
```ruby
# ❌ REJECTED
{
  event_name: "Events::OrderPaidV2",  # Different name for each version
  v: 2
}
```
- ❌ Need to query multiple names: `OrderPaid OR OrderPaidV2`
- ❌ Metrics split across different `event_name` labels
- ❌ Semantically wrong: it's the same event, different schema
- ✅ **CHOSEN: Normalize to base name** (same `event_name` for all versions)

**B) Built-in versioning (always enabled)**
```ruby
# ❌ REJECTED: Always adds v: field in Base class
E11y::Event::Base  # Always extracts version
```
- ❌ Performance overhead for apps without versioning
- ❌ Not everyone needs versioning
- ✅ **CHOSEN: Optional middleware** (zero overhead if disabled)

**B) Auto-migrate V1→V2**
```ruby
# ❌ REJECTED
def self.upgrade_from_v1(v1_payload)
  v1_payload.merge(currency: 'USD')
end
```
- ❌ Overcomplicated (chain migration, metadata storage)
- ❌ Not needed (just keep V1 alive during migration)
- ❌ Edge cases (lossy migration, impossible migration)

**C) Always include `v:` field**
```ruby
# ❌ REJECTED
{ v: 1, payload: {...} }  # Even for V1
```
- ❌ Noise for 90% of events
- ❌ Storage overhead (~5 bytes * billions of events)
- ❌ Breaking change for existing consumers

**D) Dual emission (V1 + V2)**
```ruby
# ❌ REJECTED
def self.emit_legacy_formats
  { 1 => { adapters: [:loki], downgrade: proc {...} } }
end
```
- ❌ Complex (downgrade logic)
- ❌ Not needed (just update Grafana dashboard)
- ❌ Storage overhead (2x events)

---

## 10. Summary

### 9.1. Core Principles

**1. Normalize event_name to base name**
- ✅ `Events::OrderPaidV2` → `event_name: "Events::OrderPaid"`
- ✅ Same name for all versions → easy to query
- ✅ Version in separate `v:` field

**2. Version ONLY for breaking changes**
- ✅ Add required field → V2
- ❌ Add optional field → Stay on V1

**3. Parallel versions for gradual rollout**
- ✅ Deploy V2, keep V1
- ✅ Update code gradually
- ✅ Delete V1 when no longer used

**4. Version in payload only if > 1**
- ✅ V1: No `v:` field (implicit)
- ✅ V2+: Add `v:` field (explicit)

**5. No automatic migration**
- ❌ No auto-upgrade V1→V2
- ✅ Just keep both classes alive

### 9.2. Best Practices

**✅ DO:**
1. Add optional fields freely (no versioning)
2. Think twice before adding required fields (forces V2)
3. Keep V1 alive during migration
4. Monitor V1 usage before deleting
5. Use Registry to track all versions

**❌ DON'T:**
1. Delete V1 while DLQ has V1 events
2. Version for non-breaking changes
3. Auto-migrate (keep it simple)

### 9.3. Implementation Checklist

**Phase 1: Core (Week 1)**
- [ ] Implement `VersionExtractor` (extract version from class name)
- [ ] Add `v:` field to payload (only if v > 1)
- [ ] Auto-register versions in Registry
- [ ] Add version metrics

**Phase 2: Tooling (Week 2)**
- [ ] Add `E11y::Registry.all_versions(base_name)`
- [ ] Add `E11y::Registry.version_usage(base_name)`
- [ ] Add Grafana dashboard for version adoption
- [ ] Add RSpec helpers for versioning

**Phase 3: Documentation (Week 3)**
- [ ] Document when to version
- [ ] Document migration strategy
- [ ] Add migration checklist
- [ ] Add examples for common scenarios

---

**Status:** ✅ Complete (Simplified)  
**Next:** Implementation  
**Estimated Implementation:** 1 week (not 2 weeks!)

**Key Takeaway:** Keep it simple. Parallel versions + gradual rollout is enough. No need for auto-migration magic.

# ADR-015: Middleware Execution Order

**Status:** Stable  
**Date:** January 13, 2026  
**Covers:** Pipeline execution order, event versioning integration  
**Depends On:** ADR-001 (Architecture), ADR-012 (Event Evolution)

---

## 📋 Table of Contents

1. [Context & Problem](#1-context--problem)
2. [Decision](#2-decision)
3. [Correct Order](#3-correct-order)
4. [Wrong Order Example](#4-wrong-order-example)
5. [Real-World Example](#5-real-world-example)
6. [Implementation Checklist](#6-implementation-checklist)

---

## 1. Context & Problem

### 1.1. Problem Statement

**Versioning Middleware normalizes event names for adapters, but when should this happen?**

```ruby
# Events::OrderPaidV2.track(...)
# Should validation use "Events::OrderPaidV2" or "Events::OrderPaid"?
# Should PII filtering use V2 rules or V1 rules?
# When do we normalize the name?
```

**Wrong placement breaks business logic:**
- ❌ Too early → Validation fails (can't find V2 schema)
- ❌ Too early → PII filtering uses wrong rules
- ❌ Too early → Rate limiting uses wrong limits

### 1.2. Key Insight

> **Versioning = Cosmetic normalization for external systems**  
> **All business logic MUST use original class name**

---

## 2. Decision

**Versioning Middleware MUST be LAST (before routing to adapters)**

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.middleware.use E11y::Middleware::TraceContext      # 1
  config.middleware.use E11y::Middleware::Validation        # 2
  config.middleware.use E11y::Middleware::PIIFiltering      # 3
  config.middleware.use E11y::Middleware::RateLimiting      # 4
  config.middleware.use E11y::Middleware::Sampling          # 5
  config.middleware.use E11y::Middleware::Versioning        # 6 ← LAST!
  config.middleware.use E11y::Middleware::Routing           # 7
end
```

---

## 3. Correct Order

### 3.1. Pipeline Flow

```
Events::OrderPaidV2.track(order_id: 123, amount: 99.99)
  ↓
1. TraceContext    → Add trace_id, span_id, timestamp
                     event_name = "Events::OrderPaidV2" (original)
  ↓
2. Validation      → Uses Events::OrderPaidV2 schema ✅
                     event_name = "Events::OrderPaidV2" (original)
  ↓
3. PII Filtering   → Uses Events::OrderPaidV2 PII rules ✅
                     event_name = "Events::OrderPaidV2" (original)
  ↓
4. Rate Limiting   → Checks limit for "Events::OrderPaidV2" ✅
                     event_name = "Events::OrderPaidV2" (original)
  ↓
5. Sampling        → Checks sample rate for "Events::OrderPaidV2" ✅
                     event_name = "Events::OrderPaidV2" (original)
  ↓
6. Versioning      → Normalize: "Events::OrderPaid"
   (LAST!)            Add v: 2 to payload
                     event_name = "Events::OrderPaid" (normalized)
  ↓
7. Routing         → Route to buffer
                     event_name = "Events::OrderPaid" (normalized)
  ↓
Adapters           → Receive normalized name
                     event_name = "Events::OrderPaid"
                     payload: { v: 2, order_id: 123, ... }
```

### 3.2. Why Each Middleware Needs Original Class Name

| Middleware | Needs Original? | Why? |
|------------|----------------|------|
| **TraceContext** | No | Just adds trace_id, doesn't care about class |
| **Validation** | ✅ Yes | Schema is attached to specific class (V2 ≠ V1) |
| **PIIFiltering** | ✅ Yes | PII rules may differ between V1 and V2 |
| **RateLimiting** | ✅ Yes | Rate limits may differ between V1 and V2 |
| **Sampling** | ✅ Yes | Sample rates may differ between V1 and V2 |
| **Versioning** | No | Normalizes for adapters (cosmetic change) |
| **Routing** | No | Routes based on severity, not class name |
| **Adapters** | No | Prefer normalized name (easier querying) |

---

## 4. Wrong Order Example

### 4.1. Versioning First (WRONG!)

```ruby
# ❌ WRONG ORDER!
config.middleware.use E11y::Middleware::Versioning        # 1 ← Too early!
config.middleware.use E11y::Middleware::Validation        # 2
config.middleware.use E11y::Middleware::PIIFiltering      # 3
config.middleware.use E11y::Middleware::RateLimiting      # 4
config.middleware.use E11y::Middleware::Sampling          # 5
```

### 4.2. What Breaks

```ruby
Events::OrderPaidV2.track(...)
  ↓
1. Versioning: Normalize "Events::OrderPaidV2" → "Events::OrderPaid"
  ↓
2. Validation: ❌ Can't find schema for "Events::OrderPaid" (was V2!)
  ↓
3. PII Filtering: ❌ Uses V1 rules instead of V2 rules!
  ↓
4. Rate Limiting: ❌ Uses V1 limit instead of V2 limit!
  ↓
5. Sampling: ❌ Uses V1 sample rate instead of V2 rate!
```

---

## 5. Real-World Example

```ruby
# V1: Old version (production)
class Events::OrderPaid < E11y::Event::Base
  schema do
    required(:order_id).filled(:integer)
    required(:amount).filled(:float)
    # No currency field!
  end
  
  pii_filtering do
    masks :email  # V1: masks email
  end
  
  adapters :loki, :sentry
  severity :info
end

# V2: New version (A/B test, 10% traffic)
class Events::OrderPaidV2 < E11y::Event::Base
  schema do
    required(:order_id).filled(:integer)
    required(:amount).filled(:float)
    required(:currency).filled(:string)  # ← NEW FIELD!
  end
  
  pii_filtering do
    hashes :email  # V2: hashes email (different rule!)
  end
  
  adapters :loki, :sentry
  severity :info
end

# Rate limiting config
E11y.configure do |config|
  config.rate_limiting do
    per_event 'Events::OrderPaid', limit: 1000, window: 1.second  # V1: high limit
    per_event 'Events::OrderPaidV2', limit: 100, window: 1.second # V2: low limit (A/B test)
  end
end

# Pipeline execution:
Events::OrderPaidV2.track(order_id: 123, amount: 99.99, currency: 'USD')
  ↓
1. Validation: ✅ Uses V2 schema (checks currency field exists)
2. PII Filtering: ✅ Uses V2 rules (hashes email, not masks)
3. Rate Limiting: ✅ Uses V2 limit (100 req/sec, not 1000)
4. Sampling: ✅ Uses V2 sample rate (if configured differently)
5. Versioning: Normalize to "Events::OrderPaid", add v: 2
6. Routing: Route to main buffer
  ↓
Loki receives:
{
  event_name: "Events::OrderPaid",  ← Normalized!
  v: 2,                              ← Version explicit
  order_id: 123,
  amount: 99.99,
  currency: "USD",
  email: "sha256:abc123..."          ← Hashed (V2 rule)
}

# Easy querying in Loki:
# All versions: {event_name="Events::OrderPaid"}
# Only V2: {event_name="Events::OrderPaid", v="2"}
# Only V1: {event_name="Events::OrderPaid"} |= "" != "v"
```

---

## 6. Implementation Checklist

- [ ] Versioning Middleware is **LAST** (before Routing)
- [ ] All business logic middleware uses **ORIGINAL class name**
- [ ] Adapters receive **NORMALIZED event_name**
- [ ] `v:` field is added **only if version > 1**
- [ ] Rate limits are configured **per original class** (if differ)
- [ ] PII rules are configured **per original class** (if differ)
- [ ] Sampling rules are configured **per original class** (if differ)
- [ ] Metrics track **both** normalized name and version

---

## 7. See Also

- **ADR-001: Architecture** - Pipeline architecture and middleware chain
- **ADR-012: Event Evolution & Versioning** - Full versioning design
- **COMPREHENSIVE-CONFIGURATION.md** - Complete configuration examples

---

**Status:** ✅ Stable - Do not change order without updating all ADRs!

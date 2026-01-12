# UC-019: Retention Tagging for Downstream Data Lifecycle

**Status:** Cost Optimization Feature (v1.0)  
**Complexity:** Simple (just tagging!)  
**Setup Time:** 10 minutes (E11y config only)  
**Target Users:** Platform Engineers, DevOps, Cost Optimization Teams

---

## 📋 Overview

### Problem Statement

**Current Pain Points:**

1. **Downstream systems don't know event retention requirements**
   - Elasticsearch ILM treats all events the same
   - S3 Lifecycle Rules need manual setup per prefix
   - No way to express "this event should be kept 7 years"

2. **Storage costs grow linearly**
   - All events in hot tier (expensive)
   - No differentiation between debug (1 day) and audit (7 years)

3. **Manual configuration hell**
   - Different ES indices for different retention? (nightmare)
   - Different S3 buckets per retention? (management overhead)
   - No single source of truth

### E11y Solution

**Just Add Metadata Tags!**

E11y просто добавляет **retention tags** к каждому событию:
- `retention_days: 7` для debug events
- `retention_days: 2555` (7 years) для audit events
- **Downstream системы** (ES ILM, S3 Lifecycle) используют эти теги

**Result:** Простая конфигурация, downstream делает всю работу.

---

## 🎯 Use Case Scenarios

### Scenario 1: Standard Observability Events

**Context:** Regular application events (logs, metrics)

```ruby
# Default retention: 30 days
class OrderCreated < E11y::Event::Base
  # No explicit retention → use default (30 days)
end

# E11y adds metadata:
Events::OrderCreated.track(order_id: '123')
# Event written with:
# {
#   "@timestamp": "2026-01-12T10:30:00Z",
#   "retention_until": "2026-02-11T10:30:00Z",  # ← E11y calculates: @timestamp + 30 days
#   "event_name": "order.created",
#   ...
# }

# Downstream ES ILM simply checks:
# if now > retention_until → delete
# No calculation needed!
```

### Scenario 2: Audit Events (Long Retention)

**Context:** Compliance events requiring 7-year retention

```ruby
class UserPermissionChanged < E11y::AuditEvent
  audit_retention 7.years  # Compliance requirement
  
  schema do
    required(:user_id).filled(:string)
    required(:old_role).filled(:string)
    required(:new_role).filled(:string)
  end
end

# E11y adds metadata:
Events::UserPermissionChanged.track(...)
# Event written with:
# {
#   "@timestamp": "2026-01-12T10:30:00Z",
#   "retention_until": "2033-01-12T10:30:00Z",  # ← @timestamp + 7 years
#   "event_name": "user.permission_changed",
#   ...
# }

# Downstream systems simply check:
# if now > retention_until → delete
```

### Scenario 3: High-Volume Events (Short Retention)

**Context:** Debug logs, page views (noise if kept long)

```ruby
class PageView < E11y::Event::Base
  retention 1.day  # Short retention
  
  schema do
    required(:path).filled(:string)
    required(:user_id).filled(:string)
  end
end

# E11y adds metadata:
Events::PageView.track(...)
# Event written with:
# {
#   "@timestamp": "2026-01-12T10:30:00Z",
#   "retention_until": "2026-01-13T10:30:00Z",  # ← @timestamp + 1 day
#   "event_name": "page.view",
#   ...
# }

# Downstream ES ILM:
# - Deletes when now > retention_until (1 day later)
```

---

## 🏗️ Architecture

### E11y's Simple Role: Just Add Expiry Date!

```
┌─────────────────────────────────────────────────────────────────┐
│ E11Y (Dead Simple: Calculate Expiry Date)                       │
│                                                                  │
│  Event.track(...)                                                │
│      ↓                                                           │
│  Add metadata to event:                                          │
│  {                                                               │
│    "@timestamp": "2026-01-12T10:30:00Z",                        │
│    "retention_until": "2026-02-11T10:30:00Z", ← @timestamp + 30d│
│    "event_name": "order.created",                                │
│    ...                                                           │
│  }                                                               │
│      ↓                                                           │
│  Write to adapters (Loki, ES, S3)                               │
│                                                                  │
│  THAT'S IT! E11y's job done ✅                                  │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ DOWNSTREAM SYSTEMS (Trivial Logic)                              │
│                                                                  │
│  Elasticsearch ILM / S3 Lifecycle / External job:                │
│                                                                  │
│  ┌──────────────────────────────────┐                           │
│  │  if now > retention_until        │                           │
│  │    delete(event)                 │                           │
│  │  end                             │                           │
│  └──────────────────────────────────┘                           │
│                                                                  │
│  No calculations! Just date comparison ✅                       │
└─────────────────────────────────────────────────────────────────┘
```

### Benefits of `retention_until` (Absolute Date)

**vs. `retention_days` (Relative):**

| Approach | Downstream Logic | Clock Skew Issues? | Simple? |
|----------|------------------|-------------------|---------|
| `retention_days: 30` | `if now > (@timestamp + 30.days)` | ❌ Yes (if clocks differ) | 🟡 Need calculation |
| `retention_until: "2026-02-11"` | `if now > retention_until` | ✅ No (date already calculated) | ✅ Trivial comparison |

**E11y calculates once, downstream just compares!**

---

## 🔧 Configuration

### E11y Configuration (Dead Simple!)

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  # Just enable retention tagging!
  config.retention_tagging do
    enabled true
    
    # Default retention for events without explicit retention
    default_retention 30.days
    
    # Per-pattern retention rules
    retention_by_pattern do
      pattern 'audit.*', retention: 7.years
      pattern 'security.*', retention: 1.year
      pattern 'debug.*', retention: 1.day
      pattern '*.page_view', retention: 7.days
      pattern '*', retention: 30.days  # Default
    end
    
    # Field name (what E11y adds to each event)
    retention_field :retention_until  # ISO8601 timestamp
  end
end

# E11y automatically adds to each event:
# event["retention_until"] = event["@timestamp"] + retention_period
```

**That's it for E11y!** Downstream just checks: `now > retention_until`

---

## 🔄 Downstream Configuration

**E11y doesn't migrate data!** Downstream systems use `@timestamp` + `retention_days`.

### Option 1: Elasticsearch ILM (Recommended)

**Elasticsearch reads retention_days from each event:**

```bash
# Create ILM policy in Elasticsearch
PUT _ilm/policy/e11y-events-policy
{
  "policy": {
    "phases": {
      "hot": {
        "min_age": "0ms",
        "actions": {
          "rollover": {
            "max_primary_shard_size": "50GB",
            "max_age": "1d"
          },
          "set_priority": {
            "priority": 100
          }
        }
      },
      "warm": {
        "min_age": "7d",
        "actions": {
          "shrink": {
            "number_of_shards": 1
          },
          "forcemerge": {
            "max_num_segments": 1
          },
          "set_priority": {
            "priority": 50
          }
        }
      },
      "cold": {
        "min_age": "30d",
        "actions": {
          "searchable_snapshot": {
            "snapshot_repository": "e11y-s3-repository"
          }
        }
      },
      "delete": {
        # IMPORTANT: Delete based on @timestamp + retention_days
        # This requires ES script or external job
        "min_age": "365d",  # Max default
        "actions": {
          "delete": {}
        }
      }
    }
  }
}

# NOTE: ES ILM doesn't natively support per-document retention!
# You need EITHER:
# 1. Multiple ILM policies per retention period (complex)
# 2. External cleanup job (reads retention_days, deletes old docs)
```

**Better approach: External cleanup job** (reads retention_days):

### Option 2: S3 Lifecycle Rules

**Problem:** S3 Lifecycle works on object creation date, not event @timestamp!

**Solution:** E11y can add S3 object tags (if using S3 adapter):

```ruby
# E11y S3 Adapter adds object tags
config.adapters do
  register :s3, E11y::Adapters::S3Adapter.new(
    bucket: 'e11y-events',
    tagging: true,  # Enable object tagging
    tags_from_event: [:retention_days]  # Copy event field to S3 tag
  )
end

# AWS S3 Lifecycle (using tags)
resource "aws_s3_bucket_lifecycle_configuration" "e11y_events" {
  bucket = aws_s3_bucket.e11y_events.id
  
  # Rule for 7-day retention (debug, page views)
  rule {
    id     = "short-retention"
    status = "Enabled"
    
    expiration {
      days = 7
    }
    
    filter {
      tag {
        key   = "retention_days"
        value = "7"
      }
    }
  }
  
  # Rule for 30-day retention (standard events)
  rule {
    id     = "standard-retention"
    status = "Enabled"
    
    transition {
      days          = 7
      storage_class = "STANDARD_IA"
    }
    
    expiration {
      days = 30
    }
    
    filter {
      tag {
        key   = "retention_days"
        value = "30"
      }
    }
  }
  
  # Rule for 7-year retention (audit)
  rule {
    id     = "audit-retention"
    status = "Enabled"
    
    transition {
      days          = 30
      storage_class = "GLACIER"
    }
    
    transition {
      days          = 365
      storage_class = "DEEP_ARCHIVE"
    }
    
    expiration {
      days = 2555  # 7 years
    }
    
    filter {
      tag {
        key   = "retention_days"
        value = "2555"
      }
    }
  }
}
```

**Note:** Need one rule per retention_days value (manageable for common values like 1, 7, 30, 365, 2555).

### Option 3: External Cleanup Job (Recommended!)

**Trivial logic with `retention_until`:**

```ruby
# lib/tasks/e11y_cleanup.rake
namespace :e11y do
  desc "Delete events past their retention period"
  task cleanup: :environment do
    es_client = Elasticsearch::Client.new(url: ENV['ES_URL'])
    
    # Delete expired events (dead simple query!)
    response = es_client.delete_by_query(
      index: 'e11y-events-*',
      body: {
        query: {
          range: {
            retention_until: {
              lte: 'now'  # ← That's it! Just: retention_until <= now
            }
          }
        }
      }
    )
    
    puts "Deleted #{response['deleted']} expired events"
  end
end

# Schedule daily: 0 2 * * * rake e11y:cleanup
```

**This approach:**
- ✅ Works with ANY retention period (no calculation!)
- ✅ Trivial query: `retention_until <= now`
- ✅ No Painless scripts (faster, simpler)
- ✅ Standard Elasticsearch range query

---

## 📊 Cost Savings Example

### Before Tiered Storage

```
All events in Elasticsearch (hot tier):
- Volume: 1TB/month
- Retention: 365 days
- Total storage: 12TB/year
- ES cost: $0.10/GB/month
- Annual cost: $0.10 × 12,000 GB × 12 months = $14,400/year
```

### After Tiered Storage

```
Hot tier (ES, 0-7 days):
- Volume: 1TB/month × 7/30 = 233GB
- Cost: $0.10 × 233 GB × 12 = $280/year

Warm tier (S3 Standard, 7-30 days):
- Volume: 1TB/month × 23/30 = 767GB
- Cost: $0.023/GB/month
- Annual cost: $0.023 × 767 GB × 12 = $212/year

Cold tier (S3 Glacier, 30-365 days):
- Volume: 1TB/month × 335/365 = 918GB per month average
- Cost: $0.004/GB/month
- Annual cost: $0.004 × 11,000 GB = $44/year

Total cost: $280 + $212 + $44 = $536/year
Savings: $14,400 - $536 = $13,864/year (96% reduction!)
```

---

## 💡 Best Practices

### ✅ DO

**1. Define retention at event level**
```ruby
class AuditEvent < E11y::Event::Base
  retention 7.years  # Explicit
end
```

**2. Use retention tagging for S3 lifecycle**
```ruby
config.cost_optimization.retention_tagging do
  enabled true
  tag_with_retention true  # Adds retention_days to event metadata
end
```

**3. Query warm/cold data via Athena/BigQuery**
```sql
-- Query S3 via AWS Athena
SELECT * FROM e11y_events_warm
WHERE date = '2024-01-15'
  AND event_name = 'order.created'
LIMIT 100;
```

**4. Set up ES ILM for automatic migration**
```bash
# Let Elasticsearch handle hot→warm→cold automatically
```

---

### ❌ DON'T

**1. Don't expect E11y to migrate data**
```ruby
# ❌ E11y doesn't move data between adapters
# It only routes writes to appropriate tiers

# ✅ Use ES ILM or S3 Lifecycle for migration
```

**2. Don't keep high-volume data in hot tier long**
```ruby
# ❌ BAD: Debug logs in ES for 30 days
class DebugEvent < E11y::Event::Base
  retention 30.days  # Expensive!
end

# ✅ GOOD: Short retention for debug
class DebugEvent < E11y::Event::Base
  retention 1.day  # Cheap!
end
```

**3. Don't forget to configure S3 lifecycle rules**
```ruby
# If you send events to S3, set up lifecycle rules!
# Otherwise data stays in Standard tier (expensive)
```

---

## 🎯 Success Metrics

### Quantifiable Benefits

**1. Storage Cost Reduction**
- Before: $14,400/year (all in ES)
- After: $536/year (tiered)
- **Savings: 96%**

**2. Query Performance**
- Hot tier (0-7 days): <1s queries ✅
- Warm tier (7-30 days): 1-5s queries (acceptable)
- Cold tier (30+ days): Rare access (minutes OK)

**3. Compliance**
- Audit events: 7-year retention ✅
- PII events: Auto-deleted after 30 days ✅
- Debug logs: Deleted after 1 day ✅

---

## 📚 Related Use Cases

- **[UC-012: Audit Trail](./UC-012-audit-trail.md)** - Long-term retention for compliance
- **[UC-015: Cost Optimization](./UC-015-cost-optimization.md)** - Overall cost reduction strategies
- **[UC-002: Business Event Tracking](./UC-002-business-event-tracking.md)** - Event definitions with retention

---

## 🚀 Quick Start Checklist

- [ ] Enable tiered storage in E11y config
- [ ] Configure retention tagging
- [ ] Set up Elasticsearch ILM policy
- [ ] Configure S3 lifecycle rules
- [ ] Define per-event retention policies
- [ ] Test write-time routing
- [ ] Monitor storage costs (before/after)
- [ ] Set up Athena for warm/cold queries (optional)

---

**Status:** ✅ Ready for Implementation  
**Priority:** High (significant cost savings)  
**Complexity:** Advanced (requires downstream setup)

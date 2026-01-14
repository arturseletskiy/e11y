# Backlog (Future Enhancements)

**Status:** Draft  
**Priority:** Low (v1.1+)  
**Category:** Future Ideas

---

## Overview

This document captures promising ideas for future versions of `e11y` that are not planned for v1.0 but may provide significant value in subsequent releases.

---

## 1. Quick Start Presets

### Problem

Configuration complexity can be overwhelming for new users. Setting up production-ready configuration requires understanding multiple subsystems (sampling, compression, retention, payload optimization).

### Proposal

Provide pre-configured profiles for common scenarios:

```ruby
E11y.configure do |config|
  # Option 1: Use a preset
  config.use_preset :production_high_traffic
  
  # Option 2: Use a preset with overrides
  config.use_preset :production_high_traffic do |preset|
    preset.sampling.max_events_per_sec = 5_000  # Override default
  end
end
```

### Available Presets

| Preset | Description | Sample Rate | Compression | Retention |
|--------|-------------|-------------|-------------|-----------|
| `:development` | Local dev, no sampling | 100% | None | 1 day |
| `:staging` | Pre-prod testing | 50% | Gzip | 7 days |
| `:production_low_traffic` | < 1K events/sec | 80% | Gzip | 30 days |
| `:production_high_traffic` | > 10K events/sec | 10% | Zstd | 7 days hot, 90 days warm |
| `:production_cost_optimized` | Aggressive cost reduction | 5% | Zstd level 9 | 3 days hot, 30 days warm |

### Implementation Example

```ruby
module E11y
  module Presets
    PRODUCTION_HIGH_TRAFFIC = {
      adaptive_sampling: {
        enabled: true,
        load_based: { max_events_per_sec: 10_000 },
        error_based: { enabled: true },
        value_based: {
          high_value_patterns: [/^payment\./, /^order\./, /^error\./],
          low_value_patterns: [/^debug\./, /^health_check/]
        }
      },
      compression: {
        enabled: true,
        algorithm: :zstd,
        level: 3
      },
      retention_tagging: {
        enabled: true,
        default_retention: 7.days,
        retention_by_pattern: {
          'audit.*' => 7.years,
          'payment.*' => 1.year,
          'debug.*' => 1.day
        }
      },
      payload_minimization: {
        enabled: true,
        truncate_strings_at: 1000,
        truncate_arrays_at: 100,
        remove_null_fields: true
      }
    }.freeze
  end
end
```

### Benefits

- ✅ Faster onboarding (< 5 minutes to production-ready config)
- ✅ Best practices baked in
- ✅ Easy to customize (override specific settings)
- ✅ Reduces configuration errors

### Priority

**Medium (v1.1)**

---

## 2. Sampling Budget

### Problem

Current sampling is reactive (based on load). Hard to predict costs. Organizations need predictable telemetry budgets.

### Proposal

Proactive budget-based sampling:

```ruby
E11y.configure do |config|
  config.cost_optimization do
    sampling_budget do
      enabled true
      
      # Set a daily event budget
      daily_budget 10_000_000  # 10M events/day
      
      # Budget allocation by event type
      allocate_by_pattern do
        pattern 'payment.*', percent: 20  # 2M events/day
        pattern 'order.*',   percent: 15  # 1.5M events/day
        pattern 'error.*',   percent: 10  # 1M events/day (always track)
        pattern 'debug.*',   percent: 5   # 500K events/day
        pattern '*',         percent: 50  # 5M events/day (everything else)
      end
      
      # Dynamic adjustment
      rebalance_interval 1.hour  # Recalculate sample rates every hour
      
      # Overflow strategy
      on_budget_exceeded :reduce_low_value  # or :stop_sampling, :alert_only
      
      # Alert when budget is 80% consumed
      alert_threshold 0.8
      alert_to :slack  # or :pagerduty, :email
    end
  end
end
```

### How It Works

#### 1. Budget Calculation

```ruby
# At start of each hour:
hourly_budget = daily_budget / 24  # 416,666 events/hour

# Per-pattern budget:
payment_budget = hourly_budget * 0.20  # 83,333 events/hour
```

#### 2. Dynamic Sample Rate Adjustment

```ruby
# If payment events are at 50% of budget after 30 min:
current_rate = 41,666 / (83,333 / 2)  # = 1.0 (100% sampling)

# If payment events are at 90% of budget after 30 min:
current_rate = 74,999 / (83,333 / 2)  # = 1.8 (need to reduce)
new_sample_rate = 1.0 / 1.8  # = 55% sampling for next 30 min
```

#### 3. Cost Predictability

```ruby
# Known daily cost:
cost_per_event = $0.0001  # e.g., Datadog pricing
daily_cost = 10_000_000 * $0.0001 = $1,000/day
monthly_cost = $1,000 * 30 = $30,000/month
```

### Benefits

- ✅ Predictable costs (no surprises)
- ✅ Budget enforcement (hard cap on events)
- ✅ Intelligent allocation (high-value events get more budget)
- ✅ Real-time alerts (before overspending)

### Trade-offs

- ⚠️ Complexity (requires Redis for distributed state)
- ⚠️ Potential data loss (if budget exceeded)
- ⚠️ Tuning required (optimal allocation per app)

### Priority

**Low (v1.2+)**

### Alternative Approach

- Use cloud cost management tools (AWS Cost Anomaly Detection, Datadog Cost Management)
- Set alerts on actual billing, not event counts
- Simpler, but less proactive

---

## 3. Additional Ideas (Placeholder)

Future ideas to be added:

- **ML-Based Anomaly Detection:** Automatically detect unusual patterns in events
- **Event Replay from Storage:** Replay events from cold storage for debugging
- **Multi-Tenant Support:** Isolate events by tenant/customer
- **Event Transformation Rules:** Transform events before sending to adapters
- **Custom Retention Policies:** More granular control over data lifecycle

---

## Related Use Cases

- [UC-009: Cost Optimization](UC-015-cost-optimization.md) - Current cost optimization strategies
- [UC-014: Adaptive Sampling](UC-014-adaptive-sampling.md) - Current sampling approach

---

## Related ADRs

- [ADR-009: Cost Optimization](../ADR-009-cost-optimization.md) - Current implementation

---

**Status:** ✅ Draft Complete  
**Next Review:** After v1.0 release  
**Estimated Value:** High (for enterprise customers)

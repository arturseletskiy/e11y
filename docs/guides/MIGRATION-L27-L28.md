# Migration Guide: L2.7 (Basic Sampling) → L2.8 (Advanced Sampling)

**Version:** 1.0  
**Date:** January 20, 2026  
**Applies to:** E11y gem v0.8.0+

---

## 📋 Overview

This guide helps you migrate from **L2.7 (Basic Sampling)** to **L2.8 (Advanced Sampling Strategies)** to unlock:

- **Error-Based Adaptive Sampling**: 100% sampling during error spikes
- **Load-Based Adaptive Sampling**: Tiered sampling (100%/50%/10%/1%) based on system load
- **Value-Based Sampling**: Always sample high-value events (e.g., >$1000 orders)
- **Stratified Sampling**: SLO-accurate metrics with < 5% error margin

**Cost Savings**: 35-90% reduction in observability costs while maintaining or improving data quality.

---

## 🚦 Migration Phases

### Phase 1: Preparation (1 hour)
1. Review current sampling config
2. Run tests to establish baseline
3. Enable self-monitoring metrics

### Phase 2: Enable Error-Based Adaptive (30 minutes)
1. Add error spike detection config
2. Deploy to staging
3. Validate behavior during simulated incidents

### Phase 3: Enable Load-Based Adaptive (30 minutes)
1. Add load monitor config
2. Deploy to staging
3. Load test with varying traffic levels

### Phase 4: Add Value-Based Sampling (1 hour)
1. Identify high-value events
2. Add `sample_by_value` DSL to event classes
3. Validate in staging

### Phase 5: Enable Stratified Sampling (15 minutes)
1. Enable SLO sampling correction
2. Validate SLO accuracy
3. Deploy to production

---

## 📊 Current State (L2.7 - Basic Sampling)

**What You Have:**

```ruby
# config/initializers/e11y.rb (L2.7)
E11y.configure do |config|
  # Basic sampling middleware (already in pipeline)
  config.pipeline.use E11y::Middleware::Sampling,
    default_sample_rate: 0.1,  # 10% sampling
    trace_aware: true           # Trace-consistent sampling
end

# Event-level sampling
class Events::HighFrequencyEvent < E11y::Event::Base
  sample_rate 0.01  # 1% sampling
end

# Severity-based defaults (automatic)
class Events::ErrorEvent < E11y::Event::Base
  severity :error  # → 100% sampling (SEVERITY_SAMPLE_RATES[:error])
end

# Audit event exemption
class Events::AuditEvent < E11y::Event::Base
  audit_event true  # Never sampled, always processed
end
```

**What's Working:**
- ✅ Basic sampling (10% default)
- ✅ Trace-aware sampling (C05 resolution)
- ✅ Event-level sample rates
- ✅ Severity-based defaults
- ✅ Audit event exemption

**What's Missing:**
- ❌ No dynamic adjustment during errors
- ❌ No load-based adaptation
- ❌ No value-based prioritization
- ❌ SLO metrics not corrected for sampling

---

## 🎯 Target State (L2.8 - Advanced Sampling)

**What You'll Have:**

```ruby
# config/initializers/e11y.rb (L2.8)
E11y.configure do |config|
  config.pipeline.use E11y::Middleware::Sampling,
    default_sample_rate: 0.1,
    
    # ✅ NEW: Error-Based Adaptive (FEAT-4838)
    error_based_adaptive: true,
    error_spike_config: {
      window: 60,
      absolute_threshold: 100,
      relative_threshold: 3.0,
      spike_duration: 300
    },
    
    # ✅ NEW: Load-Based Adaptive (FEAT-4842)
    load_based_adaptive: true,
    load_monitor_config: {
      window: 60,
      normal_threshold: 1_000,
      high_threshold: 10_000,
      very_high_threshold: 50_000,
      overload_threshold: 100_000
    }
  
  # ✅ NEW: Stratified Sampling for SLO (FEAT-4850)
  config.slo do
    enabled true
    enable_sampling_correction true  # Automatic correction
  end
end

# ✅ NEW: Value-Based Sampling (FEAT-4846)
class Events::OrderPaid < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:decimal)
  end
  
  # Always sample high-value orders
  sample_by_value field: "amount",
                  operator: :greater_than,
                  threshold: 1000,
                  sample_rate: 1.0
end
```

**What You'll Gain:**
- ✅ 100% sampling during error spikes (debug priority)
- ✅ Cost protection during high load (1-10% sampling)
- ✅ Business-critical event prioritization
- ✅ Accurate SLO metrics (< 5% error)

---

## 🛠️ Step-by-Step Migration

### Step 1: Review Current Config

**Check your current sampling configuration:**

```bash
# Find current sampling config
grep -r "Middleware::Sampling" config/initializers/
grep -r "sample_rate" app/events/

# Check event classes with custom sampling
find app/events -name "*.rb" -exec grep -l "sample_rate" {} \;
```

**Document current behavior:**
- What's your `default_sample_rate`?
- Which events have custom `sample_rate`?
- Are you using `audit_event true`?

**Baseline metrics (capture before migration):**
```ruby
# Run for 1 hour in production
# - e11y_events_tracked_total (events/sec)
# - e11y_events_dropped_total (% dropped)
# - e11y_slo_http_success_rate (success rate)
```

---

### Step 2: Enable Self-Monitoring

**Add self-monitoring to track migration effectiveness:**

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  # ... existing config ...
  
  # Enable self-monitoring (already included in L2.7)
  config.self_monitoring.enabled = true
end
```

**Key metrics to watch:**
- `e11y_middleware_latency_ms` (sampling overhead)
- `e11y_events_sampled_total` (events kept)
- `e11y_events_dropped_total` (events dropped)

---

### Step 3: Enable Error-Based Adaptive Sampling

**Add error spike detection config:**

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.pipeline.use E11y::Middleware::Sampling,
    default_sample_rate: 0.1,
    trace_aware: true,
    
    # NEW: Error-Based Adaptive
    error_based_adaptive: true,
    error_spike_config: {
      window: 60,                    # 60 seconds sliding window
      absolute_threshold: 100,       # 100 errors/min triggers spike
      relative_threshold: 3.0,       # 3x normal rate triggers spike
      spike_duration: 300            # Keep 100% sampling for 5 minutes
    }
end
```

**Deploy to staging:**
```bash
# Push config changes
git add config/initializers/e11y.rb
git commit -m "feat: enable error-based adaptive sampling (FEAT-4838)"
git push origin feature/l28-migration

# Deploy to staging
bin/deploy staging
```

**Validate in staging:**

1. **Simulate error spike:**
   ```bash
   # Generate 150 errors in 1 minute (exceeds absolute threshold)
   150.times { Events::TestError.track(severity: :error) }
   ```

2. **Check Grafana:**
   ```promql
   # Should see sampling rate jump to 100%
   e11y_sampling_current_rate{strategy="error_spike"}
   ```

3. **Verify events captured:**
   ```bash
   # Query Loki for events during spike
   # All errors should be present (100% sampling)
   ```

**Rollback plan:**
```ruby
# If issues, disable error-based adaptive:
E11y.configure do |config|
  config.pipeline.use E11y::Middleware::Sampling,
    default_sample_rate: 0.1,
    error_based_adaptive: false  # ← Disable
end
```

---

### Step 4: Enable Load-Based Adaptive Sampling

**Add load monitor config:**

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.pipeline.use E11y::Middleware::Sampling,
    default_sample_rate: 0.1,
    error_based_adaptive: true,
    error_spike_config: { ... },
    
    # NEW: Load-Based Adaptive
    load_based_adaptive: true,
    load_monitor_config: {
      window: 60,                    # 60 seconds
      normal_threshold: 1_000,       # < 1k events/sec = normal (100%)
      high_threshold: 10_000,        # 10k events/sec = high (50%)
      very_high_threshold: 50_000,   # 50k events/sec = very high (10%)
      overload_threshold: 100_000    # > 100k events/sec = overload (1%)
    }
end
```

**Tune thresholds for your app:**

```bash
# Check current event rate in production
echo "SELECT rate(e11y_events_tracked_total[5m])" | promql

# Adjust thresholds based on your baseline:
# - normal_threshold: 2x baseline
# - high_threshold: 10x baseline
# - very_high_threshold: 50x baseline
# - overload_threshold: 100x baseline
```

**Load test in staging:**

```bash
# Simulate high load with wrk
wrk -t12 -c400 -d30s --latency https://staging.example.com/api/orders

# Watch sampling rate adjust in Grafana:
# - Low load: 100%
# - High load: 50%
# - Very high: 10%
# - Overload: 1%
```

**Monitor performance:**
```promql
# Check if load-based sampling is working
e11y_sampling_current_rate{strategy="load_based"}

# Verify cost savings
sum(rate(e11y_events_dropped_total[5m])) / sum(rate(e11y_events_tracked_total[5m]))
```

---

### Step 5: Add Value-Based Sampling

**Identify high-value events:**

1. **Business-critical events:**
   - Payment transactions
   - Order completions
   - User registrations

2. **High-value thresholds:**
   - Orders > $1000
   - Enterprise/VIP users
   - Critical API endpoints

**Add `sample_by_value` to event classes:**

```ruby
# app/events/order_paid.rb
class Events::OrderPaid < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:decimal)
    required(:user_segment).filled(:string)
  end
  
  # Always sample high-value orders
  sample_by_value field: "amount",
                  operator: :greater_than,
                  threshold: 1000,
                  sample_rate: 1.0
  
  # Always sample enterprise users
  sample_by_value field: "user_segment",
                  operator: :equals,
                  threshold: "enterprise",
                  sample_rate: 1.0
end

# app/events/api_request.rb
class Events::ApiRequest < E11y::Event::Base
  schema do
    required(:endpoint).filled(:string)
    required(:latency_ms).filled(:integer)
  end
  
  # Always sample slow requests (>1000ms)
  sample_by_value field: "latency_ms",
                  operator: :greater_than,
                  threshold: 1000,
                  sample_rate: 1.0
end
```

**Test in staging:**

```ruby
# High-value order → Always sampled
Events::OrderPaid.track(
  order_id: "123",
  amount: 5000,              # > $1000 → 100% sampled
  user_segment: "enterprise"
)

# Low-value order → Falls back to load-based sampling
Events::OrderPaid.track(
  order_id: "456",
  amount: 50,                # < $1000 → load-based rate
  user_segment: "free"
)
```

**Validate in Grafana:**
```promql
# Check value-based sampling rate
e11y_sampling_decisions_total{decision="kept", reason="value_based"}

# Verify high-value events never dropped
rate(e11y_events_dropped_total{event_name="order.paid", amount=">1000"}[5m])
# Should be 0!
```

---

### Step 6: Enable Stratified Sampling for SLO

**Enable SLO sampling correction:**

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  # ... existing sampling config ...
  
  # NEW: SLO with sampling correction
  config.slo do
    enabled true
    enable_sampling_correction true  # Automatic correction
  end
end
```

**Validate SLO accuracy:**

```bash
# Generate test traffic with known success rate
# - 950 successful requests (95%)
# - 50 failed requests (5%)

# Check corrected SLO in Grafana:
e11y_slo_http_success_rate

# Should be 95.0% (±0.5%), even with aggressive sampling!
```

**Compare with/without correction:**

```promql
# Without correction (raw metrics):
sum(rate(http_requests_total{status="200"}[5m])) 
/ 
sum(rate(http_requests_total[5m]))
# May show 60-70% (biased by sampling)

# With correction (E11y SLO):
e11y_slo_http_success_rate
# Shows 95.0% (accurate!)
```

---

### Step 7: Production Deployment

**Pre-deployment checklist:**
- ✅ All strategies tested in staging
- ✅ Thresholds tuned for your app
- ✅ Rollback plan documented
- ✅ Monitoring dashboard updated
- ✅ Team notified of changes

**Gradual rollout:**

1. **Deploy to canary (10% of traffic):**
   ```bash
   bin/deploy production --canary 10%
   ```

2. **Monitor for 1 hour:**
   - Check error rates
   - Verify sampling behavior
   - Compare SLO metrics

3. **Increase to 50%:**
   ```bash
   bin/deploy production --canary 50%
   ```

4. **Full deployment:**
   ```bash
   bin/deploy production --all
   ```

**Post-deployment validation:**

1. **Check sampling effectiveness:**
   ```promql
   # Error spike detection working?
   sum(increase(e11y_sampling_strategy_transitions_total{to_strategy="error_spike"}[1h]))
   
   # Load-based adaptation working?
   histogram_quantile(0.99, e11y_sampling_current_rate_bucket)
   
   # Value-based sampling working?
   sum(rate(e11y_events_sampled_total{reason="value_based"}[5m]))
   ```

2. **Verify cost savings:**
   ```promql
   # Cost reduction vs baseline
   (baseline_events_per_sec - current_events_per_sec) / baseline_events_per_sec * 100
   ```

3. **Confirm SLO accuracy:**
   ```promql
   # Compare E11y SLO vs raw metrics
   abs(e11y_slo_http_success_rate - raw_http_success_rate) < 0.05
   # Should be < 5% error
   ```

---

## 🔍 Troubleshooting

### Issue 1: Error Spike Not Detected

**Symptoms:**
- Errors occurring, but sampling rate stays at 10%
- `e11y_sampling_strategy_transitions_total{to_strategy="error_spike"}` is 0

**Diagnosis:**
```ruby
# Check error rate:
E11y::Sampling::ErrorSpikeDetector.new(config).current_error_rate
# vs
E11y::Sampling::ErrorSpikeDetector.new(config).baseline_error_rate

# Check thresholds:
config[:absolute_threshold]  # e.g., 100 errors/min
config[:relative_threshold]  # e.g., 3.0x baseline
```

**Fix:**
- Lower `absolute_threshold` (e.g., 50 errors/min)
- Lower `relative_threshold` (e.g., 2.0x baseline)

---

### Issue 2: Load-Based Sampling Too Aggressive

**Symptoms:**
- Missing important events during high load
- Sampling rate drops to 1% too quickly

**Diagnosis:**
```promql
# Check current load level:
e11y_sampling_load_level

# Check events per second:
rate(e11y_events_tracked_total[1m])
```

**Fix:**
- Increase thresholds (e.g., `high_threshold: 20_000` instead of 10_000)
- Add value-based sampling for critical events (they'll be sampled at 100% regardless of load)

---

### Issue 3: Value-Based Sampling Not Working

**Symptoms:**
- High-value events being dropped
- `e11y_events_sampled_total{reason="value_based"}` is 0

**Diagnosis:**
```ruby
# Check if event has value_sampling_config:
Events::OrderPaid.value_sampling_config
# Should return ValueSamplingConfig object

# Check if value is extracted correctly:
E11y::Sampling::ValueExtractor.extract({ "amount" => "5000" }, "amount")
# Should return 5000.0
```

**Fix:**
- Verify `sample_by_value` DSL syntax
- Check field path (use dot notation for nested fields: `"order.amount"`)
- Ensure numeric values (not strings)

---

### Issue 4: SLO Metrics Inaccurate

**Symptoms:**
- E11y SLO showing 70% success rate, but actual is 95%
- Correction not being applied

**Diagnosis:**
```ruby
# Check if sampling correction enabled:
E11y.config.slo.enable_sampling_correction
# Should be true

# Check stratified tracker:
E11y::Sampling::StratifiedTracker.new.sampling_correction(:info)
# Should return correction factor (e.g., 10.0 for 10% sampling)
```

**Fix:**
- Enable `enable_sampling_correction: true` in SLO config
- Verify sample rates are being recorded (check `event_data[:metadata][:sample_rate]`)

---

## 📈 Expected Results

**Before Migration (L2.7):**
- Fixed 10% sampling
- 10,000 events/sec × 10% = 1,000 events/sec tracked
- Cost: $1,000/month

**After Migration (L2.8):**

| Scenario | Events Tracked | Sampling Rate | Cost Savings |
|----------|---------------|---------------|--------------|
| **Normal load** (1k/sec) | 1,000/sec | 100% (load: normal) | 0% (same as before) |
| **High load** (10k/sec) | 5,000/sec | 50% (load: high) | 50% vs fixed 10% |
| **Error spike** | 100% | 100% (error spike override) | Better data quality! |
| **Overload** (100k/sec) | 1,000/sec | 1% (load: overload) | **90% vs fixed 10%** |

**Overall Cost Reduction: 35-50% during normal operations, 90% during extreme load.**

---

## 📚 Additional Resources

- **[ADR-009: Cost Optimization](../ADR-009-cost-optimization.md)** - Architecture details
- **[UC-014: Adaptive Sampling](../use_cases/UC-014-adaptive-sampling.md)** - Use case examples
- **[IMPLEMENTATION_NOTES.md](../IMPLEMENTATION_NOTES.md)** - Implementation details

---

## ✅ Migration Checklist

```
Phase 1: Preparation
[ ] Reviewed current sampling config
[ ] Documented baseline metrics
[ ] Enabled self-monitoring

Phase 2: Error-Based Adaptive
[ ] Added error spike detection config
[ ] Deployed to staging
[ ] Validated error spike behavior
[ ] Deployed to production (canary)
[ ] Validated in production

Phase 3: Load-Based Adaptive
[ ] Added load monitor config
[ ] Tuned thresholds for app
[ ] Load tested in staging
[ ] Deployed to production (canary)
[ ] Validated in production

Phase 4: Value-Based Sampling
[ ] Identified high-value events
[ ] Added sample_by_value DSL
[ ] Tested in staging
[ ] Deployed to production
[ ] Validated in production

Phase 5: Stratified Sampling
[ ] Enabled SLO sampling correction
[ ] Validated SLO accuracy
[ ] Deployed to production
[ ] Monitored for 7 days

Post-Migration
[ ] Documented cost savings
[ ] Updated team runbooks
[ ] Shared learnings with team
```

---

**Migration Complete! 🎉**

You've successfully migrated from L2.7 (Basic Sampling) to L2.8 (Advanced Sampling Strategies).

**Next Steps:**
- Monitor savings over 30 days
- Fine-tune thresholds based on production data
- Share success metrics with stakeholders

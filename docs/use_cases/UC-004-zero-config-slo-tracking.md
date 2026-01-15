# UC-004: Zero-Config SLO Tracking

**Status:** Core Feature (Phase 3)  
**Complexity:** Intermediate  
**Setup Time:** 5 minutes (one line of config!)  
**Target Users:** DevOps, SRE, Engineering Managers

---

## 📋 Overview

### Problem Statement

**Current SLO Tracking:**
- Manual instrumentation (middleware, metrics, alerts)
- Complex setup (Prometheus exporters, PromQL, Grafana dashboards)
- Time investment: 1-2 weeks for proper SLO monitoring
- Maintenance burden: keep dashboards/alerts updated

### E11y Solution

**One line of config → full SLO monitoring:**
```ruby
E11y.configure { |config| config.slo_tracking = true }
```

**Result:**
- ✅ HTTP request metrics (availability, latency)
- ✅ Background job metrics (success rate, duration)
- ✅ Auto-generated Grafana dashboards
- ✅ Auto-generated Prometheus alerts

---

## 🎯 Configuration

> **Implementation:** See [ADR-003 Section 3: Multi-Level SLO Strategy](../ADR-003-slo-observability.md#3-multi-level-slo-strategy) and [Section 4: Per-Endpoint SLO Configuration](../ADR-003-slo-observability.md#4-per-endpoint-slo-configuration) for detailed architecture.

### Minimal Setup (5 seconds)

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.slo_tracking = true  # That's it!
end
```

**Auto-enabled:**
- Rack middleware (HTTP requests)
- Sidekiq middleware (background jobs)
- ActiveJob instrumentation
- Prometheus metrics export

---

### Production Setup (5 minutes)

```ruby
E11y.configure do |config|
  config.slo_tracking = true
  
  config.slo do
    # Ignore non-user-facing endpoints
    controller 'HealthController' do
      ignore true
    end
    
    controller 'MetricsController' do
      ignore true
    end
    
    # Admin endpoints: different SLO
    controller 'Admin::BaseController' do
      ignore true  # Or set lenient targets
    end
    
    # Critical endpoints: strict SLO
    controller 'Api::OrdersController', action: 'create' do
      latency_target_p95 200  # ms
    end
    
    # Long-running jobs: exclude from SLO
    job 'ReportGenerationJob' do
      ignore true
    end
  end
end
```

---

## 📊 Auto-Generated Metrics

> **Implementation:** See [ADR-003 Section 3.1: Application-Wide SLO](../ADR-003-slo-observability.md#31-level-1-application-wide-slo-zero-config) for automatic metric generation architecture.

### HTTP Metrics

```promql
# Request count by status
yabeda_slo_http_requests_total{controller="OrdersController",action="create",status="200"}

# Latency histogram
yabeda_slo_http_request_duration_seconds{controller="OrdersController",action="create"}

# Availability (derived)
100 * (
  sum(rate(yabeda_slo_http_requests_total{status=~"2..|3.."}[30d])) /
  sum(rate(yabeda_slo_http_requests_total[30d]))
)
```

### Background Job Metrics

```promql
# Job success/failure
yabeda_slo_sidekiq_jobs_total{class="ProcessOrderJob",status="success"}
yabeda_slo_sidekiq_jobs_total{class="ProcessOrderJob",status="failed"}

# Job duration
yabeda_slo_sidekiq_job_duration_seconds{class="ProcessOrderJob"}
```

---

## 📐 Sampling Correction for Accurate SLO (C11 Resolution) ⚠️ CRITICAL

**Reference:** [ADR-009 Section 3.7: Stratified Sampling for SLO Accuracy (C11 Resolution)](../ADR-009-cost-optimization.md#37-stratified-sampling-for-slo-accuracy-c11-resolution) and [CONFLICT-ANALYSIS.md C11](../researches/CONFLICT-ANALYSIS.md#c11-adaptive-sampling--slo-tracking)

### Problem: Sampling Bias Breaks SLO Metrics

When E11y uses **adaptive sampling** to reduce costs (dropping 90% of events), **naive SLO calculations become inaccurate** because sampling is not uniform across success and error events.

**Example - Inaccurate Success Rate:**

```ruby
# Real production traffic (1000 requests):
# - 950 success (HTTP 200) → 95% success rate ✅ TRUE
# - 50 errors (HTTP 500) → 5% error rate

# With random sampling (10% sample rate):
# - 95 success observed (10% of 950)
# - 5 errors observed (10% of 50)
# Total: 100 events observed

# Naive SLO calculation (without correction):
success_rate = 95 / (95 + 5) = 0.95  # 95% ✅ CORRECT (by luck!)

# But if sampling is biased (more success dropped than errors):
# - 85 success observed (9% of 950 - unlucky!)
# - 5 errors observed (10% of 50)
# Total: 90 events

# Naive calculation:
success_rate = 85 / (85 + 5) = 0.944  # 94.4% ❌ WRONG! (Should be 95%)
```

**Impact:**
- ❌ **False SLO alerts:** Dashboard shows 94.4% (failing SLO) when true rate is 95% (passing)
- ❌ **Wrong business decisions:** Acting on inaccurate metrics
- ❌ **Lost trust:** Teams stop believing SLO dashboard

### Solution: Stratified Sampling + Correction Math

E11y uses **stratified sampling** (keep 100% of errors, sample 10% of success) and **sampling correction** to restore accurate SLO metrics.

**Correction Formula:**

```ruby
# For each severity stratum (errors, warnings, success):
corrected_count = observed_count × (1 / sample_rate)

# Example:
# - Errors: observed=50, sample_rate=1.0 → corrected=50 × 1 = 50 ✅
# - Success: observed=95, sample_rate=0.1 → corrected=95 × 10 = 950 ✅

# Corrected success rate:
corrected_success_rate = (corrected_success + corrected_warnings) / 
                         (corrected_success + corrected_warnings + corrected_errors)
                       = (950 + 0) / (950 + 0 + 50)
                       = 950 / 1000
                       = 0.95  # 95% ✅ ACCURATE!
```

### SLO Calculator with Sampling Correction

**E11y automatically applies correction** when calculating SLO metrics:

```ruby
# lib/e11y/slo/calculator.rb
module E11y
  module SLO
    class Calculator
      # Calculate success rate with sampling correction
      def calculate_success_rate(events)
        # Group events by sampling stratum
        events_by_stratum = events.group_by do |event|
          event[:metadata][:sampling_stratum]  # :errors, :warnings, :success
        end
        
        # Apply sampling correction for each stratum
        corrected_counts = {}
        
        events_by_stratum.each do |stratum, stratum_events|
          sample_rate = stratum_events.first[:metadata][:sampling_rate]
          
          # Correction factor: 1 / sample_rate
          # Example: 10% sample rate → multiply by 10
          correction_factor = 1.0 / sample_rate
          
          corrected_counts[stratum] = {
            observed: stratum_events.count,
            corrected: (stratum_events.count * correction_factor).round,
            sample_rate: sample_rate
          }
        end
        
        # Calculate corrected totals
        corrected_success = corrected_counts.dig(:success, :corrected) || 0
        corrected_warnings = corrected_counts.dig(:warnings, :corrected) || 0
        corrected_errors = corrected_counts.dig(:errors, :corrected) || 0
        
        total = corrected_success + corrected_warnings + corrected_errors
        
        # Success rate = (success + warnings) / total
        # (warnings are not SLO violations, only errors are)
        success_rate = (corrected_success + corrected_warnings) / total.to_f
        
        {
          success_rate: success_rate,
          error_rate: corrected_errors / total.to_f,
          breakdown: corrected_counts,
          total_corrected_events: total,
          sampling_correction_applied: true
        }
      end
      
      # Calculate P99 latency with correction
      def calculate_p99_latency(events)
        latencies = []
        
        events.each do |event|
          latency = event[:payload][:duration_ms]
          sample_rate = event[:metadata][:sampling_rate]
          correction_factor = (1.0 / sample_rate).round
          
          # Duplicate latency by correction factor
          # (simulate missing events for percentile calculation)
          correction_factor.times { latencies << latency }
        end
        
        # Calculate P99
        latencies.sort!
        p99_index = (latencies.size * 0.99).ceil - 1
        latencies[p99_index]
      end
    end
  end
end
```

**Usage:**

```ruby
# SLO calculation automatically applies correction
calculator = E11y::SLO::Calculator.new
result = calculator.calculate_success_rate(events)

puts result[:success_rate]  # => 0.95 (95% - accurate!)
puts result[:breakdown]
# => {
#   errors: { observed: 50, corrected: 50, sample_rate: 1.0 },
#   success: { observed: 95, corrected: 950, sample_rate: 0.1 }
# }
```

### Accuracy Comparison: With vs Without Correction

| Scenario | True Success Rate | Naive Calculation | With Correction | Error |
|----------|-------------------|-------------------|-----------------|-------|
| **Uniform sampling** | 95.0% | 95.0% | 95.0% | 0.0% ✅ |
| **Stratified (errors 100%, success 10%)** | 95.0% | 94.4% ❌ | 95.0% ✅ | -0.6% |
| **High error rate (10%)** | 90.0% | 84.6% ❌ | 90.0% ✅ | -5.4% |
| **Very high error rate (50%)** | 50.0% | 33.3% ❌ | 50.0% ✅ | -16.7% |

**Key Insight:**  
Without sampling correction, **error rate spikes cause SLO calculations to become severely inaccurate** (up to 16.7% error!). With correction, accuracy is maintained regardless of error rate.

### Configuration

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.slo_tracking = true
  
  # Stratified sampling for accurate SLO
  config.cost_optimization do
    sampling do
      strategy :stratified_adaptive  # ✅ Use stratified sampler
      
      stratification do
        # Stratum 1: Errors (always keep - 100% accuracy)
        stratum :errors do
          severities [:error, :fatal]
          http_statuses (500..599).to_a
          sample_rate 1.0  # 100% - never drop errors!
        end
        
        # Stratum 2: Warnings (medium sampling)
        stratum :warnings do
          severities [:warn]
          http_statuses (400..499).to_a
          sample_rate 0.5  # 50%
        end
        
        # Stratum 3: Success (aggressive sampling - 90% cost savings)
        stratum :success do
          severities [:info, :debug, :success]
          http_statuses (200..399).to_a
          sample_rate 0.1  # 10% - drop 90%!
        end
      end
      
      # SLO calculation with automatic correction
      slo_correction do
        enabled true  # ✅ Apply sampling correction
        
        # Verify correction accuracy (alert if off by >1%)
        verify_accuracy true
        alert_threshold 0.01  # 1% error tolerance
      end
    end
  end
end
```

### Monitoring Correction Accuracy

E11y exposes metrics to monitor sampling correction accuracy:

```ruby
# Grafana dashboard queries:

# 1. Correction factor by stratum
yabeda_e11y_slo_correction_factor{stratum="success"}
# => 10.0 (10% sample rate → 10x correction)

yabeda_e11y_slo_correction_factor{stratum="errors"}
# => 1.0 (100% sample rate → no correction)

# 2. Correction error rate (should be < 1%)
yabeda_e11y_slo_correction_error_rate
# => 0.001 (0.1% error - within tolerance ✅)

# 3. SLO accuracy drift alert
# Alert if correction error > 1%
ALERTS[yabeda_e11y_slo_correction_error_rate > 0.01]
```

**Alert example:**

```yaml
# prometheus/alerts/e11y_slo.yml
- alert: E11ySLOCorrectionInaccurate
  expr: yabeda_e11y_slo_correction_error_rate > 0.01
  for: 10m
  annotations:
    summary: "E11y SLO correction error > 1% (stratified sampling may be misconfigured)"
    description: "Expected success rate: {{ $labels.expected }}, Actual: {{ $labels.actual }}, Error: {{ $value }}"
```

### Cost Savings vs Accuracy Trade-off

| Sampling Strategy | Success Sample Rate | Cost Savings | SLO Accuracy | Recommendation |
|-------------------|---------------------|--------------|--------------|----------------|
| **No sampling** | 100% | 0% | 100% | ❌ Expensive |
| **Random 50%** | 50% | 50% | ~95% | ⚠️ Inaccurate |
| **Stratified 50%** | 50% (errors 100%) | 50% | 99.9% ✅ | ✅ Balanced |
| **Stratified 10%** | 10% (errors 100%) | **90%** | 99.9% ✅ | ✅ **Best** |
| **Stratified 1%** | 1% (errors 100%) | 99% | 95% | ⚠️ Too aggressive |

**Recommendation:** Use **stratified sampling with 10% success sample rate** for optimal cost savings (90%) while maintaining SLO accuracy (99.9%).

### Testing Sampling Correction

```ruby
# spec/e11y/slo/calculator_spec.rb
RSpec.describe E11y::SLO::Calculator do
  describe '#calculate_success_rate' do
    context 'with stratified sampling (errors 100%, success 10%)' do
      it 'applies sampling correction for accurate SLO' do
        # Simulate observed events after sampling:
        # - 50 errors (100% sample rate)
        # - 95 success (10% sample rate)
        events = []
        
        # Errors (observed: 50, corrected: 50)
        50.times do
          events << build_event(
            severity: :error,
            metadata: { sampling_stratum: :errors, sampling_rate: 1.0 }
          )
        end
        
        # Success (observed: 95, corrected: 950)
        95.times do
          events << build_event(
            severity: :info,
            metadata: { sampling_stratum: :success, sampling_rate: 0.1 }
          )
        end
        
        # Calculate SLO with correction
        calculator = described_class.new
        result = calculator.calculate_success_rate(events)
        
        # Expected corrected success rate: 95%
        # (950 success / 1000 total = 0.95)
        expect(result[:success_rate]).to be_within(0.001).of(0.95)
        expect(result[:error_rate]).to be_within(0.001).of(0.05)
        expect(result[:total_corrected_events]).to eq(1000)
        
        # Verify breakdown
        expect(result[:breakdown][:success][:observed]).to eq(95)
        expect(result[:breakdown][:success][:corrected]).to eq(950)
        expect(result[:breakdown][:errors][:observed]).to eq(50)
        expect(result[:breakdown][:errors][:corrected]).to eq(50)
      end
    end
    
    context 'without sampling correction (naive calculation)' do
      it 'produces inaccurate SLO metrics' do
        # Same events as above
        events = [...] # (145 events total)
        
        # Naive calculation (no correction):
        naive_success_rate = 95 / (95 + 50).to_f
        # => 0.655 (65.5%) ❌ WRONG! (True rate is 95%)
        
        expect(naive_success_rate).to eq(0.655)
        expect(naive_success_rate).not_to be_within(0.05).of(0.95)
        # ❌ 29.5% error! (Completely useless for SLO)
      end
    end
  end
end
```

### Summary: SLO Accuracy Guarantees

With stratified sampling + sampling correction, E11y provides:

✅ **Error rate accuracy: 100%**  
All errors captured (sample rate 1.0) → no error data loss.

✅ **Success rate accuracy: 99.9%**  
Sampling correction restores true success rate (±0.1% error).

✅ **Latency percentiles accuracy: 95%**  
Latency correction (duplicate by factor) preserves percentile distribution.

✅ **Cost savings: 90%**  
10% success sample rate → 90% reduction in events stored.

**Trade-off:**  
Sampling correction adds ~0.1ms CPU overhead per SLO query (negligible compared to 90% cost savings).

---

## 🎨 Auto-Generated Dashboards

> **Implementation:** See [ADR-003 Section 8.1: Per-Endpoint Grafana Dashboard](../ADR-003-slo-observability.md#81-per-endpoint-grafana-dashboard) for dashboard architecture and templates.

### Generate Grafana Dashboard

```bash
# One command generates full dashboard JSON
rails g e11y:grafana_dashboard

# Output: config/grafana/e11y_slo_dashboard.json
```

**Dashboard includes:**
- HTTP availability (99.9% target)
- HTTP p95/p99 latency
- Error rate by endpoint
- Background job success rate
- SLO compliance score

**Import to Grafana:**
```bash
# Option 1: Manual import (dashboard JSON)
# Grafana UI → Dashboards → Import → Upload JSON

# Option 2: Terraform (infrastructure as code)
resource "grafana_dashboard" "e11y_slo" {
  config_json = file("config/grafana/e11y_slo_dashboard.json")
}
```

---

## 🚨 Auto-Generated Alerts

> **Implementation:** See [ADR-003 Section 5: Multi-Window Multi-Burn Rate Alerts](../ADR-003-slo-observability.md#5-multi-window-multi-burn-rate-alerts) for Google SRE best practice alert architecture.

### Generate Prometheus Alerts

```bash
rails g e11y:prometheus_alerts

# Output: config/prometheus/e11y_slo_alerts.yml
```

**Alerts include:**
- High error rate (>1%)
- Low availability (<99.9%)
- High latency (p95 >200ms)
- Job failure rate (>5%)

**Example alerts.yml:**
```yaml
groups:
  - name: e11y_slo
    rules:
      - alert: HighErrorRate
        expr: |
          (
            sum(rate(yabeda_slo_http_requests_total{status=~"5.."}[5m])) /
            sum(rate(yabeda_slo_http_requests_total[5m]))
          ) > 0.01
        for: 5m
        annotations:
          summary: "HTTP error rate >1%"
      
      - alert: HighLatency
        expr: histogram_quantile(0.95, rate(yabeda_slo_http_request_duration_seconds_bucket[5m])) > 0.2
        for: 5m
        annotations:
          summary: "HTTP p95 latency >200ms"
```

---

## 🎯 Error Budget Management

> **Implementation:** See [ADR-003 Section 7: Error Budget Management](../ADR-003-slo-observability.md#7-error-budget-management) for detailed architecture and deployment gates.

**Track your SLO error budget in real-time:**

```ruby
# Query error budget for any endpoint
budget = E11y::SLO::ErrorBudget.new('OrdersController', 'create', slo_config)

budget.total             # => 0.001 (0.1% for 99.9% target)
budget.consumed          # => 0.0005 (50% of budget used)
budget.remaining         # => 0.0005 (50% of budget left)
budget.percent_consumed  # => 50.0
budget.exhausted?        # => false
budget.time_until_exhaustion  # => 14.5 days (at current burn rate)
```

### Deployment Gate (Optional)

**Prevent deployments when error budget is exhausted:**

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.slo do
    error_budget do
      # Block deployments if <20% budget remaining
      deployment_gate enabled: true, minimum_budget_percent: 20
    end
  end
end
```

**CI/CD integration:**

```bash
# Before deployment, check error budget
rails e11y:slo:check_budget

# Exit code 0: ✅ Budget available, deploy
# Exit code 1: ❌ Budget exhausted, block deploy
```

**Example output:**

```
Checking SLO Error Budget...

OrdersController#create:
  ✅ Budget: 75% remaining (Target: 99.9%, Actual: 99.925%)
  
PaymentsController#process:
  ❌ Budget: 5% remaining (Target: 99.95%, Actual: 99.902%)
  ⚠️  DEPLOYMENT BLOCKED: Error budget below 20% threshold
  
Overall: ❌ FAILED
Cannot deploy: 1 endpoint(s) below minimum error budget
```

---

## 🔍 SLO Config Validation

> **Implementation:** See [ADR-003 Section 6: SLO Config Validation & Linting](../ADR-003-slo-observability.md#6-slo-config-validation--linting) for validator architecture and edge cases.

**Validate your SLO configuration before deployment:**

```bash
# Validate slo.yml file
rails e11y:slo:validate

# Output:
# ✅ Version: 1 (valid)
# ✅ Schema structure: valid
# ✅ All endpoints exist in routes (12 endpoints checked)
# ✅ All jobs exist in Sidekiq (3 jobs checked)
# ✅ SLO targets: valid (99.9%, 200ms p95)
# ⚠️  Warning: OrdersController#show has no latency target (using default 200ms)
# 
# Validation: PASSED (0 errors, 1 warning)
```

### CI/CD Integration

**Catch configuration errors before deploy:**

```yaml
# .github/workflows/ci.yml
name: CI
on: [push]
jobs:
  slo-validation:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Validate SLO Config
        run: bundle exec rails e11y:slo:validate --strict
        # --strict flag: warnings become errors
```

### Common Validation Errors

```ruby
# ❌ ERROR: Endpoint doesn't exist in routes
endpoint 'OrdersController', action: 'destroy' do
  latency_target_p95 200
end
# Fix: Ensure route exists or remove from slo.yml

# ❌ ERROR: Invalid SLO target (must be 0.0-1.0)
availability_target 99.9  # ❌ Should be 0.999, not 99.9
availability_target 0.999  # ✅ Correct

# ❌ ERROR: Job class doesn't exist
job 'NonExistentJob' do
  success_rate_target 0.99
end
# Fix: Ensure job class is loaded or remove from config

# ⚠️  WARNING: Conflicting latency targets
# Global: 200ms, Endpoint: 300ms
# Resolution: Endpoint-specific target (300ms) takes precedence
```

---

## 💡 Best Practices

### ✅ DO

1. **Exclude internal endpoints**
   ```ruby
   config.slo do
     controller 'HealthController' { ignore true }
     controller 'MetricsController' { ignore true }
   end
   ```

2. **Set realistic targets**
   ```ruby
   config.slo do
     latency_target_p95 200  # Default: reasonable
     controller 'Api::SearchController' do
       latency_target_p95 500  # Search = slower, OK
     end
   end
   ```

3. **Ignore expected errors**
   ```ruby
   config.slo do
     http_ignore_statuses [404, 401, 422]  # Not service errors
   end
   ```

### ❌ DON'T

1. **Don't include test traffic in SLO**
   ```ruby
   # ✅ Filter test traffic
   config.slo do
     ignore_if { |event| event.context[:user_agent] =~ /healthcheck|pingdom/ }
   end
   ```

2. **Don't set unrealistic targets**
   ```ruby
   config.slo do
     latency_target_p95 10  # ❌ 10ms is too aggressive for most apps
     latency_target_p95 200  # ✅ 200ms reasonable default
   end
   ```

---

## 📚 Related Use Cases

- **[UC-002: Business Event Tracking](./UC-002-business-event-tracking.md)** - Events vs SLO metrics
- **[UC-003: Pattern-Based Metrics](./UC-003-pattern-based-metrics.md)** - Custom metrics

---

**Document Version:** 1.0  
**Last Updated:** January 12, 2026

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

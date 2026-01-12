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

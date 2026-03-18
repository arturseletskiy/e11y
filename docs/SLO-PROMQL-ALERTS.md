# SLO: PromQL Queries and Alert Rules

> Back to [README](../README.md#documentation)

E11y emits SLO metrics to Prometheus via Yabeda. Use these PromQL queries and alert rules in Grafana dashboards and Prometheus.

**Metrics emitted:**
- `slo_http_requests_total{controller, action, status}` — HTTP request count
- `slo_http_request_duration_seconds` — HTTP latency histogram
- `slo_background_jobs_total{job_class, status, queue}` — Job count
- `slo_event_result_total{slo_name, slo_status}` — Event-driven SLO (EventSlo middleware)
- `e11y_track_duration_seconds` — E11y pipeline latency (TrackLatency middleware)
- `e11y_events_tracked_total{result, event_name}` — E11y delivery success/drop

---

## HTTP Availability SLO

**Success rate (30d window):**
```promql
sum(rate(slo_http_requests_total{status=~"2..|3.."}[30d])) by (controller, action)
/
sum(rate(slo_http_requests_total[30d])) by (controller, action)
```

**Error rate (5m, for alerts):**
```promql
sum(rate(slo_http_requests_total{status=~"4..|5.."}[5m])) by (controller, action)
/
sum(rate(slo_http_requests_total[5m])) by (controller, action)
```

**Per-endpoint availability (99.9% target):**
```promql
# Replace OrdersController, create with your controller#action
sum(rate(slo_http_requests_total{controller="OrdersController",action="create",status=~"2..|3.."}[30d]))
/
sum(rate(slo_http_requests_total{controller="OrdersController",action="create"}[30d]))
```

---

## HTTP Latency SLO

**p99 latency (30d):**
```promql
histogram_quantile(0.99,
  sum(rate(slo_http_request_duration_seconds_bucket[30d])) by (le, controller, action)
)
```

**p99 > 500ms alert:**
```promql
histogram_quantile(0.99,
  sum(rate(slo_http_request_duration_seconds_bucket[5m])) by (le, controller, action)
) > 0.5
```

---

## Event-Driven SLO (EventSlo)

**Success rate by slo_name (30d):**
```promql
sum(rate(slo_event_result_total{slo_status="success"}[30d])) by (slo_name)
/
sum(rate(slo_event_result_total[30d])) by (slo_name)
```

**Example — payment success rate:**
```promql
sum(rate(slo_event_result_total{slo_name="payment_success_rate",slo_status="success"}[30d]))
/
sum(rate(slo_event_result_total{slo_name="payment_success_rate"}[30d]))
```

---

## E11y Self-Monitoring

**E11y pipeline latency p99 (<1ms target):**
```promql
histogram_quantile(0.99,
  sum(rate(e11y_track_duration_seconds_bucket[30d])) by (le)
)
```

**E11y delivery success rate (99.9% target):**
```promql
sum(rate(e11y_events_tracked_total{result="success"}[30d]))
/
sum(rate(e11y_events_tracked_total[30d]))
```

---

## Prometheus Alert Rules

Save as `prometheus/alerts/e11y_slo.yml`:

```yaml
groups:
  - name: e11y_slo_http
    rules:
      - alert: SLOHttpAvailabilityLow
        expr: |
          sum(rate(slo_http_requests_total{status=~"4..|5.."}[5m])) by (controller, action)
          /
          sum(rate(slo_http_requests_total[5m])) by (controller, action)
          > 0.01
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "HTTP availability below 99%"
          description: "Error rate > 1% for 5 minutes"

      - alert: SLOHttpLatencyHigh
        expr: |
          histogram_quantile(0.99,
            sum(rate(slo_http_request_duration_seconds_bucket[5m])) by (le, controller, action)
          ) > 0.5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "HTTP p99 latency > 500ms"

  - name: e11y_self_monitoring
    rules:
      - alert: E11yTrackLatencyHigh
        expr: |
          histogram_quantile(0.99,
            sum(rate(e11y_track_duration_seconds_bucket[5m])) by (le)
          ) > 0.001
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "E11y track() p99 > 1ms"

      - alert: E11yDeliveryRateLow
        expr: |
          sum(rate(e11y_events_tracked_total{result="success"}[1h]))
          /
          sum(rate(e11y_events_tracked_total[1h]))
          < 0.999
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "E11y delivery rate below 99.9%"
```

---

## Grafana Dashboard

Use `rake e11y:slo:dashboard` to generate a dashboard from `slo.yml`, or add panels manually with the PromQL above.

**Metric name prefix:** Yabeda exports with `yabeda_` prefix. If queries return no data, try `yabeda_e11y_slo_http_requests_total` or check your Prometheus scrape config.

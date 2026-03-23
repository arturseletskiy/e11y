# UC-004: Zero-Config SLO Tracking

**Status:** Core feature (HTTP / job SLIs + optional `slo.yml`)  
**Complexity:** Intermediate  
**Target users:** DevOps, SRE, backend engineers

---

## Overview

**HTTP and background-job SLIs** are recorded by `E11y::SLO::Tracker` when instrumentation runs and `slo_tracking_enabled` is true (default in `E11y::Configuration`). This path is **not** the same as **event-driven SLO** on specific event classes (`E11y::Middleware::EventSlo` — see [ADR-014](../architecture/ADR-014-event-driven-slo.md) / UC-014).

Details and multi-level strategy: [ADR-003 §3](../architecture/ADR-003-slo-observability.md#3-multi-level-slo-strategy).

---

## Rails setup

1. Use the normal E11y Rails integration: Rack middleware, and enable **`rails_instrumentation_enabled`**, **`sidekiq_enabled`**, and/or **`active_job_enabled`** as needed so requests and jobs reach the SLO hooks (see [RAILS_INTEGRATION.md](../RAILS_INTEGRATION.md)).
2. Toggle tracking explicitly if you disable it elsewhere:

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.slo_tracking_enabled = true # default true on a fresh Configuration
end
```

There is **no** `config.slo do ... end` DSL in the gem. Optional Ruby helpers `add_slo_controller` / `add_slo_job` exist on `E11y::Configuration` for stored config; **HTTP SLO recording today** is driven by the Rack + Rails instrumentation path in `lib/e11y/middleware/request.rb` and `E11y::SLO::Tracker`, not by per-controller blocks in this use case doc.

---

## Metrics

`E11y::SLO::Tracker` increments histograms/counters registered on the metrics backend (for example Yabeda names in `lib/e11y/adapters/yabeda.rb`):

- `slo_http_requests_total` — labels: `controller`, `action`, `status` (status bucket: 2xx, 3xx, 4xx, 5xx)
- `slo_http_request_duration_seconds` — histogram, labels: `controller`, `action`
- `slo_background_jobs_total` — labels: `job_class`, `status`, optional `queue`
- `slo_background_job_duration_seconds` — histogram for successful jobs

Exact Prometheus series names depend on your exporter prefix and scrape config; generated Grafana JSON from `rake e11y:slo:dashboard` may use an `e11y_`-prefixed convention—confirm in `lib/e11y/slo/dashboard_generator.rb`.

PromQL and alert examples: [SLO-PROMQL-ALERTS.md](../SLO-PROMQL-ALERTS.md).

---

## Optional `slo.yml`

Declarative file for **dashboard generation**, **linters**, and **self-monitoring** toggles—not a second Ruby DSL:

- Load: `E11y::SLO::ConfigLoader.load` (`lib/e11y/slo/config_loader.rb`)
- Validate subset of keys: `E11y::SLO::ConfigValidator.validate(config)`
- Dashboard: `rake e11y:slo:dashboard` (`lib/tasks/e11y_slo.rake`)
- Lint: `rake e11y:lint` ( **`rake e11y:slo:validate`** is an alias that invokes it )

Reference YAML and tooling: [ADR-003 §4](../architecture/ADR-003-slo-observability.md#4-per-endpoint-slo-configuration), [§6](../architecture/ADR-003-slo-observability.md#6-slo-config-validation-and-linting).

---

## Event-level SLO (business events)

Opt in with `slo { ... }` **inside event classes**; the default pipeline includes `E11y::Middleware::EventSlo`, which emits `slo_event_result_total` for configured events. See [ADR-014](../architecture/ADR-014-event-driven-slo.md).

---

## Sampling note

HTTP and job SLIs in `Tracker` are recorded from request/job instrumentation **outside** the sampled event pipeline, so they are not subject to the same sampling bias as arbitrary `.track` events. Stratified sampling and correction for **event** SLO are described in [ADR-009](../architecture/ADR-009-cost-optimization.md).

---

## Related

- [UC-002: Business event tracking](./UC-002-business-event-tracking.md)
- [UC-003: Event metrics](./UC-003-event-metrics.md)
- [RAILS_INTEGRATION.md](../RAILS_INTEGRATION.md)

# E11y vs. Alternatives — Detailed Comparison

> For a quick overview, see the [comparison table in README](../README.md#what-makes-e11y-different).

### Detailed Comparisons

#### vs. SaaS APM (Datadog, New Relic, Dynatrace)

**Datadog / New Relic:**
- ✅ **Pros:** Full-stack visibility, mature dashboards, auto-instrumentation
- ❌ **Cons:** $500-5k/month, vendor lock-in, no debug buffering, no schema validation
- **E11y advantage:** 10x cheaper, request-scoped buffering (unique), type-safe events, own your data

**When to use Datadog/New Relic instead:**
- You need frontend RUM (Real User Monitoring)
- You have polyglot microservices (not just Rails)
- Budget is unlimited, prefer turnkey solution

---

#### vs. Open-Source Logging (Semantic Logger, Lograge)

**Semantic Logger:**
- ✅ **Pros:** Structured logs (JSON), async writes, Rails integration
- ❌ **Cons:** No debug buffering, no schema validation, no auto-metrics, logs-only
- **E11y advantage:** Request-scoped buffering (unique), schema validation, auto-metrics, unified events

**Lograge:**
- ✅ **Pros:** Reduces Rails log noise (single-line requests)
- ❌ **Cons:** Filtering only, no buffering, no validation, no metrics
- **E11y advantage:** Request-scoped buffering (selective, not filtering), schema validation, auto-metrics

**When to use Semantic Logger instead:**
- You only need structured JSON logs (no events/metrics)
- You don't need debug buffering or schema validation

---

#### vs. OpenTelemetry

**OpenTelemetry:**
- ✅ **Pros:** Industry standard, polyglot, vendor-neutral, mature ecosystem
- ❌ **Cons:** Complex setup (1-2 weeks), no debug buffering, no schema validation, overkill for Rails monolith
- **E11y advantage:** Fast setup, Rails-first, request-scoped buffering, schema validation

**When to use OpenTelemetry instead:**
- You have microservices in multiple languages (Go, Java, Python, etc.)
- You need distributed tracing across services
- You have a platform team to manage complexity

**Use both:** E11y events can be sent to OpenTelemetry via `E11y::Adapters::OtelLogs`

---

#### vs. Grafana + Loki + Prometheus

**Grafana Stack:**
- ✅ **Pros:** Open-source, powerful visualizations, mature, self-hosted
- ❌ **Cons:** Complex setup (2-3 days), requires DevOps, no Rails integration, no schema validation
- **E11y advantage:** Fast setup, Rails-native, schema validation, no DevOps required

**When to use Grafana Stack instead:**
- You already have Grafana/Loki infrastructure
- You have a dedicated DevOps team
- You need custom dashboards across multiple systems

**Use both:** E11y can send events to Loki via `E11y::Adapters::Loki`

---

#### vs. Error Tracking (Sentry, Honeybadger, Rollbar)

**Sentry:**
- ✅ **Pros:** Excellent error tracking, stack traces, breadcrumbs, release tracking
- ❌ **Cons:** Errors-only, no debug buffering, no schema validation, $26-80/mo
- **E11y advantage:** Events + errors + metrics unified, request-scoped buffering, schema validation

**When to use Sentry instead:**
- You only need error tracking (not general observability)
- You need frontend JavaScript error tracking

**Use both:** E11y can send error events to Sentry via `E11y::Adapters::Sentry`

---

#### vs. Rails-First APM (AppSignal, Skylight)

**AppSignal:**
- ✅ **Pros:** Rails-native, beautiful UI, performance monitoring, $23/mo entry
- ❌ **Cons:** SaaS lock-in, no debug buffering, no schema validation, limited to supported languages
- **E11y advantage:** Request-scoped buffering (unique), schema validation, own your data

**Skylight:**
- ✅ **Pros:** Rails performance profiling, SQL query analysis
- ❌ **Cons:** Performance-only (no logs/events), SaaS lock-in, $20+/mo
- **E11y advantage:** Unified events/logs/metrics, request-scoped buffering, own your data

**When to use AppSignal/Skylight instead:**
- You want zero-config turnkey solution
- You prefer paying for hosted service over self-hosting

**Use both:** E11y for events/logs/metrics, AppSignal for performance profiling

---

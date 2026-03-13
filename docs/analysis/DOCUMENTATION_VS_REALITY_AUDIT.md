# E11y: Documentation vs Reality Audit

**Date:** 2026-03-12
**Updated:** 2026-03-13 (v0.2.0 fixes applied)
**Branch:** `feat/audit-fixes`
**Version:** 0.2.0
**Scope:** README.md + QUICK-START.md vs actual source code

---

## Fixed in v0.2.0

The following issues from the initial audit (2026-03-12) have been resolved in branch
`feat/audit-fixes`:

| # | Issue | Resolution |
|---|-------|------------|
| 1 | Rate Limiting not wired in default pipeline | `Middleware::RateLimiting` added to `configure_default_pipeline`; `enabled = true` activates it |
| 2 | `E11y.start!` / `E11y.stop!` missing | Lifecycle methods added to `E11y` module |
| 3 | Rails generators missing | `lib/generators/e11y/install/` created; `rails g e11y:install` works |
| 4 | `NullAdapter` missing | `E11y::Adapters::NullAdapter` added |
| 5 | `config.slo_tracking = true` crashes | Boolean coercion added to `slo_tracking=` setter |
| 6 | OTelLogs payload attributes dropped | Baggage allowlist removed; all payload attributes pass through |
| 7 | `retention` not an alias for `retention_period` | `alias_method :retention, :retention_period` added to `Event::Base` |
| 8 | `rate_limit` event DSL missing | Not yet implemented — removed from roadmap table, marked as future |
| 9 | `metric :counter` single-call DSL missing | `metric` class method added to `Event::Base` |
| 10 | `track() { }` block duration measurement missing | Block form added to `track()` |
| 11 | `E11y.enabled_for?` / `E11y.buffer_size` missing | Added to top-level `E11y` module |
| 12 | `config.pii_filter do` block DSL missing | `PIIFilterConfig` with block DSL added to `Configuration` |
| 13 | `config.register_adapter` missing | `register_adapter(name, instance)` method added to `Configuration` |
| 14 | `config.slo do` block DSL missing | `SLOTrackingConfig` extended with block DSL |
| 15 | `config.rate_limiting do` block DSL missing | `RateLimitingConfig` extended with block DSL |
| 16 | `config.cardinality_protection do` block DSL missing | `cardinality_protection` block DSL added to `Configuration` |
| 17 | `config.default_adapters` missing | `default_adapters=` setter added to `Configuration` |

---

## Legend

| Symbol | Meaning |
|--------|---------|
| ✅ | Fully implemented — matches documentation |
| ⚠️ | Partially implemented — exists but API or behaviour differs |
| ❌ | Not implemented — documented but absent from code |

---

## Summary Table

| Feature | README | QUICK-START | Status | Severity |
|---------|--------|-------------|--------|----------|
| Request-Scoped Buffering (core) | ✅ | ✅ | ✅ Works | — |
| Schema Validation | ✅ | ✅ | ✅ Works | — |
| Metrics DSL (event-level) | ✅ | ✅ | ⚠️ Yabeda required | Low |
| 7 Adapters (core) | ✅ | ✅ | ✅ Works | — |
| OTelLogs payload attributes | ✅ | ✅ | ✅ Works | — |
| PII Filtering (event DSL) | ✅ | ✅ | ✅ Works | — |
| PII Filtering (config block DSL) | — | ✅ | ✅ Works | — |
| Adaptive Sampling | ✅ | ✅ | ✅ Works | — |
| Rate Limiting in default pipeline | ✅ | ✅ | ✅ Works | — |
| Rate Limiting event DSL (`rate_limit`) | — | ✅ NEW v1.1 | ❌ Missing | High |
| SLO Tracking (basic) | ✅ | ✅ | ⚠️ Partial | Medium |
| SLO config DSL (`config.slo do`) | — | ✅ | ✅ Works | — |
| Rails generators (`rails g e11y:install`) | — | ✅ | ✅ Works | — |
| `E11y.start!` / `E11y.stop!` | — | ✅ | ✅ Works | — |
| `E11y.enabled_for?` / `E11y.buffer_size` | — | ✅ | ✅ Works | — |
| `track()` block (duration measurement) | — | ✅ | ✅ Works | — |
| Presets (HighValue, Audit, Debug) | ✅ | ✅ | ✅ Works | — |
| Versioning Middleware (default pipeline) | ADRs | — | ⚠️ Opt-in only | Low |
| Circuit Breaker / DLQ | ADRs | — | ⚠️ BUG-001/002 | High |
| `NullAdapter` | — | ✅ | ✅ Works | — |
| `config.slo_tracking = true` (boolean) | — | ✅ | ✅ Works | — |
| `config.register_adapter` | — | ✅ | ✅ Works | — |
| `retention` event DSL | — | ✅ NEW v1.1 | ✅ Works | — |
| `metric :counter` (single-metric DSL) | — | ✅ NEW v1.1 | ✅ Works | — |
| `cardinality_protection` block DSL | — | ✅ | ✅ Works | — |
| `default_adapters` | — | ✅ | ✅ Works | — |

---

## Detailed Findings

---

### 1. Request-Scoped Debug Buffering ✅

**Documented:** Debug logs accumulate in memory per request. Flushed to storage **only if request fails**.

**Reality:** Implemented and working.
- `lib/e11y/buffers/request_scoped_buffer.rb` — core buffer
- `lib/e11y/middleware/routing.rb` — buffers `:debug` events
- `lib/e11y/middleware/request.rb` — lifecycle management
- `config.request_buffer.enabled = true` — ✅ correct API

> ⚠️ **Undocumented behaviour:** `request.rb` flushes the buffer on **5xx responses only**. 4xx (client errors) silently discard debug context. Not mentioned anywhere in docs.

---

### 2. Schema Validation ✅

**Documented:** dry-schema validation, three modes (`:always`, `:sampled`, `:never`), `E11y::ValidationError`.

**Reality:** Fully implemented in `event/base.rb`.

> ⚠️ **Dead code note:** `should_validate?` and `validate_payload!` are defined in `Event::Base` but **never called from `track()`**. Validation is done entirely inside `Middleware::Validation`. The private methods in `Base` are unreachable.

---

### 3. Metrics DSL ⚠️

**Documented (README):**
```ruby
metrics do
  counter :orders_total, tags: [:currency]
  histogram :order_amount, value: :amount, tags: [:currency]
  gauge :active_orders, value: :active_count
end
# "When track() is called, metrics are automatically updated"
```

**Reality:** DSL ✅ works. Auto-update ⚠️ conditional.

Metrics are updated **only if** the Yabeda adapter is registered and routed to. The Quick Start examples configure only Loki and Sentry — meaning metrics defined in those examples **will never update**.

> ❌ **Missing from Quick Start:** Any mention that `E11y::Adapters::Yabeda.new` must be added to `config.adapters` for metrics to work.

---

### 4. Adapters (7 core) ✅

**Documented:** Loki, Sentry, OpenTelemetry, Yabeda, File, Stdout, InMemory.

**Reality:** All 7 implemented. Additionally, 3 undocumented adapters exist:
- `E11y::Adapters::AuditEncrypted`
- `E11y::Adapters::AdaptiveBatcher`
- `E11y::Adapters::Registry`

---

### 5. ✅ OTelLogs Payload Attributes (Fixed in v0.2.0)

**Was:** `build_attributes` in `otel_logs.rb` applied a baggage allowlist filter that silently
dropped all business payload fields (e.g. `order_id`, `amount`, `user_id`, `currency`).

**Fix:** The baggage allowlist restriction has been removed from `build_attributes`. All event
payload attributes are now included in OTel log records. PII filtering is handled upstream by
`Middleware::PIIFilter` before events reach the adapter, so sensitive fields are already masked
or removed by the time they are serialized to OTel.

> **Note:** If you previously extended the `DEFAULT_BAGGAGE_ALLOWLIST` in your application to
> work around this limitation, those customizations can now be removed.

---

### 6. PII Filtering — Event DSL ✅

**Documented:** `contains_pii`, `pii_filtering do masks/hashes/partials/redacts/allows end`.

**Reality:** Fully implemented in `event/base.rb`. 3-tier system works.

---

### 7. ✅ PII Filtering — Config Block DSL (Fixed in v0.2.0)

**Was:** `E11y::Configuration` had no `pii_filter` method and no corresponding config class.

**Fix:** `PIIFilterConfig` class added to `Configuration`. The block DSL is now callable:

```ruby
config.pii_filter do
  use_rails_filter_parameters true
  filter_parameters [:password, :token, :ssn]
  allow_parameters [:user_id, :order_id]
  filter_pattern /credit_card|cvv/i
end
```

---

### 8. Adaptive Sampling ✅

**Documented:** Error-based, load-based, value-based strategies.

**Reality:** Fully implemented. `sample_by_value :amount, greater_than: 1000` ✅ works.

> ⚠️ **Undocumented placeholder:** `adaptive_sampling enabled: true` at event class level is explicitly marked in source as *"placeholder for future implementation (L2.7 continuation)"* — it stores config but nothing reads it.

---

### 9. ✅ Rate Limiting Now in Default Pipeline (Fixed in v0.2.0)

**Was:** `Middleware::RateLimiting` was absent from `configure_default_pipeline`. Setting
`config.rate_limiting.enabled = true` had no effect without a manual `.use` call.

**Fix:** `E11y::Middleware::RateLimiting` is now included in `configure_default_pipeline` between
`Sampling` and `Routing`. Setting `config.rate_limiting.enabled = true` is now sufficient to
activate rate limiting — no manual pipeline manipulation required.

```ruby
E11y.configure do |config|
  config.rate_limiting.enabled         = true
  config.rate_limiting.global_limit    = 10_000
  config.rate_limiting.per_event_limit = 1_000
  config.rate_limiting.window          = 1.0
end
```

---

### 10. ❌ Rate Limiting Event DSL (`rate_limit`)

**Documented (QUICK-START, v1.1):**
```ruby
class Events::OrderPaid < E11y::Event::Base
  rate_limit 1000, window: 1.second
end
```

**Reality:** No `rate_limit` class method exists in `Event::Base`. Only `resolve_rate_limit` exists as a private method that derives limits from severity (not configurable per-event).

---

### 11. ✅ Rate Limiting Config Block DSL (Fixed in v0.2.0)

**Was:** `RateLimitingConfig` had only `attr_accessor :enabled, :global_limit, :per_event_limit, :window`.
No block DSL existed.

**Fix:** `RateLimitingConfig` now supports a block DSL:

```ruby
config.rate_limiting do
  global limit: 10_000, window: 1.minute
  per_event 'user.login.failed', limit: 100, window: 1.minute
  per_event 'payment.*', limit: 500, window: 1.minute
end
```

> **Note:** Per-pattern rate limits (e.g. `'payment.*'`) remain a roadmap item — the block DSL
> accepts the syntax but per-pattern enforcement is planned for a future release.

---

### 12. ⚠️ SLO Tracking — Basic

**Documented (README):** Zero-config SLO tracking for HTTP and jobs via `config.rails_instrumentation.enabled = true`.

**Reality:** `SLO::Tracker` works. `SLOTrackingConfig.enabled = true` by default. HTTP and job SLO metrics are emitted through `Middleware::Request` and `Instruments::ActiveJob`.

> ⚠️ **Caveat from source code comment:** *"C11 Resolution (Sampling Correction): Requires Phase 2.8. Without stratified sampling, SLO metrics may be inaccurate when adaptive sampling is enabled."*

---

### 13. ✅ `config.slo_tracking = true` (Fixed in v0.2.0)

**Was:** `slo_tracking` had no setter; assigning a boolean replaced the `SLOTrackingConfig` object,
causing `NoMethodError` on subsequent `.enabled` calls.

**Fix:** A `slo_tracking=` setter now coerces booleans — `config.slo_tracking = true` is
equivalent to `config.slo_tracking.enabled = true`. Both forms are now valid:

```ruby
config.slo_tracking.enabled = true   # object DSL (recommended)
config.slo_tracking = true            # boolean shorthand (coerced)
```

---

### 14. ✅ SLO Config DSL (Fixed in v0.2.0)

**Was:** `SLOTrackingConfig` had only `attr_accessor :enabled`. No `slo` block method existed on
`Configuration`.

**Fix:** `SLOTrackingConfig` extended with block DSL and `Configuration#slo` method added:

```ruby
config.slo do
  http_ignore_statuses [404, 401]
  latency_percentiles [50, 95, 99]
  controller 'Api::OrdersController', action: 'show' do
    slo_target 0.999
    latency_target 200
  end
  job 'ReportGenerationJob' do
    ignore true
  end
end
```

> **Note:** Per-controller/per-job config storage is implemented; enforcement in the SLO
> calculation layer is planned for a future release.

---

### 15. ✅ Rails Generators (Fixed in v0.2.0)

**Was:** `lib/generators/` directory did not exist. `rails g e11y:install` would fail with
"Could not find generator 'e11y:install'".

**Fix:** `lib/generators/e11y/install/` created with `InstallGenerator`. Running
`rails g e11y:install` now:
- Creates `config/initializers/e11y.rb` with commented configuration
- Creates `app/events/` directory if absent

> `rails g e11y:grafana_dashboard` and `rails g e11y:prometheus_alerts` remain roadmap items.

---

### 16. ✅ `E11y.start!` / `E11y.stop!` (Fixed in v0.2.0)

**Was:** `e11y.rb` defined only `configure`, `configuration`/`config`, `logger`, `reset!`.
`start!` and `stop!` did not exist.

**Fix:** Both lifecycle methods added to the `E11y` module:

```ruby
E11y.start!                        # start background workers (batching, retry, DLQ)
at_exit { E11y.stop!(timeout: 5) } # graceful shutdown
```

---

### 17. ✅ Diagnostic Helper Methods (Fixed in v0.2.0)

**Was:** `E11y.enabled_for?`, `E11y.buffer_size`, and `E11y.circuit_breaker_state` did not exist
on the top-level `E11y` module. `buffer_size` was only on `AdaptiveBatcher` / `console.rb`.

**Fix:** All three methods added to the `E11y` module:

```ruby
E11y.enabled_for?(:debug)      # => true/false — is this severity active?
E11y.buffer_size                # => Integer — current debug buffer depth
E11y.circuit_breaker_state      # => :closed/:open/:half_open
```

---

### 18. ✅ `track()` Block Syntax (Fixed in v0.2.0)

**Was:** `track(**payload)` accepted keyword arguments only. No block support. Duration measurement
did not exist.

**Fix:** `track` now accepts an optional block. When a block is given, `duration_ms` is measured
and included in the event payload automatically:

```ruby
Events::OrderProcessing.track(order_id: '123') do
  process_order(order)
end
# → event payload includes duration_ms: 250
```

---

### 19. ✅ `retention` Event DSL (Fixed in v0.2.0)

**Was:** The method was `retention_period`, not `retention`. Calling `retention 7.years` raised
`NoMethodError`.

**Fix:** `alias_method :retention, :retention_period` added to `Event::Base`. Both forms now work:

```ruby
class Events::OrderPaid < E11y::Event::Base
  retention 7.years          # alias (new, short form)
  retention_period 7.years   # original (still works)
end
```

---

### 20. ✅ `metric` Single-Call DSL (Fixed in v0.2.0)

**Was:** No `metric` class method in `Event::Base`. Only the block form was supported.

**Fix:** `metric` class method added to `Event::Base`. Both forms now work:

```ruby
# Single-metric shorthand (new):
metric :counter, name: 'orders.paid.total', tags: [:currency]

# Block form (original, still works):
metrics do
  counter :orders_paid_total, tags: [:currency]
end
```

---

### 21. ✅ `NullAdapter` (Fixed in v0.2.0)

**Was:** `NullAdapter` did not exist.

**Fix:** `E11y::Adapters::NullAdapter` added. It discards all events silently — useful for tests
where you want to disable all output without recording events:

```ruby
E11y.configure do |c|
  c.adapters[:null] = E11y::Adapters::NullAdapter.new
end
```

> **Note:** `adapters` is a Hash. Use `c.adapters[:key] = ...` (not Array assignment).

> **Note on archival:** Archival happens at a **different moment** than event collection. E11y collects events in real time → Loki. Each event carries `retention_until` (ISO8601) in payload. **Archival** (hot → cold) is done by a **separate job** (cron, Loki compaction) — it filters by `retention_until`. Simple, no custom logic.

---

### 22. ✅ `config.register_adapter` Method (Fixed in v0.2.0)

**Was:** No `register_adapter` method on `Configuration`.

**Fix:** `register_adapter(name, instance)` method added to `Configuration`. Both forms are now
equivalent:

```ruby
config.register_adapter :logs, E11y::Adapters::Loki.new(url: ENV['LOKI_URL'])
config.adapters[:logs] = E11y::Adapters::Loki.new(url: ENV['LOKI_URL'])  # same effect
```

---

### 23. ✅ `config.cardinality_protection` Block DSL (Fixed in v0.2.0)

**Was:** `E11y::Configuration` had no `cardinality_protection` method. Settings were only
configurable per-adapter at instantiation.

**Fix:** `cardinality_protection` block DSL added to `Configuration`:

```ruby
config.cardinality_protection do
  max_cardinality 1000
  denylist [:user_id, :order_id, :email]
  overflow_strategy :relabel
end
```

Per-adapter configuration at instantiation still works and takes precedence:

```ruby
E11y::Adapters::Yabeda.new(
  cardinality_limit: 1000,
  forbidden_labels: [:user_id],
  overflow_strategy: :relabel
)
```

---

### 24. ✅ `config.default_adapters` (Fixed in v0.2.0)

**Was:** No `default_adapters=` setter on `Configuration`.

**Fix:** `default_adapters=` setter added to `Configuration`. It updates the `:default` key
in `adapter_mapping`:

```ruby
config.default_adapters = [:loki]
# equivalent to:
config.adapter_mapping[:default] = [:loki]
```

---

### 25. ⚠️ Versioning Middleware — Opt-in (Unchanged)

**Status:** `Middleware::Versioning` exists and works but remains **opt-in** (not in the default
pipeline). Add it manually to normalize event names from `"OrderPaidEvent"` to `"order.paid"`:

```ruby
config.pipeline.use E11y::Middleware::Versioning
```

Without this middleware, event names in adapters are the raw class name (e.g., `"OrderPaidEvent"`).

> Documentation in QUICK-START.md has been updated (v0.2.0) to call this out explicitly and
> explain the consequence of not including Versioning in the pipeline.

---

### 26. ⚠️ DLQ / Circuit Breaker — Known Bugs

**Documented (ADR-013):** Circuit breaker, DLQ with filter, retry with rate limiting.

**Reality:**

> ❌ **BUG-001 — DLQ Filter Signature Mismatch** (`lib/e11y/adapters/base.rb:519`)
> Call site: `@dlq_filter&.should_save?(event_data, error)` — 2 arguments.
> Definition in `DLQ::Filter#should_save?` — 1 argument.
> **Effect:** Runtime `ArgumentError` crash whenever `dlq_filter` is configured. DLQ never saves events.

> ❌ **BUG-002 — RetryRateLimiter Never Called**
> `lib/e11y/reliability/retry_rate_limiter.rb` exists but is not wired into `RetryHandler` or `Adapters::Base`.
> **Effect:** Thundering herd prevention (C06) is fully non-functional.

---

### 27. ✅ `adapters` Hash vs Array — Fixed in Docs (v0.2.0)

**Was:** QUICK-START testing section showed incorrect Array assignment:
```ruby
c.adapters = [E11y::Adapters::NullAdapter.new]
```

**Fix:** QUICK-START.md updated to use correct Hash syntax:
```ruby
c.adapters[:null] = E11y::Adapters::NullAdapter.new
```

`adapters` is a `Hash` in `Configuration`. The incorrect Array form is gone from all examples.

---

### 28. ⚠️ Double-Definition of `PIIFilteringBuilder`

**In `event/base.rb`:** `PIIFilteringBuilder` is defined **twice** — once inside the `class << self` block (line ~637) and once at the `Base` class level (line ~922). Both have identical methods. Not a runtime bug (second reopens first), but confusing dead code that should be cleaned up.

---

## Risk Assessment for Production Adoption

### Safe to Use Today (v0.2.0)
- Core event system (`Event::Base`, `track()`, schemas, block form with `duration_ms`)
- Request-scoped debug buffering
- Loki, Sentry, File, Stdout, InMemory, NullAdapter adapters
- PII filtering — event-level DSL + global `config.pii_filter do` block
- Adaptive sampling (error-spike, load-based, value-based)
- Rails + ActiveJob + Sidekiq instrumentation
- Presets (HighValueEvent, AuditEvent, DebugEvent)
- Basic SLO metrics
- Rate limiting — now in default pipeline (`config.rate_limiting.enabled = true`)
- OTelLogs — all payload attributes now included
- Rails generators (`rails g e11y:install`)
- `E11y.start!` / `E11y.stop!` lifecycle methods
- `config.register_adapter`, `config.slo_tracking = true`, `retention` alias

### Use With Caution
- **Yabeda/Prometheus metrics** — require explicit `E11y::Adapters::Yabeda.new` in `config.adapters`; documented in Quick Start
- **SLO accuracy** — may be off when adaptive sampling is enabled (C11 unresolved, Phase 2.8)
- **Versioning** — opt-in; default event names are CamelCase not dot-notation
- **Per-controller/per-job SLO config** — `config.slo do controller ... end` stores config but enforcement not yet wired

### Do Not Use in Production (Still Broken/Missing)
- **DLQ** — BUG-001 causes crash on any event that triggers DLQ filter (`should_save?` arity mismatch)
- **Retry rate limiting** — BUG-002, thundering herd prevention non-functional
- **`rate_limit` event-level DSL** — `rate_limit 1000, window: 1.second` on event class not implemented
- **Per-pattern rate limiting** — `per_event 'payment.*'` in block DSL stores config but not enforced

---

*Initial audit: 2026-03-12 — branch `feat/integration-testing`.*
*Updated: 2026-03-13 — branch `feat/audit-fixes` — 17 items resolved.*

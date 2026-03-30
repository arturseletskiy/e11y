# E11y - Quick Start Guide

> **TL;DR**: Ruby gem for structured business events with request-scoped debug buffering,
> schema validation, and pluggable adapters (Loki, Sentry, OpenTelemetry, Yabeda, etc.).
>
> **Current version: 0.2.0** — ⚠️ Work in Progress, production validation in progress.

---

## 🚀 Installation

```bash
# Gemfile
gem 'e11y', '~> 0.2'

bundle install
```

Then run the generator to create the initializer and example event:

```bash
rails g e11y:install
```

This creates:
- `config/initializers/e11y.rb` — base configuration with comments
- `app/events/` — directory for event classes (if it doesn't exist)

> **Available generators:**
> - `rails g e11y:install` — initializer + directory scaffold
> - `rails g e11y:grafana_dashboard` — Grafana dashboard JSON (requires Yabeda/Prometheus)
> - `rails g e11y:prometheus_alerts` — Prometheus alerting rules

Or create the initializer manually:

```bash
touch config/initializers/e11y.rb
```

---

## 🎯 Killer Features

### 1. Request-Scoped Debug Buffering

**Problem**: Debug logs in production = noise. Without debug = no context when errors occur.

**Solution**: Debug events are buffered in thread-local storage. On success — discarded.
On error — flushed with full context.

```
GET /api/orders/123
  ├─ [debug] Query: SELECT... (buffered, NOT sent)
  ├─ [debug] Cache miss (buffered, NOT sent)
  ├─ [ERROR] Payment failed ← 5xx raised
  └─> FLUSH: all buffered debug events are sent to the adapter!
```

> **Note:** By default the buffer flushes only on **5xx server errors** (`flush_on_error = true`).
> On 4xx responses and successful requests the buffer is discarded.
>
> Two independent knobs let you customize this — see [Configuration](#-configuration):
> - `flush_on_error = false` — disable the 5xx auto-flush
> - `flush_on_statuses = [403]` — add extra statuses (independent of `flush_on_error`)

**Result**: Debug logs only when needed, zero overhead on the happy path.

### 2. `:success` Pseudo-Severity

A new severity level between `:info` and `:warn` for successful operations.

```ruby
Events::OrderPaid.track(order_id: '123', amount: 99.99, currency: 'USD')
# severity is automatically :success (inferred from class name — "Paid")

# Or explicitly:
Events::SomeEvent.track(order_id: '123', severity: :success)
```

**In Grafana/Kibana:**
```
{severity="success", event_name="OrderPaid"}
```

**Result**: Visibility into successes, not just errors. Easy to build success rate dashboards.

### 3. Schema Validation (dry-schema)

```ruby
class Events::OrderPaid < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float, gt?: 0)
    required(:currency).filled(:string, included_in?: %w[USD EUR GBP])
  end
end

Events::OrderPaid.track(order_id: nil, amount: -10)
# => E11y::ValidationError: Validation failed for OrderPaid: {:order_id=>["must be filled"], ...}
```

### 4. Trace Context (W3C + OTel + Sentry fallback)

Automatic trace_id extraction with fallback chain:

```
1. traceparent header (W3C Trace Context)
2. X-Request-ID header
3. X-Trace-Id header (custom)
4. Generate new UUID
```

**Result**: Correlated events across services with no extra code.

### 5. Built-in SLO Tracking

```ruby
E11y.configure do |config|
  config.rails_instrumentation_enabled = true
  # config.slo_tracking_enabled = true  # enabled by default
end

# Automatically emits metrics:
# e11y_http_requests_total, e11y_http_request_duration_seconds
# e11y_sidekiq_jobs_total, e11y_sidekiq_job_duration_seconds
# e11y_active_jobs_total, e11y_active_job_duration_seconds
```

> ⚠️ **Caveat:** SLO metrics may be imprecise when adaptive sampling is enabled
> (sampling correction is planned for Phase 2.8).

> 🚧 **Roadmap:** Per-controller/per-job SLO configuration, auto-generated Grafana dashboards
> and Prometheus alerts — planned for future releases.

---

## ⚡ Quick Examples

### Basic Event (minimal configuration)

```ruby
# 1. Define the event (app/events/order_paid.rb)
class Events::OrderPaid < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float)
    required(:currency).filled(:string)
  end

  # Optional: Prometheus metrics via Yabeda
  # NOTE: The metrics do...end DSL requires the Yabeda adapter to be registered.
  # Without E11y::Adapters::Yabeda.new in config.adapters, metric definitions are
  # stored but never updated. See the Yabeda / Prometheus Integration section below.
  metrics do
    counter :orders_paid_total, tags: [:currency]
    histogram :order_amount, value: :amount, tags: [:currency],
              buckets: [10, 50, 100, 500, 1000]
  end
end

# 2. Track — only this form, no alternatives
Events::OrderPaid.track(
  order_id: '123',
  amount: 99.99,
  currency: 'USD'
)
```

**90% of events — just a schema, everything else from conventions:**

```ruby
class Events::OrderCreated < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float)
  end
  # severity: :success   (auto, inferred from "Created")
  # adapters: [:logs]    (auto, from severity via adapter_mapping)
  # sample_rate: 0.1     (auto, from severity)
  # retention_period: 30.days (from config.default_retention_period)
end
```

**Explicit configuration at the event-class level:**

```ruby
class Events::PaymentSucceeded < E11y::Event::Base
  schema do
    required(:transaction_id).filled(:string)
    required(:amount).filled(:float)
  end

  severity :success
  sample_rate 1.0            # never sample-out payment events
  retention_period 7.years   # financial records (also: `retention 7.years` is a valid alias)
  adapters :logs, :errors_tracker
end
```

**Inheritance for DRY configuration:**

```ruby
module Events
  class BasePaymentEvent < E11y::Event::Base
    severity :success
    sample_rate 1.0
    retention_period 7.years
    adapters :logs, :errors_tracker
  end
end

class Events::PaymentSucceeded < Events::BasePaymentEvent
  schema do
    required(:transaction_id).filled(:string)
    required(:amount).filled(:float)
  end
  # Inherits ALL configuration from BasePaymentEvent
end
```

**Preset modules:**

```ruby
class Events::PaymentProcessed < E11y::Event::Base
  include E11y::Presets::HighValueEvent
  # → severity :success, sample_rate 1.0, adapters [:logs, :errors_tracker]

  schema do
    required(:transaction_id).filled(:string)
    required(:amount).filled(:float)
  end
end

class Events::UserDeleted < E11y::Event::Base
  include E11y::Presets::AuditEvent
  # → sample_rate 1.0, signing enabled, never rate-limited

  schema do
    required(:user_id).filled(:string)
    required(:deleted_by).filled(:string)
  end
end
```

### Request-Scoped Debug Buffering

```ruby
class OrdersController < ApplicationController
  def create
    # Debug events are buffered — not sent immediately
    Events::ValidationStarted.track(severity: :debug, params: params.keys)
    Events::DatabaseQuery.track(sql: '...', severity: :debug)

    order = Order.create!(order_params)

    # Non-debug events are sent immediately (not buffered)
    Events::OrderCreated.track(order_id: order.id, amount: order.total)

    render json: order
    # ← Successful request: debug buffer is discarded
  rescue => e
    # ← 5xx (or any configured flush status): debug buffer is flushed with error context
    raise
  end
end
```

---

## 🔧 Configuration

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  # === Service identity ===
  config.service_name = 'myapp'
  config.environment  = Rails.env

  # === Adapters (key = name, value = instance) ===
  # adapters is a Hash — use [] assignment or register_adapter (both are equivalent):
  config.adapters[:logs] = E11y::Adapters::Loki.new(
    url: ENV['LOKI_URL'],
    batch_size: 100,
    batch_timeout: 5,
    compress: true
  )
  # Equivalent form:
  # config.register_adapter :logs, E11y::Adapters::Loki.new(url: ENV['LOKI_URL'])

  config.adapters[:errors_tracker] = E11y::Adapters::Sentry.new(
    dsn: ENV['SENTRY_DSN']
  )

  # For Prometheus metrics (requires gem 'yabeda' + 'yabeda-prometheus')
  config.adapters[:metrics] = E11y::Adapters::Yabeda.new(
    cardinality_limit: 1000,
    overflow_strategy: :relabel
  )

  # === Request-scoped buffering ===
  config.ephemeral_buffer_enabled = true
  # flush_on_error (default: true) — flush buffer on any 5xx server error
  # config.ephemeral_buffer_flush_on_error = false  # disable 5xx auto-flush
  # flush_on_statuses (default: []) — extra statuses, independent of flush_on_error
  # config.ephemeral_buffer_flush_on_statuses = [403]       # also flush on 403 Forbidden
  # config.ephemeral_buffer_flush_on_statuses = [401, 403]  # multiple codes

  # === Rails auto-instrumentation (HTTP, ActiveRecord, ActiveJob, Cache) ===
  config.rails_instrumentation_enabled = true

  # === SLO tracking (enabled by default) ===
  # config.slo_tracking_enabled = true  # already true

  # === Rate limiting (now in default pipeline!) ===
  # Rate limiting is wired into the default pipeline in v0.2.0.
  # Enable and configure parameters:
  # config.rate_limiting_enabled         = true
  # config.rate_limiting_global_limit    = 10_000   # events/sec
  # config.rate_limiting_per_event_limit  = 1_000    # events/sec per type
  # config.rate_limiting_global_window    = 1.0      # seconds

  # === Retention ===
  config.default_retention_period = 30.days
end

# Lifecycle methods (v0.2.0):
# E11y.start!                    # start background workers (batching, retry, DLQ)
# at_exit { E11y.stop!(timeout: 5) }  # graceful shutdown
```

### Enforcing Sentry in production

By default, the adapter starts inactive (with a warning to stderr) if `SENTRY_DSN` is
absent — this allows Docker builds and CI pipelines to load the app without secrets.

To make a missing DSN a hard error at boot (recommended for production):

```ruby
config.adapters[:sentry] = E11y::Adapters::Sentry.new(
  dsn: ENV["SENTRY_DSN"],
  required: Rails.env.production?  # raises ArgumentError at boot if DSN missing in prod
)
```

If you see no events in Sentry, check:
1. `SENTRY_DSN` is set in the running environment (not just build-time)
2. Adapter is healthy: `E11y.configuration.adapters[:sentry].healthy?`
3. Boot logs for `[E11y] Sentry adapter: no DSN configured` warning

### Buffer flush — manual trigger

`EphemeralBuffer.flush_on_error` is a public method — you can call it directly in custom
rescue handlers or background jobs:

```ruby
# Custom error handler (e.g. Grape API, custom Rack app)
rescue => e
  E11y::Buffers::EphemeralBuffer.flush_on_error
  raise
end

# Or flush to a specific adapter target (not yet implemented — placeholder)
E11y::Buffers::EphemeralBuffer.flush_on_error(target: :errors_tracker)
```

### Severity → Adapter mapping

Default routing:

```ruby
# error/fatal → [:logs, :errors_tracker]
# all others  → [:logs]

# Override globally:
E11y.configure do |config|
  config.adapter_mapping[:warn] = [:logs, :errors_tracker]
end

# Override per event:
class Events::CriticalEvent < E11y::Event::Base
  adapters :logs, :errors_tracker
end
```

### PII Filtering

**Auto (:rails_filters):** E11y automatically applies `Rails.application.config.filter_parameters`.

```ruby
# config/application.rb
config.filter_parameters += [:password, :email, :ssn]

# These fields become '[FILTERED]' automatically on track
Events::UserRegistered.track(email: 'user@example.com', password: 'secret')
```

**Event-level DSL (:explicit_pii):**

```ruby
class Events::PaymentCreated < E11y::Event::Base
  contains_pii true

  pii_filtering do
    masks   :card_number   # → '[FILTERED]'
    hashes  :user_email    # → SHA256 (preserves searchability)
    partials :phone        # → first/last characters visible
    redacts :ssn           # → removed completely
    allows  :amount        # → no filtering
  end
end
```

**Inheritance:** Use a base class for common rules, child events add or override:

```ruby
class BaseUserEvent < E11y::Event::Base
  contains_pii true
  pii_filtering do
    masks   :password
    hashes  :email
    partials :phone
  end
end

class Events::PaymentCreated < BaseUserEvent
  pii_filtering do
    masks :card_number, :cvv
  end
end
```

### Adaptive Sampling

```ruby
E11y.configure do |config|
  config.pipeline.use E11y::Middleware::Sampling,
    default_sample_rate: 0.1,

    # Error-spike: on error burst → 100% sampling
    error_based_adaptive: true,
    error_spike_config: {
      window: 60,
      absolute_threshold: 100,
      relative_threshold: 3.0,
      spike_duration: 300
    },

    # Load-based: under high load → reduced sampling
    load_based_adaptive: true,
    load_monitor_config: {
      window: 60,
      thresholds: {
        normal:    1_000,
        high:     10_000,
        very_high: 50_000,
        overload: 100_000
      }
    }
end
```

**Value-based sampling at the event level:**

```ruby
class Events::Payment < E11y::Event::Base
  sample_by_value :amount, greater_than: 1000  # large payments — always tracked
  sample_by_value :total,  in_range: 100..500
end
```

---

## 📊 Severity Levels

```ruby
# lib/e11y/event/base.rb
SEVERITIES = %i[debug info success warn error fatal].freeze

# Default sample rates by severity:
SEVERITY_SAMPLE_RATES = {
  error:   1.0,   # always
  fatal:   1.0,   # always
  debug:   0.01,  # 1%
  info:    0.1,   # 10%
  success: 0.1,   # 10%
  warn:    0.1    # 10%
}.freeze
```

**When to use `:success`:**

```ruby
Events::OrderPaid.track(order_id: '123')       # ← :success (explicit)
Events::JobCompleted.track(job_id: '456')       # ← :success (from name "Completed")
Events::UserLoggedIn.track(user_id: '123')      # ← :info   (default)
Events::PaymentFailed.track(reason: 'timeout')  # ← :error  (from name "Failed")
```

**Auto-resolved severity (convention over configuration):**

| Name contains | Severity |
|---|---|
| `Failed`, `Error` | `:error` |
| `Paid`, `Success`, `Completed` | `:success` |
| `Warn`, `Warning` | `:warn` |
| anything else | `:info` |

---

## 🎭 Middleware (configuration)

### Rails / Rack

`E11y::Middleware::Request` is automatically inserted by the Railtie when `ephemeral_buffer_enabled` is true.

### Sidekiq

```ruby
# Automatically inserted by Railtie when Sidekiq is present.
# For manual setup:
Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add E11y::Instruments::Sidekiq::ServerMiddleware
  end
end
```

### Default pipeline order

```
TraceContext → Validation → PIIFilter → AuditSigning → Sampling → RateLimiting → Routing
```

As of v0.2.0, `RateLimiting` is wired into the default pipeline. To activate it, set
`config.rate_limiting_enabled = true` (no manual `.use` call needed).

**Versioning (opt-in):**

`Middleware::Versioning` normalizes event names from CamelCase class names to dot-notation
(e.g., `OrderPaidEvent` → `order.paid`). It is not in the default pipeline; add it explicitly:

```ruby
config.pipeline.use E11y::Middleware::Versioning
```

Without this middleware, event names in adapters are the raw class name (e.g., `"OrderPaidEvent"`).

---

## 🔍 Trace Context Flow

```ruby
# Service A (API)
POST /orders
  trace_id: abc-123  # from X-Trace-ID header
  ├─ Events::OrderValidation.track  # trace_id: abc-123
  ├─ Events::OrderCreated.track     # trace_id: abc-123
  └─ ProcessOrderJob.perform_later(order_id: id, trace_id: 'abc-123')

# Background Job (Sidekiq)
ProcessOrderJob
  trace_id: abc-123  # propagated through middleware
  └─ Events::OrderProcessed.track  # trace_id: abc-123

# Result: all events are correlated by trace_id = full visibility
```

---

## 📈 Yabeda / Prometheus Integration

> **Note:** The `metrics do ... end` DSL requires the Yabeda adapter to be registered.
> Without `E11y::Adapters::Yabeda.new` in `config.adapters`, metric definitions are stored
> but never updated. Add the adapter as shown below before defining event metrics.

```ruby
# Gemfile
gem 'yabeda'
gem 'yabeda-prometheus'

# config/initializers/e11y.rb
E11y.configure do |config|
  config.adapters[:metrics] = E11y::Adapters::Yabeda.new(
    cardinality_limit: 1000,
    forbidden_labels: [:user_id, :order_id],  # additional denylist
    overflow_strategy: :relabel               # :drop, :alert, or :relabel
  )
end

# Event with metrics:
class Events::OrderPaid < E11y::Event::Base
  metrics do
    counter   :orders_paid_total, tags: [:currency]
    histogram :order_amount, value: :amount, tags: [:currency]
  end
end

Events::OrderPaid.track(order_id: '123', amount: 99, currency: 'USD')
# → Yabeda.e11y.orders_paid_total.increment({currency: 'USD'})
# → Yabeda.e11y.order_amount.measure({currency: 'USD'}, 99)
```

**Prometheus endpoint:**

```ruby
# config/routes.rb
mount Yabeda::Prometheus::Exporter => '/metrics'
```


---

## 🧪 Testing

```ruby
# spec/support/e11y_helper.rb
RSpec.configure do |config|
  let(:test_adapter) { E11y::Adapters::InMemory.new }

  config.before(:each) do
    # adapters is a Hash — use [] assignment, not Array assignment
    E11y.configure do |c|
      c.adapters[:test] = test_adapter
      # For a no-op adapter that discards all events (no recording overhead):
      # c.adapters[:null] = E11y::Adapters::NullAdapter.new
    end
  end

  config.after(:each) do
    test_adapter.clear!
  end
end

# spec/controllers/orders_controller_spec.rb
RSpec.describe OrdersController do
  it 'tracks order creation' do
    post :create, params: { order_id: '123', amount: 99.99, currency: 'USD' }

    events = test_adapter.events
    expect(events).to include(
      a_hash_including(
        event_name: 'OrderCreated',
        payload: hash_including(order_id: '123')
      )
    )
  end

  it 'raises on invalid data' do
    expect {
      Events::OrderPaid.track(order_id: nil, amount: -1)
    }.to raise_error(E11y::ValidationError)
  end
end
```

**InMemory Adapter API:**

```ruby
adapter = E11y::Adapters::InMemory.new(max_events: 1000)

adapter.events       # => Array<Hash> — all events
adapter.event_count  # => Integer
adapter.last_event   # => Hash — last event
adapter.clear!       # reset
```

---

## 🔐 Security

### PII Filtering — what works today

**Auto (:rails_filters) — Rails filter_parameters:**

```ruby
# config/application.rb
config.filter_parameters += [:password, :email, :ssn, :credit_card]
# E11y applies this list automatically — no extra config needed
```

**Event-level (:explicit_pii):**

```ruby
class Events::UserRegistered < E11y::Event::Base
  contains_pii true

  pii_filtering do
    masks   :password
    hashes  :email      # SHA256, preserves searchability
    redacts :ssn
    allows  :user_id
  end
end
```

### Rate Limiting — now in default pipeline

As of v0.2.0, `Middleware::RateLimiting` is included in the default pipeline. Activate it by
enabling the config (no extra `.use` call required):

```ruby
E11y.configure do |config|
  config.rate_limiting_enabled         = true
  config.rate_limiting_global_limit     = 10_000  # events/sec
  config.rate_limiting_per_event_limit  = 1_000   # events/sec per type
  config.rate_limiting_global_window    = 1.0     # seconds
end
```

> **Note:** When `config.rate_limiting_enabled = false` (default), the middleware is present in
> the pipeline but passes all events through without limiting. Set `enabled = true` to activate.

> 🚧 **Roadmap:** Per-event and per-pattern rate limiting (e.g. `'user.login.failed'` → 100/min)
> — planned for future releases.

---

## 🎯 Built-in SLO Tracking

**What is tracked automatically** when `config.rails_instrumentation_enabled = true`:

```ruby
# HTTP Metrics (via Rack middleware)
e11y_http_requests_total{
  status="200", method="GET",
  controller="Api::OrdersController", action="show"
}
e11y_http_request_duration_seconds{ ... }  # histogram

# Sidekiq Metrics
e11y_sidekiq_jobs_total{queue="default", class="ProcessOrderJob", status="success"}
e11y_sidekiq_job_duration_seconds{ ... }

# ActiveJob Metrics
e11y_active_jobs_total{queue="mailers", class="EmailJob", status="success"}
e11y_active_job_duration_seconds{ ... }
```

**SLO Calculations (PromQL):**

```promql
# HTTP Availability (30d rolling)
100 * (
  sum(rate(e11y_http_requests_total{status=~"2.."}[30d])) /
  sum(rate(e11y_http_requests_total[30d]))
)

# p95 Latency
histogram_quantile(0.95, rate(e11y_http_request_duration_seconds_bucket[5m]))
```

**⚠️ In-process SLO limitations:**

E11y SLO runs inside the Ruby process and **does not see**:
- Network issues (requests that never reach the app)
- Load balancer failures
- All pods down

Recommended: multi-layer monitoring — E11y SLO + K8s health probes + external synthetic checks.

> 🚧 **Roadmap:** Per-controller/per-job SLO configuration, auto-generated Grafana dashboards
> (`rails g e11y:grafana_dashboard`) and Prometheus alerts (`rails g e11y:prometheus_alerts`)
> — planned for future releases.

---

## 🔄 Migration from Rails.logger

```ruby
# ❌ Before
Rails.logger.info "Order #{order.id} paid #{order.amount} #{order.currency}"
OrderMetrics.increment('orders.paid.total')
OrderMetrics.observe('orders.paid.amount', order.amount)

# ✅ After (1 line instead of 3, + validation + trace context)
Events::OrderPaid.track(
  order_id: order.id,
  amount:   order.amount,
  currency: order.currency
)
```

---

## 🐛 Troubleshooting

### Events not appearing in the adapter?

```ruby
# 1. Is E11y enabled?
E11y.config.enabled  # => true

# 2. Is the adapter registered?
E11y.config.adapters  # => {:logs=>#<Loki...>, ...} — must not be empty

# 3. Is severity routing configured?
E11y.config.adapter_mapping
# => {:error=>[:logs, :errors_tracker], :fatal=>[:logs, :errors_tracker], :default=>[:logs]}

# 4. Is the adapter healthy?
E11y.config.adapters[:logs].healthy?  # => true

# 5. Metrics not updating? Yabeda adapter must be explicitly configured:
E11y.config.adapters[:metrics]  # should be E11y::Adapters::Yabeda

# 6. Diagnostic helpers (v0.2.0):
E11y.enabled_for?(:debug)         # => true/false — is debug severity active?
E11y.buffer_size                   # => Integer — current debug buffer size
E11y.circuit_breaker_state         # => :closed/:open/:half_open
```

### Debug events not flushing on errors?

```ruby
# Is the buffer enabled?
E11y.config.ephemeral_buffer_enabled  # => true

# Is Rails instrumentation enabled?
E11y.config.rails_instrumentation_enabled  # => true

# Is 5xx auto-flush enabled?
E11y.config.ephemeral_buffer_flush_on_error    # => true (default)

# Any extra statuses configured?
E11y.config.ephemeral_buffer_flush_on_statuses # => [] (default) or [403] etc.

# Note: flush_on_error and flush_on_statuses are independent.
# flush_on_error=true  → flush on any 5xx.
# flush_on_statuses=[403] → also flush on 403, regardless of flush_on_error.
```

### High latency?

```ruby
# Possible causes:
# - Loki/Sentry unreachable → circuit breaker will open after 5 errors
# - PII filtering: complex regexes → simplify
# - batch_size too large → reduce or lower batch_timeout

# Check adapter health:
E11y.config.adapters[:logs].healthy?
```

---

## 📚 Full Documentation

- **ADRs**: `docs/architecture/ADR-*.md` — architecture decision records
- **GitHub**: https://github.com/arturseletskiy/e11y

---

## ✅ Getting Started Checklist

- [ ] Add `gem 'e11y', '~> 0.2'` to Gemfile, run `bundle install`
- [ ] Run `rails g e11y:install` (or create `config/initializers/e11y.rb` manually)
- [ ] Configure adapters: `config.adapters[:logs] = E11y::Adapters::Loki.new(...)`
- [ ] For metrics: add `gem 'yabeda'`, set `config.adapters[:metrics] = E11y::Adapters::Yabeda.new`
- [ ] Enable request buffering: `config.ephemeral_buffer_enabled = true`
- [ ] Enable Rails instrumentation: `config.rails_instrumentation_enabled = true`
- [ ] Define first event class in `app/events/`
- [ ] Use `EventName.track(...)` in a controller or service
- [ ] Write a test using `E11y::Adapters::InMemory`
- [ ] Check `/metrics` endpoint (if Yabeda is configured)
- [ ] Test request buffering: raise an exception → confirm debug events appeared
- [ ] Configure PII filtering for events that handle personal data
- [ ] Deploy to staging, monitor performance

---

## ✅ What's New in v0.2.0

| Feature | Notes |
|---------|-------|
| `rails g e11y:install` | Generator available: creates initializer + `app/events/` |
| `E11y.start!` / `E11y.stop!` | Lifecycle methods for graceful startup/shutdown |
| Rate Limiting in default pipeline | `config.rate_limiting_enabled = true` now works |
| Event name normalization (`Middleware::Versioning`) | Now in default pipeline |
| OTelLogs payload attributes | All payload attributes now included in OTel log records |
| `config.slo_tracking = true` | Boolean coercion now accepted |
| `retention` / `retention_period` | Both work as aliases on event class |
| `add_slo_controller` / `add_slo_job` | Helpers on `E11y::Configuration` (stored config; see UC-004) |
| `config.rate_limiting do` | Rate limiting block DSL |
| `config.cardinality_protection do` | Cardinality DSL block |
| `config.register_adapter` | Alias for `config.adapters[name] =` |
| `NullAdapter` | `E11y::Adapters::NullAdapter.new` for no-op testing |
| `track() { }` block form | Block form measures duration automatically |
| `E11y.enabled_for?` / `E11y.buffer_size` | Diagnostic helpers |
| `metric :counter` single-call DSL | Single metric definition without `metrics do` block |
| Full block DSLs | All config sections support `do...end` block form |

## 🚧 Roadmap (still not implemented)

The following features are **documented in ADRs** but not yet implemented:

| Feature | ADR/UC |
|---------|--------|
| `rails g e11y:grafana_dashboard` | ADR-003 |
| `rails g e11y:prometheus_alerts` | ADR-003 |
| Wire `add_slo_controller` / `add_slo_job` into HTTP/job `Tracker` dimensions | UC-004, ADR-003 |
| Per-event rate limiting (`rate_limit` DSL on event class) | UC-011 |
| Tiered storage (archival) | UC-019 — filter by `retention_until` |
| Cost Tracking / Budget Enforcement | ADR-009, UC-015 |
| Outgoing HTTP trace propagation (Faraday/Net::HTTP) | UC-009 |
| Event Registry (`E11y::Registry`) | UC-022 |
| Key Rotation for AuditEncrypted | ADR-006 |

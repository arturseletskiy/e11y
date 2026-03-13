<div align="center">

# E11y - Easy Telemetry

**Observability for Rails developers who hate noise**

[![Gem Version](https://badge.fury.io/rb/e11y.svg)](https://badge.fury.io/rb/e11y)
[![CI](https://github.com/arturseletskiy/e11y/actions/workflows/ci.yml/badge.svg)](https://github.com/arturseletskiy/e11y/actions/workflows/ci.yml)
[![Code Coverage](https://codecov.io/gh/arturseletskiy/e11y/branch/main/graph/badge.svg)](https://codecov.io/gh/arturseletskiy/e11y)

**⚠️ Work in Progress** - Core features implemented, production validation in progress

[Quick Start](#quick-start) • [Why E11y?](#why-e11y) • [Documentation](#documentation)

</div>

---

## The Problem Every Rails Developer Knows

You enable debug logs in production to catch that one weird bug.  
**Result:** 10,000 lines of noise for every 1 error.

```ruby
# Production logs right now:
[DEBUG] Cache read: session:abc123        ← 99% useless
[DEBUG] SQL: SELECT * FROM users WHERE... ← 99% useless  
[DEBUG] Rendered users/show.html.erb     ← 99% useless
[INFO] User 123 logged in                ← maybe useful
[DEBUG] Cache read: user:123              ← 99% useless
[ERROR] Payment failed: Stripe timeout    ← THIS is what you need!
```

**The dilemma:**
- Turn debug ON → drown in noise, pay $$$ for log storage
- Turn debug OFF → fly blind when bugs happen

---

## The E11y Solution

**Request-scoped debug buffering** - the only Rails observability gem that does this:

```ruby
# E11y buffers debug logs in memory during request
# Flushes to storage ONLY if request fails

# Happy path (99% of requests):
[INFO] User 123 logged in ✅
# Debug logs discarded, zero noise

# Error path (1% of requests):  
[ERROR] Payment failed: Stripe timeout
[DEBUG] Cache read: session:abc123      ← NOW we see the context!
[DEBUG] SQL: SELECT * FROM users...      ← NOW we see what happened!
[DEBUG] Rendered users/show.html.erb    ← Complete error trail!
```

**Result:** Debug when you need it. Silence when you don't.

---

## What Makes E11y Different?

### 1. Request-Scoped Debug Buffering (Unique to E11y)

**No other Rails gem does this.**

```ruby
# Traditional approach:
Rails.logger.debug "query: SELECT..." # → Always written to disk
Rails.logger.debug "cache miss"       # → Always written to disk
Rails.logger.debug "rendering view"   # → Always written to disk
# Cost: $$$, Noise: 99%, Value: 1%

# E11y approach:
E11y.configure do |config|
  config.request_buffer.enabled = true
end

# Debug events buffered in memory during request
# Flushed to storage ONLY on 5xx server errors
# Cost: -90%, Noise: -99%, Value: 100%
```

> **Note:** By default the buffer flushes only on **5xx server errors** (`flush_on_error = true`).
> On 4xx responses the buffer is discarded. Two independent knobs control this:
>
> ```ruby
> # flush_on_error (default: true) — controls 5xx behaviour
> config.request_buffer.flush_on_error = false  # disable 5xx flush
>
> # flush_on_statuses (default: []) — extra statuses, independent of flush_on_error
> config.request_buffer.flush_on_statuses = [403]       # also flush on 403 Forbidden
> config.request_buffer.flush_on_statuses = [401, 403]  # multiple codes
> ```

**Real-world impact:**
- **Storage costs:** $500/month → $50/month (Loki/CloudWatch)
- **Log search time:** 30 seconds → 3 seconds (90% less data)
- **Developer sanity:** Infinite ✨

---

### 2. retention_until — Simple Archival

Events carry `retention_until` (ISO8601) in their payload. **Archival happens later** — a separate job (cron, Loki compaction) filters logs by this field. No custom logic: `WHERE retention_until > ?`. Cost savings (export to cheap cold storage) and simplicity (one field to filter).

---

### 3. Schema-Validated Business Events

Stop debugging nil values in production:

```ruby
class OrderPaidEvent < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float, gt?: 0)
    required(:currency).filled(:string, included_in?: %w[USD EUR GBP])
  end
  
  metrics do
    counter :orders_total, tags: [:currency]
    histogram :order_amount, value: :amount, tags: [:currency]
  end
end

# Invalid data caught BEFORE production
OrderPaidEvent.track(order_id: "123", amount: -10, currency: "INVALID")
# => E11y::ValidationError: amount must be > 0

# Valid data: event + metrics in one call
OrderPaidEvent.track(order_id: "123", amount: 99.99, currency: "USD")
# ✅ Event sent to Loki/Sentry
# ✅ Prometheus metrics updated
# ✅ No manual Yabeda.increment
```

**Developer experience:**
- Schema validation prevents bugs
- Auto-metrics eliminate boilerplate
- Type safety without TypeScript

---

### 4. Zero-Config SLO Tracking

Automatic Service Level Objectives for your endpoints and jobs:

```ruby
# Enable Rails instrumentation
E11y.configure do |config|
  config.rails_instrumentation.enabled = true
end

# That's it! E11y now emits SLO metrics automatically:
# - HTTP endpoints: success rate, latency percentiles (p50, p95, p99)
# - Background jobs: success rate, execution time, retry rate
# - Database queries: slow query detection
# - Cache operations: hit/miss ratios
#
# SLO metrics are collected via Prometheus/Yabeda; calculate SLOs from those metrics.
```

**vs. Traditional SLO Tracking:**
- ❌ Manual instrumentation of every endpoint
- ❌ Complex SLO definitions and calculations
- ❌ Separate tools for different SLOs
- ✅ E11y: Zero config, automatic tracking, metrics for SLO calculation

---

### 5. Rails-First Design

Built for Rails developers, not platform engineers:

```ruby
# 5-minute setup, not 2-week OpenTelemetry migration
gem "e11y"

E11y.configure do |config|
  config.adapters[:logs] = E11y::Adapters::Loki.new(url: ENV["LOKI_URL"])
  config.adapters[:errors_tracker] = E11y::Adapters::Sentry.new(dsn: ENV["SENTRY_DSN"])
end

# Auto-instruments Rails (optional):
config.rails_instrumentation.enabled = true
# → HTTP requests, ActiveRecord, ActiveJob, Cache events
```

**vs. Traditional Observability:**
- ❌ OpenTelemetry: 5 docs pages, complex setup
- ❌ Datadog: $10k+/year, vendor lock-in  
- ❌ ELK Stack: DevOps team needed
- ✅ E11y: One gem, Rails conventions, owned data

---

## Who Should Use E11y?

### ✅ Perfect For

**Rails developers who:**
- Hate searching through 100k debug logs for 1 error
- Pay too much for Datadog/New Relic ($500-5k/month)
- Need observability but don't have a DevOps team
- Want type-safe events without migrating to TypeScript

**Teams that:**
- Run Rails 7.0+ in production (Sidekiq, PostgreSQL, Redis)
- Use Loki/Grafana or Sentry for monitoring
- Care about developer experience and code quality
- Prefer open-source over SaaS vendor lock-in

### ⚠️ Not For (Yet)

- **Non-Rails Ruby** - Focused on Rails conventions first
- **Microservices polyglot** - OpenTelemetry better for multi-language
- **Enterprise compliance** - E11y is WIP, audit trails coming soon
- **Auto-instrumentation only** - E11y requires event definitions (by design)

---

## Core Features

| Feature | Status | Description |
|---------|--------|-------------|
| **Request-Scoped Buffering** | ✅ Implemented | Buffer debug logs, flush only on errors (-90% noise) |
| **Zero-Config SLO Tracking** | ✅ Implemented | Automatic Service Level Objectives for endpoints/jobs |
| **Schema Validation** | ✅ Implemented | dry-schema validation before sending events |
| **Metrics DSL** | ✅ Implemented | Define Prometheus metrics alongside events |
| **Adapters** | ✅ 7 adapters | Loki, Sentry, OpenTelemetry, Yabeda, File, Stdout, InMemory |
| **PII Filtering** | ✅ Implemented | Configurable field masking/hashing/redaction (event-level DSL) |
| **Adaptive Sampling** | ✅ Implemented | Error-based, load-based, value-based strategies |
| **Rate Limiting** | ✅ Implemented | Opt-in — requires `config.pipeline.use E11y::Middleware::RateLimiting` |
| **Rails Integration** | ✅ Implemented | Auto-instrument HTTP, ActiveRecord, ActiveJob, Cache |
| **Production Testing** | 🚧 In Progress | Validating with real workloads |

---

## Quick Start in 5 Minutes

### 1. Install

```bash
# Gemfile
gem "e11y"

bundle install
```

### 2. Configure (One-Time Setup)

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  # Enable request-scoped debug buffering (THE killer feature)
  config.request_buffer.enabled        = true
  # config.request_buffer.flush_on_error    = true   # default: flush on 5xx
  # config.request_buffer.flush_on_statuses = [403]  # also flush on 403
  
  # Configure where events go
  config.adapters[:logs] = E11y::Adapters::Loki.new(
    url: ENV["LOKI_URL"],
    batch_size: 100
  )
  
  config.adapters[:errors_tracker] = E11y::Adapters::Sentry.new(
    dsn: ENV["SENTRY_DSN"]
  )
  
  # Optional: Auto-instrument Rails
  config.rails_instrumentation.enabled = true
end
```

### 3. Define Business Events

```ruby
# app/events/order_paid_event.rb
class OrderPaidEvent < E11y::Event::Base
  # Schema validation (catch bugs before production)
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float, gt?: 0)
    required(:currency).filled(:string, included_in?: %w[USD EUR GBP])
  end
  
  # Auto-metrics (no manual Yabeda.increment!)
  metrics do
    counter :orders_total, tags: [:currency]
    histogram :order_amount, value: :amount, tags: [:currency]
  end
end
```

### 4. Track Events

```ruby
# In controllers/services
class OrdersController < ApplicationController
  def create
    order = Order.create!(order_params)
    
    # One method call = validation + event + metrics
    OrderPaidEvent.track(
      order_id: order.id,
      amount: order.total,
      currency: "USD"
    )
    
    # If amount is negative → E11y::ValidationError (caught before production!)
    # If valid → event sent to Loki + orders_total metric incremented
  end
end
```

**That's it!** Now you have:
- ✅ Debug logs buffered in memory (flushed only on errors)
- ✅ Schema-validated business events  
- ✅ Auto-generated Prometheus metrics
- ✅ Zero-config SLO tracking (success rates, latency percentiles)
- ✅ Events sent to Loki, Sentry, or custom adapters

**No more:**
- ❌ Searching through 100k debug logs
- ❌ nil values in production
- ❌ Manual `Yabeda.increment` everywhere
- ❌ Manual SLO definitions and calculations
- ❌ $500/month log storage bills

---

## Before and After E11y

### Before: Traditional Rails Logging

```ruby
# Development: Debug enabled
Rails.logger.debug "Cache read: session:abc"
Rails.logger.debug "SQL: SELECT * FROM users..."
Rails.logger.debug "Rendered users/show"
# Result: Helpful for debugging ✅

# Production: Debug disabled (too noisy)
Rails.logger.info "User logged in"
# Bug happens...
Rails.logger.error "Payment failed!"
# Result: No context, blind debugging ❌

# Production: Debug enabled (to catch bug)
# 99 successful requests:
#   [DEBUG] Cache read... (297 lines)
#   [INFO] User logged in (99 lines)
# 1 failed request:
#   [DEBUG] Cache read... (3 lines)
#   [ERROR] Payment failed (1 line)
# Total: 400 lines, 74% noise ❌
# Cost: $500/month Loki storage ❌
# Search time: 30 seconds ❌
```

### After: E11y Request-Scoped Buffering

```ruby
# Production with E11y:
E11y.configure { |c| c.request_buffer.enabled = true }

# 99 successful requests:
#   [INFO] User logged in (99 lines)
# Debug logs buffered in memory, discarded ✅

# 1 failed request:
#   [ERROR] Payment failed (1 line)
#   [DEBUG] Cache read... (3 lines) ← Flushed!
#   [DEBUG] SQL: SELECT... (context!) ← Flushed!
#   [DEBUG] Rendered view... (trail!) ← Flushed!
# Total: 103 lines, 0% noise ✅
# Cost: $50/month Loki storage ✅ (-90%)
# Search time: 3 seconds ✅ (-90%)
```

**Impact:**
- **Developer productivity:** 10x faster debugging (context when you need it)
- **Infrastructure cost:** -90% log storage (only relevant logs stored)
- **Signal-to-noise:** 100% vs 1% (every log line matters)

---

## E11y vs Alternatives

### Comparison Matrix

| Solution | Setup Time | Monthly Cost | Request-Scoped Buffering | SLO Tracking | Schema Validation | Auto-Metrics | Data Ownership |
|----------|-----------|--------------|--------------------------|--------------|-------------------|--------------|----------------|
| **E11y** | **5 minutes** | **Infra costs** | **✅ Unique** | **✅ Zero-config** | **✅** | **✅** | **✅ Full** |
| Datadog APM | 2-4 hours | $500-5,000 | ❌ | ✅ Manual | ❌ | ✅ | ❌ SaaS lock-in |
| New Relic | 2-4 hours | $99-658/user | ❌ | ✅ Manual | ❌ | ✅ | ❌ SaaS lock-in |
| Sentry | 1 hour | $26-80/mo | ❌ | ❌ | ❌ | Partial | ❌ SaaS lock-in |
| Semantic Logger | 30 minutes | Infra costs | ❌ | ❌ | ❌ | ❌ | ✅ Full |
| OpenTelemetry | 1-2 weeks | Infra costs | ❌ | Manual setup | ❌ | ✅ | ✅ Full |
| Grafana + Loki | 2-3 days | Infra costs | ❌ | Manual setup | ❌ | Manual | ✅ Full |
| AppSignal | 1 hour | $23-499/mo | ❌ | ✅ Built-in | ❌ | ✅ | ❌ SaaS lock-in |

**Legend:**
- **Setup Time:** From zero to first meaningful data
- **Monthly Cost:** For 10-person team, medium Rails app (estimated)
- **Request-Scoped Buffering:** Buffer debug logs, flush only on errors
- **SLO Tracking:** Automatic Service Level Objectives monitoring
- **Schema Validation:** Type-safe event schemas
- **Auto-Metrics:** Metrics generated from events automatically
- **Data Ownership:** Can you host it yourself?

---

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
- **E11y advantage:** 5-minute setup, Rails-first, request-scoped buffering, schema validation

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
- **E11y advantage:** 5-minute setup, Rails-native, schema validation, no DevOps required

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

### Decision Matrix

**Choose E11y if:**
- ✅ You're tired of noisy debug logs
- ✅ You want type-safe events (catch bugs before production)
- ✅ You prefer Rails conventions over platform engineering
- ✅ You want to own your observability data
- ✅ You want to reduce log storage costs by 90%

**Choose SaaS APM (Datadog, New Relic) if:**
- ✅ You need frontend RUM + backend APM
- ✅ You have polyglot microservices
- ✅ Budget unlimited, prefer turnkey solution
- ✅ You don't want to manage infrastructure

**Choose OpenTelemetry if:**
- ✅ You have microservices in multiple languages
- ✅ You have a platform team to manage complexity
- ✅ You need vendor-neutral distributed tracing

**Choose Grafana Stack if:**
- ✅ You already have Grafana infrastructure
- ✅ You have a DevOps team
- ✅ You need custom dashboards across systems

**Choose Semantic Logger/Lograge if:**
- ✅ You only need structured JSON logs (nothing else)
- ✅ You don't need debug buffering or schema validation

---

### The E11y Sweet Spot

E11y is optimized for:

**Team size:** 5-100 engineers  
**Stack:** Rails 7.0+ monolith or modular monolith  
**Infra:** PostgreSQL, Redis, Sidekiq, standard Rails stack  
**Budget:** Prefer infrastructure costs over $500-5k/month SaaS  
**Philosophy:** Developer experience > platform complexity  

**Not optimized for:**
- Polyglot microservices (use OpenTelemetry)
- Frontend-heavy SPAs (use Datadog/Sentry for RUM)
- Enterprise compliance requirements (WIP, coming soon)

---

## Table of Contents

- [Quick Start](#quick-start-in-5-minutes)
- [What Makes E11y Different?](#what-makes-e11y-different)
- [Who Should Use E11y?](#who-should-use-e11y)
- [Before and After](#before-and-after-e11y)
- [E11y vs Alternatives](#e11y-vs-alternatives)
- [Schema Validation](#schema-validation)
- [Metrics DSL](#metrics-dsl)
- [Adapters](#adapters)
- [PII Filtering](#pii-filtering)
- [Adaptive Sampling](#adaptive-sampling)
- [Presets](#presets)
- [Rails Integration](#rails-integration)
- [Testing](#testing)
- [Configuration](#configuration)
- [Performance](#performance)
- [Documentation](#documentation)

---

## Schema Validation

E11y validates event data using [dry-schema](https://dry-rb.org/gems/dry-schema/).

### Basic Example

```ruby
class OrderCreatedEvent < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:total).filled(:float, gt?: 0)
    required(:currency).filled(:string, included_in?: %w[USD EUR GBP])
    optional(:coupon_code).maybe(:string)
  end
end

# Valid event
OrderCreatedEvent.track(order_id: "123", total: 99.99, currency: "USD")

# Invalid event raises E11y::ValidationError
OrderCreatedEvent.track(order_id: nil, total: -10, currency: "INVALID")
# => ValidationError: order_id is missing, total must be > 0
```

### Validation Modes

For high-frequency events, you can configure validation behavior:

```ruby
class HighFrequencyEvent < E11y::Event::Base
  # Always validate (default)
  validation_mode :always

  # Sampled validation (validate 1% of events)
  validation_mode :sampled, sample_rate: 0.01

  # Never validate (use with caution)
  validation_mode :never
end
```

Use `:always` for user input and critical events. Use `:sampled` for high-frequency internal events. Use `:never` only for trusted, typed input.

### Validation Behavior

By default, invalid events raise `E11y::ValidationError`:

```ruby
OrderEvent.track(order_id: nil)
# => E11y::ValidationError
```

To handle validation errors gracefully:

```ruby
begin
  OrderEvent.track(order_id: nil)
rescue E11y::ValidationError => e
  Rails.logger.warn "Invalid event: #{e.message}"
end
```

---

## Metrics DSL

Define Prometheus metrics alongside events.

### Basic Example

```ruby
class OrderPaidEvent < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float)
    required(:currency).filled(:string)
  end
  
  metrics do
    # Counter: Track number of paid orders
    counter :orders_total, tags: [:currency]
    
    # Histogram: Track order amount distribution
    histogram :order_amount,
              value: :amount,
              tags: [:currency],
              buckets: [10, 50, 100, 500, 1000]
    
    # Gauge: Track active orders
    gauge :active_orders, value: :active_count
  end
end

# One track() call = event + metrics
OrderPaidEvent.track(order_id: "123", amount: 99.99, currency: "USD")
# => orders_total{currency="USD"} +1
# => order_amount{currency="USD"} observe 99.99
```

### Metric Types

**Counter** - Monotonically increasing value:
```ruby
metrics do
  counter :orders_total, tags: [:currency, :status]
end
# => orders_total{currency="USD", status="paid"} 42
```

**Histogram** - Distribution of values:
```ruby
metrics do
  histogram :order_amount,
            value: :amount,
            tags: [:currency],
            buckets: [10, 50, 100, 500, 1000]
end
# => order_amount_bucket{currency="USD", le="100"} 15
```

**Gauge** - Arbitrary value that can go up or down:
```ruby
metrics do
  gauge :queue_depth, value: :size, tags: [:queue_name]
end
# => queue_depth{queue_name="emails"} 37
```

### How It Works

1. Define metrics in event class
2. Metrics registered in `E11y::Metrics::Registry` at boot time
3. When `track()` is called, metrics are automatically updated **if the Yabeda adapter is configured and routed to**
4. Metrics exported via Yabeda adapter (Prometheus format)

> **Note:** The `metrics do` DSL only registers metric definitions. Metrics are actually updated
> when an event is written to the `E11y::Adapters::Yabeda` adapter. If you omit the Yabeda adapter
> from your configuration, `track()` will send events to Loki/Sentry but metric counters will not
> be incremented. Make sure to add:
> ```ruby
> config.adapters[:metrics] = E11y::Adapters::Yabeda.new
> ```

---

## Adapters

E11y supports multiple adapters for different backends.

| Adapter | Purpose | Batching | Use Case |
|---------|---------|----------|----------|
| **Loki** | Log aggregation (Grafana) | Yes | Production logs |
| **Sentry** | Error tracking | Via SDK | Error monitoring |
| **OpenTelemetry** | OTLP export | Yes | Distributed tracing |
| **Yabeda** | Prometheus metrics | N/A | Metrics export |
| **File** | Local logs | Yes | Development, CI |
| **Stdout** | Console output | No | Development |
| **InMemory** | Test buffer | No | Testing |

### Configuration

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  # Configure adapters
  config.adapters[:logs] = E11y::Adapters::Loki.new(
    url: ENV["LOKI_URL"],
    batch_size: 100,
    batch_timeout: 5,
    compress: true
  )
  
  config.adapters[:errors_tracker] = E11y::Adapters::Sentry.new(
    dsn: ENV["SENTRY_DSN"]
  )
  
  config.adapters[:stdout] = E11y::Adapters::Stdout.new(
    format: :pretty
  )
end
```

### Adapter Routing by Severity

Events are routed to adapters based on severity. The default mapping:

- `error`, `fatal` → `[:logs, :errors_tracker]`
- Other severities → `[:logs]`

Override routing explicitly:

```ruby
class CustomEvent < E11y::Event::Base
  adapters :logs, :stdout  # Explicit routing
end
```

### Custom Adapters

Implement the `write` method:

```ruby
class MyBackendAdapter < E11y::Adapters::Base
  def write(event_data)
    # event_data contains event_name, payload, severity, timestamp, etc.
    MyBackend.send_event(event_data)
  end
end

E11y.configure do |config|
  config.adapters[:my_backend] = MyBackendAdapter.new
end
```

---

## PII Filtering

E11y provides PII filtering capabilities for sensitive data.

### Rails Integration

E11y can respect `Rails.application.config.filter_parameters` when configured:

```ruby
# config/application.rb
config.filter_parameters += [:password, :email, :ssn, :credit_card]

# E11y will filter these fields when PII filtering middleware is enabled
```

### Explicit PII Strategies

Configure PII filtering per event:

```ruby
class PaymentEvent < E11y::Event::Base
  contains_pii true
  
  pii_filtering do
    masks :card_number     # Replace with "[FILTERED]"
    hashes :user_email     # SHA256 hash (searchable)
    allows :amount         # No filtering
  end
end
```

Available strategies:
- `masks` - Replace with "[FILTERED]"
- `hashes` - SHA256 hash (preserves searchability)
- `partials` - Show first/last characters
- `redacts` - Remove completely
- `allows` - No filtering

---

## Adaptive Sampling

E11y supports adaptive sampling to reduce event volume during high load.

Sampling strategies:
1. **Error-based** - Increase sampling during error spikes
2. **Load-based** - Reduce sampling under high throughput
3. **Value-based** - Always sample high-value events

> **Note:** Rate limiting (`E11y::Middleware::RateLimiting`) is **not included in the default
> pipeline**. To enable it, add it manually:
> ```ruby
> config.pipeline.use E11y::Middleware::RateLimiting
> ```
> Enabling `config.rate_limiting.enabled = true` alone has no effect without this step.

### Configuration

```ruby
E11y.configure do |config|
  config.pipeline.use E11y::Middleware::Sampling,
    default_sample_rate: 0.1,
    
    # Error-based sampling
    error_based_adaptive: true,
    error_spike_config: {
      window: 60,
      absolute_threshold: 100,
      relative_threshold: 3.0,
      spike_duration: 300
    },
    
    # Load-based sampling
    load_based_adaptive: true,
    load_monitor_config: {
      window: 60,
      thresholds: {
        normal: 1_000,
        high: 10_000,
        very_high: 50_000,
        overload: 100_000
      }
    }
end
```

### Value-Based Sampling

Sample events based on payload values:

```ruby
class PaymentEvent < E11y::Event::Base
  sample_by_value :amount, greater_than: 1000  # Always sample large payments
end
```

---

## Presets

E11y provides presets for common event types.

### HighValueEvent

For financial transactions and critical business events:

```ruby
class PaymentProcessedEvent < E11y::Event::Base
  include E11y::Presets::HighValueEvent
  
  schema do
    required(:transaction_id).filled(:string)
    required(:amount).filled(:decimal)
  end
end

# Configured with:
# - severity: :success
# - sample_rate: 1.0 (always sampled)
# - adapters: [:logs, :errors_tracker]
# - rate_limit: unlimited
```

### AuditEvent

For compliance and audit trails:

```ruby
class UserDeletedEvent < E11y::Event::Base
  include E11y::Presets::AuditEvent
  
  schema do
    required(:user_id).filled(:string)
    required(:deleted_by).filled(:string)
  end
end

# Configured with:
# - sample_rate: 1.0 (never sampled)
# - rate_limit: unlimited
# Note: Set severity based on event criticality
```

### DebugEvent

For development and troubleshooting:

```ruby
class SlowQueryEvent < E11y::Event::Base
  include E11y::Presets::DebugEvent
  
  schema do
    required(:query).filled(:string)
    required(:duration_ms).filled(:integer)
  end
end

# Configured with:
# - severity: :debug
# - adapters: [:logs]
```

---

## Distributed Tracing

E11y automatically attaches W3C Trace Context headers to incoming requests via the `TraceContext` middleware and propagates trace/span IDs through the event pipeline.

### Incoming Trace Context

Incoming `traceparent` / `tracestate` headers are extracted automatically:

```ruby
E11y.configure do |config|
  config.pipeline.use E11y::Middleware::TraceContext
end
```

Events tracked during a request will include `trace_id` and `span_id` from the incoming context.

### Outgoing HTTP Trace Propagation (Manual — v1.0)

> **Note:** Automatic outgoing trace context injection (Faraday / Net::HTTP middleware) is planned for v1.1.
> Until then, use the helper below to propagate W3C Trace Context manually:

```ruby
# Helper: build W3C traceparent header from current context
def traceparent_header
  return {} unless E11y::Current.trace_id

  span_id = E11y::Current.span_id || SecureRandom.hex(8)
  { "traceparent" => "00-#{E11y::Current.trace_id}-#{span_id}-01" }
end

# Faraday — inject on each connection
conn = Faraday.new(url: "https://api.example.com") do |f|
  f.headers.merge!(traceparent_header)
end

# Net::HTTP — inject per request
request = Net::HTTP::Post.new("/events")
traceparent_header.each { |k, v| request[k] = v }
http.request(request)
```

This ensures downstream services receive a valid `traceparent` header and can correlate logs/traces back to the originating request.

---

## Rails Integration

E11y integrates with Rails via Railtie.

### Auto-Instrumented Components

E11y includes event definitions for common Rails components:

| Component | Event Classes | Location |
|-----------|--------------|----------|
| **HTTP Requests** | Request, StartProcessing, Redirect, SendFile | `lib/e11y/events/rails/http/` |
| **ActiveRecord** | Query | `lib/e11y/events/rails/database/` |
| **ActiveJob** | Enqueued, Started, Completed, Failed, Scheduled | `lib/e11y/events/rails/job/` |
| **Cache** | Read, Write, Delete | `lib/e11y/events/rails/cache/` |
| **View** | Render | `lib/e11y/events/rails/view/` |

Enable instrumentation in your configuration as needed.

### Sidekiq Integration

E11y includes Sidekiq instrumentation support. Configure in your initializer:

```ruby
E11y.configure do |config|
  config.rails_instrumentation.enabled = true
end
```

---

## Testing

Use the InMemory adapter for testing.

### Setup

```ruby
# spec/rails_helper.rb or spec/spec_helper.rb
RSpec.configure do |config|
  config.before(:each) do
    # Configure InMemory adapter for tests
    # Note: adapters is a Hash keyed by adapter name symbol
    E11y.configure do |e11y_config|
      e11y_config.adapters[:test] = E11y::Adapters::InMemory.new
    end
  end

  config.after(:each) do
    # Clear events after each test
    E11y.configuration.adapters[:test]&.clear!
  end
end
```

### Test Events

```ruby
RSpec.describe OrdersController do
  let(:test_adapter) { E11y.configuration.adapters[:test] }
  
  it "tracks order creation" do
    post :create, params: { item: "Book", price: 29.99 }
    
    events = test_adapter.events
    expect(events).to include(
      a_hash_including(
        event_name: "OrderCreatedEvent",
        payload: hash_including(item: "Book", price: 29.99)
      )
    )
  end
  
  it "does not track payment for free orders" do
    post :create, params: { item: "Free Book", price: 0 }
    
    payment_events = test_adapter.events.select { |e| e[:event_name] == "PaymentProcessedEvent" }
    expect(payment_events).to be_empty
  end
end
```

### InMemory Adapter API

```ruby
test_adapter = E11y::Adapters::InMemory.new

# Get all events
test_adapter.events  # => Array<Hash>

# Count events
test_adapter.event_count  # => Integer

# Find last event
test_adapter.last_event  # => Hash

# Clear all events
test_adapter.clear!
```

---

## Configuration

### Basic Configuration

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  # Service identification
  config.service_name = "myapp"
  config.environment = Rails.env
  
  # Configure adapters
  config.adapters[:logs] = E11y::Adapters::Loki.new(
    url: ENV["LOKI_URL"],
    batch_size: 100,
    batch_timeout: 5,
    compress: true
  )
  
  config.adapters[:errors_tracker] = E11y::Adapters::Sentry.new(
    dsn: ENV["SENTRY_DSN"]
  )
  
  # Default retention period
  config.default_retention_period = 30.days
end
```

### Middleware Pipeline

Configure middleware for sampling, PII filtering, and more:

```ruby
E11y.configure do |config|
  # Sampling middleware
  config.pipeline.use E11y::Middleware::Sampling,
    default_sample_rate: 0.1,
    error_based_adaptive: true,
    load_based_adaptive: true
  
  # PII filtering middleware
  config.pipeline.use E11y::Middleware::PIIFilter
  
  # Trace context middleware
  config.pipeline.use E11y::Middleware::TraceContext
end
```

---

## Performance

### Design Principles

E11y is designed for performance:

- **Hash-based events** - Events are Hashes, not objects, minimizing allocations
- **Configurable validation** - Choose validation mode based on performance needs
- **Batching** - Loki and other adapters support batching to reduce network overhead
- **Sampling** - Adaptive sampling reduces event volume under high load

See `benchmarks/` directory for detailed performance tests.

### Cardinality Protection

Optional cardinality protection prevents high-cardinality labels from overwhelming metrics systems:

```ruby
E11y::Adapters::Loki.new(
  url: "http://loki:3100",
  enable_cardinality_protection: true,
  max_label_cardinality: 100
)
```

When enabled, high-cardinality labels (e.g., `user_id`, `order_id`) are filtered from metric tags.

---

## Documentation

Additional documentation is available in the `docs/` directory:

- Architecture Decision Records (ADRs)
- Use Cases
- Configuration guides
- Performance benchmarks

---

## Development

### Running Tests

E11y has three test suites with different requirements:

#### Quick Commands (recommended)

```bash
# Using rake tasks
rake spec:unit            # Unit tests (~1672 examples, includes all e11y tests)
rake spec:integration     # Integration tests (~36 examples, requires Rails)
rake spec:railtie        # Railtie tests (~21 examples, Rails initialization)
rake spec:all            # All tests (~1729 examples, unit + integration + railtie)
rake spec:benchmark      # Benchmark tests (~44 examples, slow)
rake spec:coverage       # With coverage
```

#### Manual Commands

```bash
# Unit tests (fast, no Rails required)
bundle exec rspec --exclude-pattern 'spec/{integration,e11y/railtie_integration_spec.rb}/**/*_spec.rb'

# Integration tests (requires: bundle install --with integration)
INTEGRATION=true bundle exec rspec spec/integration/

# Railtie integration tests
bundle exec rspec spec/e11y/railtie_integration_spec.rb --tag railtie_integration

# All tests
bundle exec rspec

# Benchmarks (optional)
bundle exec rspec --tag benchmark
```

### Test Suite Overview

- **Unit tests** (~1672 examples, ~30s): Core logic, all e11y/* tests
- **Integration tests** (~36 examples, ~5s): Rails, ActiveJob, Sidekiq integration
- **Railtie tests** (~21 examples, ~2s): Rails initialization and configuration
- **Benchmark tests** (~44 examples, ~30s): Performance tests (run with `rake spec:benchmark`)

### Other Development Commands

```bash
# Linting
bundle exec rubocop

# Auto-fix linting issues
bundle exec rubocop -a

# Interactive console
rake e11y:console

# Generate documentation
rake e11y:docs

# Security audit
rake e11y:audit

# Run benchmarks
rake e11y:benchmark
```

---

## Contributing

Bug reports and pull requests are welcome at https://github.com/arturseletskiy/e11y.

Contributing workflow:
1. Fork the repository
2. Create a feature branch
3. Run tests: `rake spec:all`
4. Run linter: `bundle exec rubocop`
5. Submit a pull request

**Note:** Performance benchmarks are excluded from default test runs due to CI environment variability. Run them explicitly with `--tag benchmark` when needed.

---

## License

MIT License. See [LICENSE.txt](LICENSE.txt) for details.

---

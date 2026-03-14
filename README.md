<div align="center">

# E11y - Easy Telemetry

**Debug production issues in seconds. Zero setup overhead. Own your data.**

[![Gem Version](https://badge.fury.io/rb/e11y.svg)](https://badge.fury.io/rb/e11y)
[![CI](https://github.com/arturseletskiy/e11y/actions/workflows/ci.yml/badge.svg)](https://github.com/arturseletskiy/e11y/actions/workflows/ci.yml)
[![Code Coverage](https://codecov.io/gh/arturseletskiy/e11y/branch/main/graph/badge.svg)](https://codecov.io/gh/arturseletskiy/e11y)

[Quick Start](#quick-start) • [How it works](#the-e11y-solution) • [Docs](#documentation)

> v0.2.0 · Actively developed · Production feedback welcome → [open an issue](https://github.com/arturseletskiy/e11y/issues)

</div>

**Contents:** [Quick Look](#quick-look-2-minutes) · [Quick Start](#quick-start) · [Features](#what-makes-e11y-different) · [vs Alternatives](#e11y-vs-alternatives) · [Docs](#documentation)

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

## Quick Look (2 minutes)

```ruby
# 1. Configure once
E11y.configure do |config|
  config.request_buffer.enabled = true
  config.adapters[:logs] = E11y::Adapters::Loki.new(url: ENV["LOKI_URL"])
end

# 2. Define a business event
class OrderPaidEvent < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float, gt?: 0)
    required(:currency).filled(:string, included_in?: %w[USD EUR GBP])
    optional(:user_email).maybe(:string)
  end

  validation_mode :sampled, sample_rate: 0.01   # 1% validation for hot path
  contains_pii true
  pii_filtering { hashes :user_email }
  sample_by_value :amount, greater_than: 1000  # Always sample large orders

  metrics do
    counter :orders_total, tags: [:currency]
    histogram :order_amount, value: :amount, tags: [:currency]
  end
end

# 3. Track it
OrderPaidEvent.track(order_id: "123", amount: 99.99, currency: "USD")
```

→ [Full Quick Start guide (5 min)](#quick-start)

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
- **Storage costs:** Up to -90% log volume → proportional Loki storage savings
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
# Fast setup, not 2-week OpenTelemetry migration
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

### 6. Built-in PII Filtering

**Built-in PII filtering** — mask, hash, or redact sensitive fields per event class. No other Ruby observability gem provides this out of the box.

```ruby
class Events::UserSignedIn < E11y::Event::Base
  contains_pii :email, strategy: :hash
  contains_pii :ip_address, strategy: :mask
end
```

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
- **Enterprise compliance requirements** — audit trails and compliance reports are not yet available
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

## Quick Start

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
- ❌ High log storage bills from storing everything

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
# Cost: High (all logs stored) ❌
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
# Cost: Low (-90% log volume) ✅
# Search time: 3 seconds ✅ (-90%)
```

**Impact:**
- **Developer productivity:** 10x faster debugging (context when you need it)
- **Infrastructure cost:** -90% log storage (only relevant logs stored)
- **Signal-to-noise:** 100% vs 1% (every log line matters)

---

## E11y vs Alternatives

### Comparison Matrix

| Solution | Setup Time | Monthly Cost | Request-Scoped Buffering | SLO Tracking | Schema Validation | Auto-Metrics | Built-in PII Filtering | Data Ownership | Ecosystem / Managed Infra |
|----------|-----------|--------------|--------------------------|--------------|-------------------|--------------|------------------------|----------------|--------------------------|
| **E11y** | **5–30 min*** | **Infra costs** | **✅ Unique** | **✅ Zero-config** | **✅** | **✅** | **✅ Field masking, hashing, redaction** | **✅ Full** | ⚠️ Ruby/Rails only |
| Datadog APM | 2-4 hours | $500-5,000 | ❌ | ✅ Manual | ❌ | ✅ | ⚠️ Via agent config (limited) | ❌ SaaS lock-in | ✅ Extensive + fully managed |
| New Relic | 2-4 hours | $99-658/user | ❌ | ✅ Manual | ❌ | ✅ | ⚠️ Via obfuscation rules | ❌ SaaS lock-in | ✅ Extensive + fully managed |
| Sentry | 1 hour | $26-80/mo | ❌ | ❌ | ❌ | Partial | ⚠️ Data scrubbing rules | ❌ SaaS lock-in | ✅ Managed (error-focused) |
| Semantic Logger | 30 minutes | Infra costs | ❌ | ❌ | ❌ | ❌ | ❌ None | ✅ Full | ⚠️ Ruby only, self-hosted |
| OpenTelemetry | 1-2 weeks | Infra costs | ❌ | Manual setup | ❌ | ✅ | ❌ Manual implementation required | ✅ Full | ✅ Polyglot, vendor-neutral |
| Grafana + Loki | 2-3 days | Infra costs | ❌ | Manual setup | ❌ | Manual | ❌ None | ✅ Full | ✅ Mature, DevOps-friendly |
| AppSignal | 1 hour | $23-499/mo | ❌ | ✅ Built-in | ❌ | ✅ | ⚠️ Parameter filtering only | ❌ SaaS lock-in | ✅ Managed (Rails-friendly) |

**Legend:**
- **Setup Time:** From zero to first meaningful data
- **Monthly Cost:** For 10-person team, medium Rails app (estimated)
- **Request-Scoped Buffering:** Buffer debug logs, flush only on errors
- **SLO Tracking:** Automatic Service Level Objectives monitoring
- **Schema Validation:** Type-safe event schemas
- **Auto-Metrics:** Metrics generated from events automatically
- **Built-in PII Filtering:** Automatic masking/hashing of sensitive fields (emails, IPs, credit cards, etc.) — no other Ruby observability gem provides this out of the box
- **Data Ownership:** Can you host it yourself?
- **Ecosystem / Managed Infra:** Integration breadth and whether infrastructure is managed for you

*\* 5 min for gem + stdout; 30 min if adding self-hosted Loki/Grafana stack.

> Cost estimates assume migration from verbose SaaS logging (Datadog/CloudWatch) to self-hosted Loki. Actual savings depend on your current setup.

---

### Detailed Comparisons

See [docs/COMPARISON.md](docs/COMPARISON.md) for detailed per-tool comparisons.

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
- Enterprise compliance requirements (not yet available)

---

## Performance

p99 latency <70µs (`:always`), <10µs (`:sampled`), <50µs (`:never`). Full benchmarks → [docs/PERFORMANCE.md](docs/PERFORMANCE.md)

---

## Documentation

| Topic | Doc |
|-------|-----|
| [Schema Validation](docs/SCHEMA_VALIDATION.md) | dry-schema validation, modes, error handling |
| [Metrics DSL](docs/METRICS_DSL.md) | Counters, histograms, gauges, Yabeda integration |
| [Adapters](docs/ADAPTERS.md) | Loki, Sentry, OTel, Yabeda, File, Stdout, InMemory |
| [PII Filtering](docs/PII_FILTERING.md) | Mask, hash, redact sensitive fields |
| [Adaptive Sampling](docs/ADAPTIVE_SAMPLING.md) | Error-based, load-based, value-based |
| [Presets](docs/PRESETS.md) | HighValueEvent, AuditEvent, DebugEvent |
| [Distributed Tracing](docs/DISTRIBUTED_TRACING.md) | W3C Trace Context, manual propagation |
| [Rails Integration](docs/RAILS_INTEGRATION.md) | Auto-instrumentation, Sidekiq |
| [Testing](docs/TESTING.md) | InMemoryTest adapter, RSpec setup |
| [Configuration](docs/CONFIGURATION.md) | Basic config, middleware pipeline |
| [Performance](docs/PERFORMANCE.md) | Benchmarks, validation modes, cardinality |
| [Limitations](docs/LIMITATIONS.md) | Rails only, Ruby 3.2+, tradeoffs |
| [Comparison](docs/COMPARISON.md) | vs Datadog, OTel, Sentry, AppSignal, etc. |

Also: [ADRs](docs/ADR-INDEX.md), [Use Cases](docs/use_cases/README.md), [QUICK-START](docs/QUICK-START.md)

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

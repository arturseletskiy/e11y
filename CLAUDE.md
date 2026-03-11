# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

E11y ("easy telemetry") is a Ruby gem providing observability for Rails apps. Its key differentiator is **request-scoped debug buffering**: debug logs accumulate in memory during a request and flush to storage only if the request fails, cutting noise by ~90%.

- **Ruby**: 3.2+, **Rails**: 7.0–8.0 (8.1 excluded due to a sqlite3 bug)
- **Gem version**: 0.2.0, current branch: `feat/integration-testing`

## Commands

```bash
# Run all tests
rake spec:all

# Run unit tests only (fast, no Rails required)
rake spec:unit

# Run integration tests (requires --with integration bundle group)
rake spec:integration

# Run a single spec file
bundle exec rspec spec/e11y/adapters/loki_adapter_spec.rb

# Run a single example by line number
bundle exec rspec spec/e11y/adapters/loki_adapter_spec.rb:42

# Lint
bundle exec rubocop

# Lint with autocorrect
bundle exec rubocop -a

# Install integration dependencies (needed before rake spec:integration)
bundle install --with integration

# Open a console with the gem loaded
rake console

# Run benchmarks
rake spec:benchmark

# Run Cucumber acceptance tests
rake cucumber
# Or: bundle exec cucumber features/

# Cucumber with Loki (adapter_configurations.feature): start Loki first
docker-compose up -d loki
rake cucumber
```

## Architecture

### Event Processing Pipeline

Every event flows through a middleware pipeline before reaching an adapter:

```
Event.track(data)
  → Validation (dry-schema)
  → Sampling (adaptive: error-spike, load, value-based)
  → PII Filtering (mask/hash sensitive fields)
  → Trace Context (attach OTel span/trace IDs)
  → Routing (direct to adapters by severity/type)
  → Rate Limiting
  → Audit Signing
  → Adapter(s): Loki | Sentry | OpenTelemetry | Yabeda | File | Stdout | InMemory
```

Pipeline is built in `lib/e11y/pipeline/builder.rb`. Middleware order matters — see ADR-015.

### Key Modules

| Path | Role |
|------|------|
| `lib/e11y.rb` | Public API, `E11y.configure`, `E11y.configuration`, `E11y.logger` |
| `lib/e11y/event/base.rb` | Base event class; all user events inherit from this |
| `lib/e11y/adapters/` | Backend adapters (Loki, Sentry, OTel, Yabeda, File, Stdout, InMemory) |
| `lib/e11y/middleware/` | 11 pipeline stages (validation, sampling, PII, routing, etc.) |
| `lib/e11y/buffers/` | Request-scoped buffer + adaptive buffer implementations |
| `lib/e11y/pipeline/builder.rb` | Assembles middleware chain from configuration |
| `lib/e11y/railtie.rb` | Rails integration entry point |
| `lib/e11y/pii/` | PII detection patterns and masking/hashing strategies |
| `lib/e11y/sampling/` | Error-spike, load-based, value-based sampling strategies |
| `lib/e11y/reliability/` | Circuit breaker, DLQ (dead letter queue), retry logic |
| `lib/e11y/slo/` | Event-driven SLO tracking |
| `lib/e11y/metrics/` | Prometheus metrics registry with cardinality protection |

### Event Definition Pattern

Events are defined as classes inheriting from `E11y::Event::Base`:

```ruby
class Events::OrderCreated < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float)
    optional(:user_id).maybe(:string)
  end

  metrics do
    counter :orders_created_total, "Orders created"
    histogram :order_amount, "Order amount in USD", buckets: [10, 50, 100, 500]
  end
end

# Usage
Events::OrderCreated.track(order_id: order.id, amount: order.total)
```

### Adapter Routing

Adapters are registered in configuration and events route to them by severity:
- `error`/`fatal` → errors tracker (e.g., Sentry)
- other severities → logs (e.g., Loki)
- metrics always → Yabeda/Prometheus

### Request-Scoped Buffering

The buffer middleware captures debug-level events in a `Concurrent::Array` per request (stored in `Thread.current`). On request success: buffer discarded. On request failure: buffer flushed to configured adapters. Controlled by `config.enable_request_buffering`.

## Test Structure

- `spec/e11y/` — Unit tests (86 files, ~1672 examples, fast)
- `spec/integration/` — Integration tests against a real Rails app (~36 examples)
- `spec/dummy/` — Minimal Rails app used by integration tests
- `spec/dummy/app/events/events/` — Event class definitions for test fixtures
- `spec/support/matchers/` — Custom RSpec matchers including PII matchers
- `spec/fixtures/pii_samples.yml` — PII test data

Integration tests use `DatabaseCleaner` and require `--with integration` bundle group.

## Code Conventions

- Frozen string literals everywhere (`# frozen_string_literal: true`)
- Double-quoted strings (enforced by RuboCop)
- Events use class-level `.track` (not instantiation) — zero-allocation design; data stored in plain Hashes
- Adapters inherit from `E11y::Adapters::Base` and implement `#deliver(event_data)`
- Middleware inherits from `E11y::Middleware::Base` and implements `#call(event, pipeline)`

## Architecture Decision Records

The `docs/ADR-*.md` files document design decisions. Key ones:
- **ADR-004**: Adapter architecture
- **ADR-011**: Testing strategy
- **ADR-013**: Reliability and error handling
- **ADR-015**: Middleware ordering (critical — changing order breaks the pipeline)
- **ADR-017**: Multi-Rails compatibility approach

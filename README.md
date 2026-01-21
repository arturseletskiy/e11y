# E11y - Easy Telemetry for Ruby on Rails

[![Gem Version](https://badge.fury.io/rb/e11y.svg)](https://badge.fury.io/rb/e11y)
[![Build Status](https://github.com/arturseletskiy/e11y/workflows/CI/badge.svg)](https://github.com/arturseletskiy/e11y/actions)
[![Code Coverage](https://codecov.io/gh/arturseletskiy/e11y/branch/main/graph/badge.svg)](https://codecov.io/gh/arturseletskiy/e11y)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-rubocop-brightgreen.svg)](https://github.com/rubocop/rubocop)

**Production-ready observability for Rails applications.**

E11y (Easy Telemetry) provides structured business event tracking with request-scoped debug buffering, pattern-based metrics, zero-config SLO tracking, and pluggable adapters for logs/metrics/traces. Designed for SuperApp architecture with compliance-ready PII filtering and audit trails.

## 🚀 Quick Start

```ruby
# Gemfile
gem "e11y"

# Define your first event
class OrderPaidEvent < E11y::Event::Base
  schema do
    required(:order_id).filled(:integer)
    required(:amount).filled(:float)
  end
  
  severity :success  # Optional - auto-detected from name
  adapters :loki     # Optional - auto-selected based on severity
end

# Track events (zero-allocation pattern)
OrderPaidEvent.track(order_id: 123, amount: 99.99)
```

## ✨ Features

- 🎯 **Zero-Allocation Event Tracking** - Class-based pattern with zero GC pressure
- 📐 **Convention over Configuration** - Smart defaults from event names
- 📊 **Type-Safe Events** - Declarative schemas with dry-schema validation
- 🔄 **Event Versioning** - Built-in version support for schema evolution
- 🎭 **Severity Levels** - Auto-detection from event names
- 🔌 **Pluggable Adapters** - Loki, Sentry, OpenTelemetry, File, Stdout, Memory
- 📦 **Future Ready** - Architecture designed for Phase 2+ features:
  - Request-Scoped Debug Buffering
  - Pattern-Based Metrics (Prometheus/Yabeda)
  - PII Filtering & Audit Trails (GDPR/SOC2)
  - Rate Limiting & Cardinality Protection
  - OpenTelemetry Integration
  - Rails/Sidekiq Integration

## 📚 Documentation

- [Quick Start Guide](docs/QUICK-START.md)
- [Implementation Plan](docs/IMPLEMENTATION_PLAN.md)
- [Architecture Decisions (ADRs)](docs/)
- [Use Cases](docs/use_cases/)
- [API Reference](https://e11y.dev/api)

## 🛠️ Installation

Add this line to your application's Gemfile:

```ruby
gem "e11y"
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install e11y
```

## 📖 Usage

### Define Events

```ruby
# Convention-based configuration (minimal)
class UserSignupEvent < E11y::Event::Base
  schema do
    required(:user_id).filled(:integer)
    required(:email).filled(:string)
  end
  # Severity auto-detected: :info
  # Adapters auto-selected: [:loki]
end

# Explicit configuration
class PaymentFailedEvent < E11y::Event::Base
  severity :error           # Explicit severity
  version 2                 # Event version
  adapters :loki, :sentry   # Multiple adapters
  
  schema do
    required(:payment_id).filled(:integer)
    required(:error_code).filled(:string)
  end
end

# Track events (class method - no instances!)
UserSignupEvent.track(user_id: 123, email: "user@example.com")
PaymentFailedEvent.track(payment_id: 456, error_code: "CARD_DECLINED")
```

### Convention-Based Defaults

E11y uses smart conventions to minimize configuration:

**Severity from event name:**
- `*Failed*`, `*Error*` → `:error`
- `*Paid*`, `*Success*`, `*Completed*` → `:success`
- `*Warn*`, `*Warning*` → `:warn`
- Default → `:info`

**Adapters from severity:**
- `:error`, `:fatal` → `[:loki, :sentry]` (errors need both logging and alerting)
- Others → `[:loki]` (logs only)

**Result:** 90% of events need only `schema` definition!

## 🧪 Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

```bash
# Install dependencies
bin/setup

# Run tests
bundle exec rspec

# Run linter
bundle exec rubocop

# Run security audit
bundle exec bundler-audit check --update
bundle exec brakeman

# Generate documentation
bundle exec yard doc
```

## 🤝 Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/arturseletskiy/e11y. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](CODE_OF_CONDUCT.md).

## 📜 License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).

## 🙏 Code of Conduct

Everyone interacting in the E11y project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).

## 📊 Project Status

**Current Version:** 0.1.0

**Development Progress:**
- ✅ Phase 0: Gem Setup & Best Practices
- ✅ Phase 1: Core Foundation
- ✅ Phase 2: Core Features (PII, Adapters, Metrics)
- ✅ Phase 3: Rails Integration
- ✅ Phase 4: Production Hardening
- 🔄 Phase 5: Scale & Optimization (In Progress)
  - ✅ High Cardinality Protection (4-layer defense)
  - ✅ Tiered Storage Migration (hot/warm/cold)
  - ✅ Performance Benchmarks (1K/10K/100K events/sec)
  - 🔄 Documentation & Testing
  - ⏳ Gem Release

See [IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) for detailed timeline.

## 📚 Additional Documentation

- [Architecture Decisions (ADR Index)](docs/ADR-INDEX.md)
- [API Reference](docs/API.md)
- [Guides](docs/guides/):
  - [Migrating from Rails.logger](docs/guides/rails-logger-migration.md)
  - [Custom Middleware Guide](docs/guides/custom-middleware.md)
  - [Custom Adapter Guide](docs/guides/custom-adapter.md)
  - [Performance Tuning](docs/guides/performance-tuning.md)

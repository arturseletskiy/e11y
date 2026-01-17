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

# config/initializers/e11y.rb
E11y.configure do |config|
  config.adapters = [:loki, :sentry]
  config.log_level = :info
end

# Track business events
E11y.track(Events::UserSignup.new(
  user_id: 123,
  source: "web",
  plan: "premium"
))
```

## ✨ Features

- 🎯 **Request-Scoped Debug Buffering** - Buffer debug events in memory, flush only on error (reduce log noise by 90%)
- 📊 **Zero-Config SLO Tracking** - Automatic Service Level Objective monitoring for HTTP and background jobs
- 📈 **Pattern-Based Metrics** - Auto-generate Prometheus/Yabeda metrics from business events
- 🔒 **GDPR/SOC2 Compliant** - Built-in PII filtering and audit trails for compliance
- 🔌 **Pluggable Adapters** - Send to Loki, Sentry, OpenTelemetry, Elasticsearch, File, Stdout
- 🚀 **High Performance** - Zero-allocation event tracking, lock-free ring buffers, adaptive memory limits
- 🧵 **Thread-Safe** - Designed for multi-threaded Rails apps and Sidekiq workers
- 🎭 **Multi-Service Tracing** - OpenTelemetry integration with automatic trace context propagation
- 📝 **Type-Safe Events** - Declarative schemas with dry-schema validation
- ⚡ **Rate Limiting & Sampling** - Protect production from metric storms and cost overruns
- 🛡️ **Cardinality Protection** - Prevent metric explosions from high-cardinality data
- 📦 **Rails Integration** - Railtie, ActiveSupport::Notifications bridge, Sidekiq middleware

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

### Basic Configuration

```ruby
E11y.configure do |config|
  # Adapters
  config.adapters = [:loki, :stdout]
  
  # Buffer settings
  config.buffer_size = 1000
  config.memory_limit = 10.megabytes
  
  # PII filtering
  config.pii_filters = [:email, :phone, :ssn]
  
  # Sampling
  config.sampling_rate = 0.1 # 10%
end
```

### Track Events

```ruby
# Define custom event
class Events::UserSignup < E11y::Event
  schema do
    required(:user_id).filled(:integer)
    required(:source).filled(:string)
    optional(:referrer).maybe(:string)
  end
  
  # Event-level adapter configuration
  adapters :loki, :sentry
  
  # PII fields
  pii_fields :email, :ip_address
end

# Track event
E11y.track(Events::UserSignup.new(
  user_id: 123,
  source: "web",
  email: "user@example.com" # Will be masked
))
```

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

**Current Version:** 0.1.0 (Phase 0: Gem Setup & Best Practices)

**Roadmap:**
- ✅ Phase 0: Gem Setup & Best Practices (Week -1)
- 🔄 Phase 1: Core Foundation (Weeks 1-4)
- ⏳ Phase 2: Rails Integration (Weeks 5-8)
- ⏳ Phase 3: Adapters & External Systems (Weeks 9-12)
- ⏳ Phase 4: Advanced Features (Weeks 13-16)
- ⏳ Phase 5: Production Readiness (Weeks 17-20)

See [IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) for detailed timeline.

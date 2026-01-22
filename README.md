<div align="center">

# E11y

**Type-safe business events for Rails with pluggable adapters**

[![Gem Version](https://badge.fury.io/rb/e11y.svg)](https://badge.fury.io/rb/e11y)
[![Build Status](https://github.com/arturseletskiy/e11y/workflows/CI/badge.svg)](https://github.com/arturseletskiy/e11y/actions)
[![Code Coverage](https://codecov.io/gh/arturseletskiy/e11y/branch/main/graph/badge.svg)](https://codecov.io/gh/arturseletskiy/e11y)

Schema validation • Auto metrics • PII filtering • Multi-backend

[Quick Start](#quick-start) • [Core Features](#core-features) • [Documentation](#documentation)

</div>

```ruby
class OrderPaidEvent < E11y::Event::Base
  schema { required(:order_id).filled(:string) }
  
  metrics do
    counter :orders_total, tags: [:currency]
    histogram :order_amount, value: :amount, tags: [:currency]
  end
end

OrderPaidEvent.track(order_id: "123", amount: 99.99, currency: "USD")
# ✅ Schema validated
# ✅ Sent to Loki/Sentry
# ✅ Metrics incremented (orders_total, order_amount)
```

---

## Why E11y?

E11y provides structured, validated business events for Rails applications.

### The Problem

Traditional logging lacks structure and validation:

```ruby
# Unvalidated logging
logger.info "order.paid user_id=#{user.id} amount=#{order.total}"
# If order.total is nil, you discover this in production

# Manual metrics duplication
logger.info "Order paid: #{order.id}"
Yabeda.orders.paid.increment(currency: order.currency)
# Easy to forget, no validation

# Vendor lock-in
Datadog.logger.info(...)
# Switching backends requires code changes
```

### The Solution

E11y provides schema-validated events with automatic metrics:

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

# Invalid data raises validation error
OrderPaidEvent.track(order_id: "123", amount: -10, currency: "INVALID")
# => E11y::ValidationError: amount must be > 0

# Valid data sends event and updates metrics
OrderPaidEvent.track(order_id: "123", amount: 99.99, currency: "USD")
# => Event sent to configured adapters
# => Metrics automatically updated
```

---

## Core Features

| Feature | Description |
|---------|-------------|
| **Schema Validation** | Validate event data with dry-schema before sending |
| **Metrics DSL** | Define Prometheus metrics alongside events |
| **Pluggable Adapters** | Support for Loki, Sentry, OpenTelemetry, File, Stdout, InMemory |
| **PII Filtering** | Configurable PII field masking and hashing |
| **Adaptive Sampling** | Error-based, load-based, and value-based sampling strategies |
| **Performance** | Hash-based events minimize memory allocations |
| **Cardinality Protection** | Optional label cardinality limits for metrics systems |

---

## Quick Start

### 1. Install

```bash
# Gemfile
gem "e11y"

bundle install
```

Create an initializer:

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  # Configure adapters (see Adapters section)
end
```

### 2. Define Event

```ruby
# app/events/order_paid_event.rb
class OrderPaidEvent < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float, gt?: 0)
    required(:currency).filled(:string)
  end
  
  # Optional: Define metrics
  metrics do
    counter :orders_total, tags: [:currency]
    histogram :order_amount, value: :amount, tags: [:currency]
  end
end
```

### 3. Track Events

```ruby
# In controller/service
OrderPaidEvent.track(
  order_id: order.id,
  amount: order.total,
  currency: "USD"
)
```

Events are validated against schema, sent to configured adapters, and converted to metrics automatically.

---

## Table of Contents

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
3. When `track()` is called, metrics are automatically updated
4. Metrics exported via Yabeda adapter (Prometheus format)

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

## Contributing

Bug reports and pull requests are welcome at https://github.com/arturseletskiy/e11y.

Development:
1. Fork the repository
2. Create a feature branch
3. Run tests: `bundle exec rspec`
4. Run linter: `bundle exec rubocop`
5. Submit a pull request

---

## License

MIT License. See [LICENSE.txt](LICENSE.txt) for details.

---

# Metrics DSL

> Back to [README](../README.md#documentation)

Define Prometheus metrics alongside events.

## Basic Example

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

## Metric Types

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

## How It Works

1. Define metrics in event class
2. Metrics registered in `E11y::Metrics::Registry` at boot time
3. When `track()` is called, metrics are automatically updated **if the Yabeda adapter is configured and routed to**
4. Metrics exported via Yabeda adapter (Prometheus format)

> **Note:** The `metrics do` DSL only registers metric definitions. Metrics are actually updated
> when an event is written to the `E11y::Adapters::Yabeda` adapter. If you omit the Yabeda adapter
> from your configuration, `track()` will send events to Loki/Sentry but metric counters will not
> be incremented. Make sure to add:
>
> ```ruby
> config.adapters[:metrics] = E11y::Adapters::Yabeda.new
> ```

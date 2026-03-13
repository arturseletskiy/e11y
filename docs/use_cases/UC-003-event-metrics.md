# UC-003: Event Metrics

**Status:** Implemented  
**Complexity:** Intermediate  
**Setup Time:** 15-30 minutes  
**Target Users:** DevOps, SRE, Backend Developers

---

## Overview

Define metrics directly in event classes. Metrics are registered at boot and updated automatically when events are tracked.

### Event-Level Metrics DSL

```ruby
class Events::OrderPaid < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float)
    required(:currency).filled(:string)
    required(:payment_method).filled(:string)
  end

  metrics do
    counter :orders_paid_total, tags: [:currency, :payment_method]
    histogram :orders_paid_amount, value: :amount, tags: [:currency], buckets: [10, 50, 100, 500, 1000, 5000]
  end
end

Events::OrderPaid.track(order_id: '123', amount: 99.99, currency: 'USD', payment_method: 'stripe')
# → orders_paid_total{currency="USD",payment_method="stripe"} += 1
# → orders_paid_amount_bucket{currency="USD",le="100"} += 1
```

### Metric Types

- **counter** — monotonically increasing
- **histogram** — distribution (requires `value:` field, optional `buckets:`)
- **gauge** — point-in-time value (requires `value:`)

### Boot-Time Validation

E11y validates metrics at Rails boot: label conflicts, type conflicts. Non-Rails: call `E11y::Metrics::Registry.instance.validate_all!` after loading events.

### Shared Metrics via Inheritance

```ruby
class BaseOrderEvent < E11y::Event::Base
  metrics do
    counter :orders_total, tags: [:currency, :status]
  end
end

class Events::OrderPaid < BaseOrderEvent
  metrics do
    histogram :order_amount, value: :amount, tags: [:currency]
  end
end
```

---

## Yabeda Integration

Register Yabeda adapter in `config.adapters`. Metrics flow to Prometheus via Yabeda.

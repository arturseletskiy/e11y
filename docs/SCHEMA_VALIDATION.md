# Schema Validation

> Back to [README](../README.md#documentation)

E11y validates event data using [dry-schema](https://dry-rb.org/gems/dry-schema/).

## Basic Example

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

## Validation Modes

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

## Validation Behavior

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

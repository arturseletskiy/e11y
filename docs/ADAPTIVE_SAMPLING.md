# Adaptive Sampling

> Back to [README](../README.md#documentation)

E11y supports adaptive sampling to reduce event volume during high load.

Sampling strategies:

1. **Error-based** - Increase sampling during error spikes
2. **Load-based** - Reduce sampling under high throughput
3. **Value-based** - Always sample high-value events

> **Note:** Rate limiting (`E11y::Middleware::RateLimiting`) is **not included in the default
> pipeline**. To enable it, add it manually:
>
> ```ruby
> config.pipeline.use E11y::Middleware::RateLimiting
> ```
> Enabling `config.rate_limiting_enabled = true` alone has no effect without this step.

## Configuration

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

## Value-Based Sampling

Sample events based on payload values:

```ruby
class PaymentEvent < E11y::Event::Base
  sample_by_value :amount, greater_than: 1000  # Always sample large payments
end
```

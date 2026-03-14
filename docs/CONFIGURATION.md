# Configuration

> Back to [README](../README.md#documentation)

## Basic Configuration

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

## Middleware Pipeline

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

For full configuration options, see [COMPREHENSIVE-CONFIGURATION.md](COMPREHENSIVE-CONFIGURATION.md).

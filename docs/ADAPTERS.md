# Adapters

> Back to [README](../README.md#documentation)

E11y supports multiple adapters for different backends.

| Adapter | Purpose | Batching | Use Case |
|---------|---------|----------|----------|
| **Loki** | Log aggregation (Grafana) | Yes | Production logs |
| **Sentry** | Error tracking | Via SDK | Error monitoring |
| **OpenTelemetry** | OTLP export (OTelLogs, OpenTelemetryCollector) | Varies | Distributed tracing, logs |
| **Yabeda** | Prometheus metrics | N/A | Metrics export |
| **File** | Local logs | Yes | Development, CI |
| **Stdout** | Console output | No | Development |
| **InMemory** | Test buffer | No | Testing |

## Configuration

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

  # OpenTelemetry Collector (compress: true default, requires Faraday)
  # config.adapters[:otel] = E11y::Adapters::OpenTelemetryCollector.new(
  #   endpoint: ENV["OTEL_EXPORTER_OTLP_ENDPOINT"],
  #   service_name: "my-app"
  # )
end
```

## Adapter Routing by Severity

Events are routed to adapters based on severity. The default mapping:

- `error`, `fatal` → `[:logs, :errors_tracker]`
- Other severities → `[:logs]`

Override routing explicitly:

```ruby
class CustomEvent < E11y::Event::Base
  adapters :logs, :stdout  # Explicit routing
end
```

## Custom Adapters

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

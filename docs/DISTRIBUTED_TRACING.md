# Distributed Tracing

> Back to [README](../README.md#documentation)

E11y automatically attaches W3C Trace Context headers to incoming requests via the `TraceContext` middleware and propagates trace/span IDs through the event pipeline.

## Incoming Trace Context

Incoming `traceparent` / `tracestate` headers are extracted automatically:

```ruby
E11y.configure do |config|
  config.pipeline.use E11y::Middleware::TraceContext
end
```

Events tracked during a request will include `trace_id` and `span_id` from the incoming context.

## Outgoing HTTP Trace Propagation (Manual — v1.0)

> **Note:** Automatic outgoing trace context injection (Faraday / Net::HTTP middleware) is planned for v1.1.
> Until then, use the helper below to propagate W3C Trace Context manually:

```ruby
# Helper: build W3C traceparent header from current context
def traceparent_header
  return {} unless E11y::Current.trace_id

  span_id = E11y::Current.span_id || SecureRandom.hex(8)
  { "traceparent" => "00-#{E11y::Current.trace_id}-#{span_id}-01" }
end

# Faraday — inject on each connection
conn = Faraday.new(url: "https://api.example.com") do |f|
  f.headers.merge!(traceparent_header)
end

# Net::HTTP — inject per request
request = Net::HTTP::Post.new("/events")
traceparent_header.each { |k, v| request[k] = v }
http.request(request)
```

This ensures downstream services receive a valid `traceparent` header and can correlate logs/traces back to the originating request.

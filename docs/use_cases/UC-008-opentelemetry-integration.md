# UC-008: OpenTelemetry Integration

**Status:** v1.1+ Enhancement  
**Complexity:** Advanced  
**Setup Time:** 30-45 minutes  
**Target Users:** Platform Engineers, SRE, DevOps

---

## 📋 Overview

### Problem Statement

**The fragmentation problem:**
```ruby
# ❌ BEFORE: Separate systems, no integration
# - E11y for business events → Loki
# - OpenTelemetry for traces → Jaeger
# - Prometheus for metrics → Grafana
# - Logs go to different place than traces
# - Can't correlate events with spans
# - Different metadata formats
# - Manual trace ID management

# Problems:
# 1. Three different telemetry systems
# 2. No automatic correlation (logs ↔ traces ↔ metrics)
# 3. Different semantic conventions (your fields vs OTel fields)
# 4. Manual instrumentation duplication
# 5. Can't use OTel Collector benefits (sampling, filtering, routing)
```

### E11y Solution

**Native OpenTelemetry integration:**
```ruby
# ✅ AFTER: Unified observability via OpenTelemetry
E11y.configure do |config|
  config.opentelemetry do
    enabled true
    
    # Use OTel Collector as backend
    collector_endpoint 'http://otel-collector:4318'
    
    # Automatic semantic conventions
    use_semantic_conventions true
    
    # Automatic span creation from events
    create_spans_for severity: [:error, :warn]
    
    # Export to OTel Logs Signal
    export_logs true
  end
end

# Result:
# ✅ Events → OTel Logs Signal → OTel Collector
# ✅ Automatic span creation for errors
# ✅ Trace context from OTel SDK (W3C Trace Context)
# ✅ Semantic conventions applied automatically
# ✅ All benefits of OTel Collector (sampling, routing, etc.)
```

---

## 🎯 Features

> **Implementation:** See [ADR-007: OpenTelemetry Integration](../ADR-007-opentelemetry-integration.md) for complete architecture, including [Section 3: OTel Collector Adapter](../ADR-007-opentelemetry-integration.md#3-otel-collector-adapter), [Section 4: Semantic Conventions](../ADR-007-opentelemetry-integration.md#4-semantic-conventions), and [Section 5: Logs Signal Export](../ADR-007-opentelemetry-integration.md#5-logs-signal-export).

### 1. OpenTelemetry Collector Adapter

**Route events to OTel Collector:**
```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.adapters[:otel] = E11y::Adapters::OpenTelemetryCollector.new(
    endpoint: ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] || 'http://localhost:4318',
    service_name: 'my-app',
    headers: { 'X-API-Key' => ENV['OTEL_API_KEY'] },
    compress: true  # default, gzip on HTTP body
  )
end

# Architecture:
# E11y Event → OTel Logs/Traces → OTel Collector → Multiple Backends
#                                                   ├─→ Jaeger (traces)
#                                                   ├─→ Loki (logs)
#                                                   ├─→ Prometheus (metrics)
#                                                   └─→ Object storage (archive, via OTel exporter)
```

---

### 2. Semantic Conventions Mapping

> **Implementation:** See [ADR-007 Section 4: Semantic Conventions](../ADR-007-opentelemetry-integration.md#4-semantic-conventions) for automatic field mapping across HTTP, DB, RPC, Messaging, and Exception patterns.

**Automatic field mapping to OTel standards:**
```ruby
# E11y event (your fields)
Events::HttpRequest.track(
  method: 'POST',
  path: '/api/orders',
  status_code: 201,
  duration_ms: 45
)

# ↓ Automatic mapping ↓

# OTel Logs Signal (semantic conventions)
{
  Timestamp: 1673520000000000000,
  SeverityText: 'INFO',
  SeverityNumber: 9,
  Body: 'order.created',
  
  # Resource attributes (service metadata)
  Resource: {
    'service.name': 'api',
    'service.version': '1.0.0',
    'service.instance.id': 'pod-abc-123',
    'deployment.environment': 'production'
  },
  
  # Span context (trace correlation)
  TraceId: 'abc123...',
  SpanId: 'def456...',
  TraceFlags: 1,
  
  # Attributes (semantic conventions applied!)
  Attributes: {
    # HTTP semantic conventions
    'http.method': 'POST',              # ← Mapped from 'method'
    'http.route': '/api/orders',        # ← Mapped from 'path'
    'http.status_code': 201,            # ← Mapped from 'status_code'
    'http.request.duration_ms': 45,     # ← Mapped from 'duration_ms'
    
    # Event metadata
    'event.name': 'order.created',
    'event.domain': 'order'
  }
}
```

**Supported Semantic Conventions:**
- ✅ HTTP (requests, routes, status codes)
- ✅ Database (queries, connections)
- ✅ RPC (gRPC, JSON-RPC)
- ✅ Messaging (queues, topics)
- ✅ FaaS (serverless functions)
- ✅ Exceptions (errors, stack traces)

---

### 3. Automatic Span Creation

> **Implementation:** See [ADR-007 Section 6: Traces Signal Export](../ADR-007-opentelemetry-integration.md#6-traces-signal-export) for automatic span creation rules and parent-child relationships.

**Create spans from E11y events:**
```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.opentelemetry do
    # Create spans for errors (for distributed tracing)
    create_spans_for severity: [:error, :fatal],
                     span_kind: :internal
    
    # HTTP requests already have spans (from OTel auto-instrumentation)
    # But business events need spans too!
    create_spans_for pattern: 'order.*',
                     span_kind: :internal,
                     span_name: ->(event) { event.event_name }
  end
end

# Usage: Automatic span creation!
Events::OrderProcessingStarted.track(
  order_id: '123',
  severity: :info
)

# Result in Jaeger:
# Parent Span: POST /api/orders (from OTel auto-instrumentation)
#   └─ Child Span: order.processing.started (from E11y event)
#       └─ Child Span: payment.captured (from E11y event)
#           └─ Child Span: shipment.scheduled (from E11y event)
```

---

### 4. W3C Trace Context Integration

> **Implementation:** See [ADR-007 Section 8: Trace Context Integration](../ADR-007-opentelemetry-integration.md#8-trace-context-integration) for OTel SDK as primary trace context source.

**Automatic trace context from OpenTelemetry SDK:**
```ruby
# E11y automatically uses OTel trace context
require 'opentelemetry/sdk'

OpenTelemetry::SDK.configure do |c|
  c.service_name = 'api'
  c.use_all # Auto-instrumentation
end

# E11y automatically detects OTel context!
E11y.configure do |config|
  config.trace_context do
    source :opentelemetry  # Use OTel SDK (automatic!)
  end
end

# Now all E11y events have OTel trace context:
Events::OrderCreated.track(order_id: '123')

# Event includes:
# - trace_id: from OpenTelemetry::Trace.current_span.context.trace_id
# - span_id: from OpenTelemetry::Trace.current_span.context.span_id
# - trace_flags: from OpenTelemetry::Trace.current_span.context.trace_flags
# → Can correlate with OTel traces in Jaeger!
```

---

### 5. OTel Logs Signal Export

> **Implementation:** See [ADR-007 Section 5: Logs Signal Export](../ADR-007-opentelemetry-integration.md#5-logs-signal-export) for OTLP JSON format and trace correlation details.

**Export E11y events as OpenTelemetry Logs:**
```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.opentelemetry do
    # Export to OTel Logs Signal (OTLP)
    export_logs true
    
    # Map severity levels
    severity_mapping do
      debug -> OpenTelemetry::SDK::Logs::SeverityNumber::DEBUG
      info -> OpenTelemetry::SDK::Logs::SeverityNumber::INFO
      warn -> OpenTelemetry::SDK::Logs::SeverityNumber::WARN
      error -> OpenTelemetry::SDK::Logs::SeverityNumber::ERROR
      fatal -> OpenTelemetry::SDK::Logs::SeverityNumber::FATAL
      success -> OpenTelemetry::SDK::Logs::SeverityNumber::INFO  # Custom!
    end
    
    # Resource attributes (service metadata)
    resource_attributes do
      'service.name' ENV['SERVICE_NAME']
      'service.version' ENV['GIT_SHA']
      'deployment.environment' Rails.env
      'host.name' Socket.gethostname
    end
  end
end

# Every E11y event → OTel Logs Signal
Events::OrderCreated.track(order_id: '123')

# ↓ Exported as ↓

# OpenTelemetry Log Record
{
  Timestamp: 1673520000000000000,
  ObservedTimestamp: 1673520000000000000,
  SeverityText: 'INFO',
  SeverityNumber: 9,
  Body: {
    event_name: 'order.created',
    order_id: '123'
  },
  TraceId: 'abc...',
  SpanId: 'def...',
  Resource: { ... },
  Attributes: { ... }
}
```

---

### 6. Baggage PII Protection (C08 Resolution) ⚠️ CRITICAL

> **⚠️ CRITICAL: C08 Conflict Resolution - PII Leaking via OpenTelemetry Baggage**  
> **See:** [ADR-006 Section 5.5](../ADR-006-security-compliance.md#55-opentelemetry-baggage-pii-protection-c08-resolution--critical) for detailed architecture and GDPR compliance rationale.  
> **Problem:** OpenTelemetry Baggage propagates data via HTTP headers (`baggage: key1=value1,key2=value2`), bypassing E11y's PII filtering. If a developer accidentally adds PII to baggage, it leaks across all services.  
> **Solution:** Block ALL baggage keys by default, allow ONLY safe keys via allowlist.

**The Problem - PII Leaking via HTTP Headers:**

OpenTelemetry Baggage is a W3C standard for propagating key-value pairs across distributed traces. However, it bypasses ALL security controls:

```ruby
# ❌ DANGER: PII in baggage leaks via HTTP headers
# Service A:
OpenTelemetry::Baggage.set_value('user_email', 'user@example.com')
OpenTelemetry::Baggage.set_value('ip_address', '192.168.1.100')

# HTTP call to Service B includes:
# baggage: user_email=user@example.com,ip_address=192.168.1.100
# ↑ PII transmitted in PLAIN TEXT via HTTP headers!
# ↑ Bypasses E11y PII filtering entirely!

# Problems:
# 1. ❌ GDPR violation - PII transmitted without consent
# 2. ❌ Security risk - PII visible in HTTP logs, proxies, CDNs
# 3. ❌ Audit risk - No record of PII transmission
# 4. ❌ Compliance risk - PII leaves your infrastructure without controls
```

**The Solution - Allowlist-Only Baggage:**

E11y blocks ALL baggage keys by default, allowing ONLY safe keys (no PII):

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.security_baggage_protection_enabled = true  # ✅ CRITICAL: Always enable in production
  
  # Allowlist: ONLY these keys are safe
  config.security_baggage_protection_allowed_keys = [
    'trace_id',       # ✅ Safe: Correlation ID
    'span_id',        # ✅ Safe: Trace context
    'environment',    # ✅ Safe: Deployment context
    'version',        # ✅ Safe: Service version
    'service_name',   # ✅ Safe: Service identifier
    'request_id',     # ✅ Safe: Request identifier
    # Custom safe keys (no PII!):
    'feature_flag_id',  # ✅ Safe: Feature flag name
    'ab_test_variant'   # ✅ Safe: A/B test group
  ]
  
  # Block mode: What happens when PII detected?
  config.security_baggage_protection_block_mode = :silent  # Options: :silent (log), :warn (log+warn), :raise (exception)
end
```

**Usage Examples:**

**❌ BLOCKED: PII Keys (Not in Allowlist)**

```ruby
# Service A:
OpenTelemetry::Baggage.set_value('user_email', 'user@example.com')
# → BLOCKED ❌ (not in allowlist)
# → Logged: "[E11y] Blocked PII from OpenTelemetry baggage: key='user_email'"

OpenTelemetry::Baggage.set_value('ip_address', '192.168.1.100')
# → BLOCKED ❌ (not in allowlist)

OpenTelemetry::Baggage.set_value('session_id', 'abc123')
# → BLOCKED ❌ (not in allowlist)

# HTTP call to Service B:
# baggage: (empty - all PII blocked!)
```

**✅ ALLOWED: Safe Keys (In Allowlist)**

```ruby
# Service A:
OpenTelemetry::Baggage.set_value('trace_id', 'abc123def456')
# → ALLOWED ✅

OpenTelemetry::Baggage.set_value('environment', 'production')
# → ALLOWED ✅

OpenTelemetry::Baggage.set_value('version', 'v2.1.0')
# → ALLOWED ✅

OpenTelemetry::Baggage.set_value('feature_flag_id', 'new_checkout_v2')
# → ALLOWED ✅

# HTTP call to Service B:
# baggage: trace_id=abc123def456,environment=production,version=v2.1.0,feature_flag_id=new_checkout_v2
# ✅ All safe keys propagated, no PII!
```

**✅ ALTERNATIVE: Use Pseudonymized Identifiers**

If you need to propagate user context, use non-PII identifiers:

```ruby
# ❌ BAD: PII in baggage
OpenTelemetry::Baggage.set_value('user_email', 'user@example.com')

# ✅ GOOD: Pseudonymized user identifier
OpenTelemetry::Baggage.set_value('user_id_hash', Digest::SHA256.hexdigest(user.email))
# → No PII, still allows correlation across services ✅
```

**Strict Mode for Development:**

Fail fast in non-production environments:

```ruby
# config/environments/development.rb
E11y.configure do |config|
  config.security_baggage_protection_enabled = true
  config.security_baggage_protection_block_mode = :raise  # ← RAISE exception on blocked keys (fail fast)
  config.security_baggage_protection_allowed_keys = E11y::BAGGAGE_PROTECTION_DEFAULT_ALLOWED_KEYS
end

# Developer tries to set PII:
OpenTelemetry::Baggage.set_value('user_email', 'test@example.com')
# → RAISES BaggagePiiError:
#    "Blocked PII from OpenTelemetry baggage: key='user_email'.
#     Only allowed keys: trace_id, environment, version, ..."
# ✅ Catch PII leaks during development!
```

**Why This Matters (GDPR Compliance):**

| GDPR Article | Requirement | How Baggage Protection Helps |
|--------------|-------------|------------------------------|
| **Art. 5(1)(c)** | Data minimisation | Only necessary metadata propagated |
| **Art. 5(1)(f)** | Integrity and confidentiality | PII cannot leak via trace context |
| **Art. 32** | Security of processing | Technical measure to prevent PII transmission |

**Monitoring:**

Track baggage protection effectiveness:

```ruby
# Metrics (via Yabeda)
Yabeda.e11y_baggage_pii_blocked_total.increment(
  key: 'user_email',
  service: 'api-gateway'
)

# Alert on repeated violations (indicates developer training needed)
if Yabeda.e11y_baggage_pii_blocked_total.get > 100
  Sentry.capture_message(
    "High volume of baggage PII violations detected",
    level: :warning
  )
end
```

---

## 💻 Implementation Examples

### Example 1: OTel Collector Setup

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      http:
        endpoint: 0.0.0.0:4318
      grpc:
        endpoint: 0.0.0.0:4317

processors:
  # Batch for efficiency
  batch:
    timeout: 10s
    send_batch_size: 100
  
  # Add resource attributes
  resource:
    attributes:
      - key: deployment.environment
        value: production
        action: insert
  
  # Filter out debug logs in production
  filter:
    logs:
      exclude:
        match_type: strict
        severity_texts: ['DEBUG', 'DEBUG2']
  
  # Tail-based sampling (keep errors, sample success)
  tail_sampling:
    policies:
      - name: errors-policy
        type: status_code
        status_code:
          status_codes: [ERROR]
      - name: sample-policy
        type: probabilistic
        probabilistic:
          sampling_percentage: 10

exporters:
  # Logs → Loki
  loki:
    endpoint: http://loki:3100/loki/api/v1/push
    labels:
      resource:
        service.name: "service_name"
        deployment.environment: "env"
  
  # Traces → Jaeger
  jaeger:
    endpoint: jaeger:14250
    tls:
      insecure: true
  
  # Metrics → Prometheus
  prometheus:
    endpoint: 0.0.0.0:8889
  
  # Archive: OTel Collector can export to object storage (add exporter config as needed)

service:
  pipelines:
    logs:
      receivers: [otlp]
      processors: [batch, resource, filter]
      exporters: [loki]
    
    traces:
      receivers: [otlp]
      processors: [batch, tail_sampling]
      exporters: [jaeger]
    
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [prometheus]
```

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.adapters[:otel] = E11y::Adapters::OpenTelemetryCollector.new(
    endpoint: 'http://otel-collector:4318',
    service_name: 'my-app'
  )
end

# Now all E11y events flow through OTel Collector!
# Benefits:
# - Centralized routing
# - Tail-based sampling
# - Multiple backends
# - Cost optimization
```

---

### Example 2: Semantic Conventions for HTTP

```ruby
# app/events/http_request.rb
module Events
  class HttpRequest < E11y::Event::Base
    # Enable OTel semantic conventions
    use_otel_conventions :http
    
    schema do
      required(:method).filled(:string)
      required(:route).filled(:string)
      required(:status_code).filled(:integer)
      required(:duration_ms).filled(:float)
      optional(:request_size).filled(:integer)
      optional(:response_size).filled(:integer)
    end
    
    # OTel mapping (automatic!)
    otel_mapping do
      'http.method' from: :method
      'http.route' from: :route
      'http.status_code' from: :status_code
      'http.request.duration_ms' from: :duration_ms
      'http.request.body.size' from: :request_size
      'http.response.body.size' from: :response_size
    end
  end
end

# Usage: Just track the event!
Events::HttpRequest.track(
  method: 'POST',
  route: '/api/orders',
  status_code: 201,
  duration_ms: 45.2,
  request_size: 1024,
  response_size: 512
)

# OTel Collector receives:
# {
#   Attributes: {
#     'http.method': 'POST',
#     'http.route': '/api/orders',
#     'http.status_code': 201,
#     'http.request.duration_ms': 45.2,
#     'http.request.body.size': 1024,
#     'http.response.body.size': 512
#   }
# }

# Grafana query (works with OTel conventions!):
# {http.status_code="201"} | json
```

---

### Example 3: Database Query Events

```ruby
# app/events/database_query.rb
module Events
  class DatabaseQuery < E11y::Event::Base
    use_otel_conventions :database
    
    schema do
      required(:statement).filled(:string)
      required(:duration_ms).filled(:float)
      optional(:rows_affected).filled(:integer)
      optional(:connection_id).filled(:string)
    end
    
    otel_mapping do
      'db.statement' from: :statement
      'db.operation.duration_ms' from: :duration_ms
      'db.operation.rows_affected' from: :rows_affected
      'db.connection.id' from: :connection_id
      'db.system' value: 'postgresql'
      'db.name' from_config: 'database.name'
    end
  end
end

# Usage
Events::DatabaseQuery.track(
  statement: 'SELECT * FROM orders WHERE status = ?',
  duration_ms: 12.5,
  rows_affected: 145
)

# OTel attributes:
# {
#   'db.statement': 'SELECT * FROM orders WHERE status = ?',
#   'db.operation.duration_ms': 12.5,
#   'db.operation.rows_affected': 145,
#   'db.system': 'postgresql',
#   'db.name': 'production_db'
# }
```

---

### Example 4: Automatic Span Creation from Events

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.opentelemetry do
    # Create spans for order processing events
    create_spans_for pattern: 'order.*' do
      span_kind :internal
      span_name ->(event) { event.event_name }
      
      # Span attributes from event payload
      span_attributes do |event|
        {
          'order.id' => event.payload[:order_id],
          'order.amount' => event.payload[:amount],
          'order.status' => event.payload[:status]
        }
      end
      
      # Mark span as error if event severity is error
      mark_error_if ->(event) { event.severity.in?([:error, :fatal]) }
    end
  end
end

# Usage: Track events, get spans automatically!
def process_order(order_id)
  Events::OrderProcessingStarted.track(order_id: order_id)
  
  Events::InventoryChecked.track(
    order_id: order_id,
    items_available: true
  )
  
  Events::PaymentCaptured.track(
    order_id: order_id,
    amount: 99.99
  )
  
  Events::OrderProcessingCompleted.track(
    order_id: order_id,
    severity: :success
  )
end

# Result in Jaeger:
# Trace: abc-123
#   Span: order.processing.started (45ms)
#     Span: inventory.checked (12ms)
#     Span: payment.captured (180ms)
#   Span: order.processing.completed (2ms)
# → Complete distributed trace from E11y events!
```

---

### Example 5: Multi-Backend Routing via OTel Collector

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  # Single adapter: OTel Collector
  config.adapters[:otel] = E11y::Adapters::OpenTelemetryCollector.new(
    endpoint: 'http://otel-collector:4318',
    service_name: 'my-app'
  )

  # OTel Collector handles routing to multiple backends!
  # No need for multiple E11y adapters
end

# OTel Collector routes to:
# - Loki (logs, last 30 days)
# - Jaeger (traces, last 7 days)
# - Object storage (archive, long-term; OTel exporter)
# - Prometheus (metrics via remote write)

# Benefits:
# 1. Single integration point
# 2. Centralized sampling/filtering
# 3. Cost optimization (tail-based sampling)
# 4. Flexible routing (add backends without changing code)
```

---

## 🔧 Configuration

### Full Configuration

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.opentelemetry do
    # === BASIC ===
    enabled true
    
    # === COLLECTOR ===
    collector do
      endpoint ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] || 'http://localhost:4318'
      protocol :http  # :http or :grpc
      
      # Headers (for authentication)
      headers do
        'X-API-Key' ENV['OTEL_API_KEY']
        'X-Tenant-ID' ENV['TENANT_ID']
      end
      
      # TLS
      tls do
        enabled true
        ca_file '/path/to/ca.crt'
        client_cert '/path/to/client.crt'
        client_key '/path/to/client.key'
      end
      
      # Timeout
      timeout connect: 5.seconds, write: 10.seconds, read: 10.seconds
      
      # Retry
      retry_enabled true
      max_retries 3
      retry_backoff initial: 1.second, max: 30.seconds, multiplier: 2
      
      # Compression
      compression :gzip  # :none, :gzip
      
      # Batching
      batch_size 100
      flush_interval 10.seconds
    end
    
    # === SIGNALS ===
    signals do
      # Logs Signal (E11y events → OTel Logs)
      logs do
        enabled true
        include_body true
        include_attributes true
        max_attribute_length 4096
      end
      
      # Traces Signal (E11y events → OTel Spans)
      traces do
        enabled true
        create_spans_for severity: [:error, :warn, :fatal]
        create_spans_for pattern: 'order.*'
        span_kind :internal  # :internal, :server, :client
      end
      
      # Metrics Signal (disabled, use Yabeda instead)
      metrics do
        enabled false  # Yabeda is better for metrics
      end
    end
    
    # === SEMANTIC CONVENTIONS ===
    semantic_conventions do
      enabled true
      
      # HTTP conventions
      http do
        map 'http.method' from: :method
        map 'http.route' from: :path
        map 'http.status_code' from: :status_code
        map 'http.request.duration_ms' from: :duration_ms
      end
      
      # Database conventions
      database do
        map 'db.statement' from: :query
        map 'db.operation.duration_ms' from: :duration_ms
        map 'db.system' value: 'postgresql'
      end
      
      # Custom conventions
      custom do
        map 'business.order.id' from: :order_id
        map 'business.user.segment' from: :user_segment
      end
    end
    
    # === RESOURCE ATTRIBUTES ===
    resource_attributes do
      # Service identification (REQUIRED for OTel!)
      'service.name' ENV['SERVICE_NAME'] || 'api'
      'service.version' ENV['GIT_SHA'] || 'unknown'
      'service.instance.id' ENV['HOSTNAME'] || Socket.gethostname
      
      # Deployment
      'deployment.environment' Rails.env.to_s
      'deployment.region' ENV['AWS_REGION']
      
      # Host
      'host.name' Socket.gethostname
      'host.type' ENV['INSTANCE_TYPE']
      
      # Container (if applicable)
      'container.id' ENV['CONTAINER_ID']
      'container.name' ENV['CONTAINER_NAME']
      
      # Kubernetes (if applicable)
      'k8s.namespace.name' ENV['K8S_NAMESPACE']
      'k8s.pod.name' ENV['K8S_POD_NAME']
      'k8s.deployment.name' ENV['K8S_DEPLOYMENT']
    end
    
    # === TRACE CONTEXT ===
    trace_context do
      # Use OTel SDK for trace context (automatic!)
      source :opentelemetry
      
      # Fallback to E11y trace context if OTel not available
      fallback_to_e11y true
    end
    
    # === SAMPLING ===
    sampling do
      # Parent-based (respect upstream sampling decision)
      parent_based true
      
      # Default sampler
      default_sampler :always_on  # :always_on, :always_off, :trace_id_ratio
      
      # Ratio (if using :trace_id_ratio)
      ratio 0.1  # 10% sampling
    end
  end
end
```

---

## 📊 Benefits of OTel Collector

### 1. Centralized Telemetry Pipeline
```
┌─────────────┐
│   E11y      │─┐
└─────────────┘ │
                │
┌─────────────┐ │    ┌──────────────────┐
│ Rails.logger│─┼───→│  OTel Collector  │─┐
└─────────────┘ │    └──────────────────┘ │
                │                          │
┌─────────────┐ │                          ├─→ Loki (logs)
│  Sidekiq    │─┘                          ├─→ Jaeger (traces)
└─────────────┘                            ├─→ Prometheus (metrics)
                                           ├─→ Object storage (archive)
                                           └─→ Datadog (optional)
```

### 2. Advanced Sampling
- **Tail-based sampling:** Keep all errors, sample success
- **Probabilistic sampling:** 10% of all traffic
- **Rate limiting:** Max 1000 spans/sec
- **Policy-based:** Different policies per service

### 3. Cost Optimization
```ruby
# Without OTel Collector:
# - 100% of events → Loki ($$$)
# - 100% of traces → Jaeger ($$$)

# With OTel Collector:
# - 10% sampled → Loki ($)
# - 100% errors → Loki (important!)
# - Tail sampling → 90% reduction
# → $68k/month → $6.8k/month (90% savings!)
```

### 4. Vendor Flexibility
```yaml
# Easy to switch backends (just reconfigure OTel Collector)
# No code changes needed!

# Day 1: Use Jaeger
exporters:
  jaeger:
    endpoint: jaeger:14250

# Day 30: Switch to Grafana Tempo
exporters:
  otlp/tempo:
    endpoint: tempo:4317

# Day 60: Add Datadog too
exporters:
  jaeger: { ... }
  otlp/tempo: { ... }
  datadog:
    api:
      key: ${DD_API_KEY}
```

---

## 🧪 Testing

```ruby
# spec/support/opentelemetry_helper.rb
RSpec.configure do |config|
  config.before(:suite) do
    # Setup in-memory OTel exporter for testing
    OpenTelemetry::SDK.configure do |c|
      c.service_name = 'test'
      c.add_span_processor(
        OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(
          OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
        )
      )
    end
  end
  
  config.after(:each) do
    # Clear spans after each test
    OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.reset
  end
end

# spec/events/order_created_spec.rb
RSpec.describe Events::OrderCreated do
  it 'creates OTel span' do
    # Track event
    Events::OrderCreated.track(order_id: '123')
    
    # Get recorded spans
    spans = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.get_finished_spans
    
    # Verify span created
    expect(spans.size).to eq(1)
    
    span = spans.first
    expect(span.name).to eq('order.created')
    expect(span.kind).to eq(:internal)
    expect(span.attributes['order.id']).to eq('123')
  end
  
  it 'includes trace context' do
    # Create parent span
    tracer = OpenTelemetry.tracer_provider.tracer('test')
    tracer.in_span('parent') do |parent_span|
      # Track event (should be child span)
      Events::OrderCreated.track(order_id: '123')
      
      spans = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.get_finished_spans
      child_span = spans.find { |s| s.name == 'order.created' }
      
      # Verify parent-child relationship
      expect(child_span.parent_span_id).to eq(parent_span.context.span_id)
      expect(child_span.trace_id).to eq(parent_span.context.trace_id)
    end
  end
end
```

---

## 💡 Best Practices

### ✅ DO

**1. Use OTel Collector in production**
```ruby
# ✅ GOOD: Central pipeline
config.adapters[:otel] = E11y::Adapters::OpenTelemetryCollector.new(
  endpoint: 'http://otel-collector:4318',
  service_name: 'my-app'
)

# OTel Collector handles:
# - Sampling
# - Filtering
# - Routing to multiple backends
# - Cost optimization
```

**2. Use semantic conventions**
```ruby
# ✅ GOOD: Standard field names
module Events
  class HttpRequest < E11y::Event::Base
    use_otel_conventions :http
    
    otel_mapping do
      'http.method' from: :method        # ← Standard!
      'http.status_code' from: :status   # ← Standard!
    end
  end
end
```

**3. Enable trace context integration**
```ruby
# ✅ GOOD: Use OTel SDK trace context
config.trace_context do
  source :opentelemetry  # Automatic correlation!
end
```

---

### ❌ DON'T

**1. Don't bypass OTel Collector**
```ruby
# ❌ BAD: Direct to backends (no sampling, no routing)
config.adapters = [
  E11y::Adapters::JaegerAdapter.new(...),
  E11y::Adapters::LokiAdapter.new(...),
  E11y::Adapters::FileAdapter.new(...)  # Direct to file (bypasses OTel routing)
]

# ✅ GOOD: Through OTel Collector
config.adapters[:otel] = E11y::Adapters::OpenTelemetryCollector.new(
  endpoint: ENV['OTEL_EXPORTER_OTLP_ENDPOINT'],
  service_name: 'my-app'
)
```

**2. Don't use custom field names**
```ruby
# ❌ BAD: Non-standard fields
Events::HttpRequest.track(
  verb: 'POST',        # ← Should be 'method'
  code: 201            # ← Should be 'status_code'
)

# ✅ GOOD: OTel semantic conventions
Events::HttpRequest.track(
  method: 'POST',
  status_code: 201
)
```

---

## 📚 Related Use Cases

- **[UC-006: Trace Context Management](./UC-006-trace-context-management.md)** - W3C Trace Context
- **[UC-007: PII Filtering](./UC-007-pii-filtering.md)** - PII protection (baggage allowlist: C08)
- **[UC-009: Multi-Service Tracing](./UC-009-multi-service-tracing.md)** - Distributed traces
- **[UC-010: Background Job Tracking](./UC-010-background-job-tracking.md)** - Job tracing

---

## 🎯 Summary

### OpenTelemetry Benefits

| Feature | Without OTel | With OTel |
|---------|-------------|-----------|
| **Backend Flexibility** | Locked to E11y adapters | Any OTel-compatible backend |
| **Sampling** | Basic (E11y only) | Advanced (tail-based, policy-based) |
| **Cost** | High (100% events) | Optimized (10-20% sampled) |
| **Routing** | Code changes | Config-only |
| **Standards** | E11y conventions | Industry-standard OTel |
| **Trace Correlation** | Manual | Automatic (W3C) |

**Setup Time:**
- Initial: 30-45 min (OTel Collector + E11y config)
- Per event: 0 min (semantic conventions automatic!)

---

**Document Version:** 1.0  
**Last Updated:** January 12, 2026  
**Status:** ✅ Complete

# ADR-005: Tracing & Context Management

**Status:** Draft  
**Date:** January 12, 2026  
**Covers:** UC-006 (Trace Context Management), UC-009 (Multi-Service Tracing)  
**Depends On:** ADR-001 (Core), ADR-008 (Rails Integration)

---

## 📋 Table of Contents

1. [Context & Problem](#1-context--problem)
2. [Architecture Overview](#2-architecture-overview)
3. [Current (Thread-Local Storage)](#3-current-thread-local-storage)
4. [Trace ID Generation](#4-trace-id-generation)
5. [W3C Trace Context](#5-w3c-trace-context)
6. [Context Propagation](#6-context-propagation)
7. [Sampling Decisions](#7-sampling-decisions)
8. [Context Inheritance](#8-context-inheritance)
9. [Trade-offs](#9-trade-offs)

---

## 1. Context & Problem

### 1.1. Problem Statement

**Current Pain Points:**

1. **No Trace Correlation:**
   ```ruby
   # ❌ Can't correlate events across requests
   Events::OrderCreated.track(order_id: 123)
   # Later in Sidekiq:
   Events::EmailSent.track(order_id: 123)
   # → No way to link these two events
   ```

2. **Lost Context in Background Jobs:**
   ```ruby
   # ❌ User context lost when job executes
   def create
     @current_user = User.find(params[:user_id])
     SendEmailJob.perform_later(order_id: 123)
     # Job has no idea about @current_user
   end
   ```

3. **No Cross-Service Tracing:**
   ```ruby
   # ❌ Can't trace requests across microservices
   response = HTTP.get("https://payment-service/charge")
   # Payment service has no idea this is part of the same trace
   ```

4. **Manual Context Passing:**
   ```ruby
   # ❌ Must manually pass context everywhere
   def process_order(order_id, trace_id:, user_id:, request_id:)
     Events::OrderProcessing.track(
       order_id: order_id,
       trace_id: trace_id,
       user_id: user_id,
       request_id: request_id
     )
   end
   ```

### 1.2. Goals

**Primary Goals:**
- ✅ **Automatic trace ID generation** for every request/job
- ✅ **W3C Trace Context** standard support
- ✅ **Thread-safe context storage** (Rails.current pattern)
- ✅ **Context propagation** to background jobs
- ✅ **Cross-service tracing** via HTTP headers
- ✅ **Sampling consistency** across distributed traces

**Non-Goals:**
- ❌ Full OpenTelemetry SDK (see ADR-007)
- ❌ Automatic span creation (manual spans only)
- ❌ Distributed transactions

### 1.3. Success Metrics

| Metric | Target | Critical? |
|--------|--------|-----------|
| **Context lookup overhead** | <100ns p99 | ✅ Yes |
| **Trace ID collision rate** | <1 in 10^15 | ✅ Yes |
| **Context propagation rate** | >99.9% | ✅ Yes |
| **Cross-service trace coverage** | >95% | ✅ Yes |

---

## 2. Architecture Overview

### 2.1. System Context

```mermaid
C4Context
    title Tracing & Context Management Context
    
    Person(user, "User", "Makes HTTP request")
    
    System(rails_app, "Rails App", "Web application")
    
    System(e11y, "E11y Gem", "Context management")
    
    System_Ext(sidekiq, "Sidekiq", "Background jobs")
    System_Ext(payment_service, "Payment Service", "Microservice")
    System_Ext(frontend, "Frontend", "SPA/Mobile")
    
    Rel(user, frontend, "Uses")
    Rel(frontend, rails_app, "HTTP request", "traceparent header")
    Rel(rails_app, e11y, "Auto trace context", "E11y::Current")
    Rel(e11y, sidekiq, "Propagate context", "Job metadata")
    Rel(rails_app, payment_service, "HTTP request", "traceparent header")
    Rel(payment_service, rails_app, "Uses E11y", "Same trace_id")
```

### 2.2. Component Architecture

```mermaid
graph TB
    subgraph "Request Entry Points"
        HTTPRequest[HTTP Request] --> Middleware[Rack Middleware]
        JobExecution[Job Execution] --> JobMiddleware[Sidekiq/ActiveJob MW]
        ManualAPI[Manual API Call] --> CurrentAPI[E11y::Current.set]
    end
    
    subgraph "Context Storage (Thread-Local)"
        Middleware --> Current[E11y::Current]
        JobMiddleware --> Current
        CurrentAPI --> Current
        
        Current --> TraceID[trace_id]
        Current --> SpanID[span_id]
        Current --> ParentSpanID[parent_span_id]
        Current --> UserID[user_id]
        Current --> RequestID[request_id]
        Current --> Sampled[sampled]
        Current --> Baggage[baggage]
    end
    
    subgraph "Trace ID Management"
        Current --> TraceGenerator[Trace ID Generator]
        TraceGenerator --> W3CParser[W3C Trace Context Parser]
        TraceGenerator --> UUIDGen[UUID Generator]
    end
    
    subgraph "Context Propagation"
        Current --> HTTPPropagator[HTTP Header Propagator]
        Current --> JobPropagator[Job Metadata Propagator]
        Current --> LogPropagator[Structured Log Propagator]
    end
    
    subgraph "Event Pipeline"
        Current --> EventTracking[Event Tracking]
        EventTracking --> EnrichWithContext[Auto-enrich with Context]
    end
    
    style Current fill:#d1ecf1
    style TraceGenerator fill:#fff3cd
    style HTTPPropagator fill:#d4edda
```

### 2.3. Context Lifecycle

```mermaid
sequenceDiagram
    participant Browser as Browser
    participant Rack as Rack Middleware
    participant Current as E11y::Current
    participant Controller as Rails Controller
    participant Sidekiq as Sidekiq Job
    participant Event as Event Tracking
    
    Note over Browser: User makes request
    Browser->>Rack: GET /orders<br/>traceparent: 00-abc123...
    
    Rack->>Current: Extract or generate trace_id
    Current->>Current: Store in thread-local
    
    Note over Current: trace_id: abc123<br/>span_id: def456<br/>user_id: 42
    
    Rack->>Controller: Process request
    
    Controller->>Event: Track event
    Event->>Current: Read context
    Current-->>Event: Return trace_id, user_id, etc
    Event->>Event: Enrich event with context
    
    Controller->>Sidekiq: Enqueue job
    Sidekiq->>Current: Read trace_id
    Current-->>Sidekiq: abc123
    Sidekiq->>Sidekiq: Store in job metadata
    
    Note over Sidekiq: Later... job executes
    
    Sidekiq->>Current: Restore trace_id from metadata
    Current->>Current: Store in NEW thread-local
    
    Note over Current: Same trace_id: abc123<br/>New span_id: ghi789<br/>parent_span_id: def456
    
    Sidekiq->>Event: Track job event
    Event->>Current: Read context
    Current-->>Event: Same trace_id!
    
    Rack->>Current: Reset context
    Current->>Current: Clear thread-local
```

---

## 3. Current (Thread-Local Storage)

### 3.1. E11y::Current Implementation

**Design Decision:** Use `ActiveSupport::CurrentAttributes` for thread-safe storage.

```ruby
# lib/e11y/current.rb
module E11y
  class Current < ActiveSupport::CurrentAttributes
    # Core trace attributes
    attribute :trace_id
    attribute :span_id
    attribute :parent_span_id
    
    # Request/job attributes
    attribute :request_id
    attribute :job_id
    attribute :job_class
    
    # User/tenant attributes
    attribute :user_id
    attribute :tenant_id
    attribute :organization_id
    
    # Sampling decision
    attribute :sampled
    
    # Custom baggage (key-value pairs)
    attribute :baggage
    
    # IP and user agent (for security/audit)
    attribute :ip_address
    attribute :user_agent
    
    # Delegation methods for convenience
    class << self
      # Set multiple attributes at once
      def set(attributes = {})
        attributes.each do |key, value|
          public_send(:"#{key}=", value)
        end
      end
      
      # Get all current attributes as hash
      def to_h
        {
          trace_id: trace_id,
          span_id: span_id,
          parent_span_id: parent_span_id,
          request_id: request_id,
          job_id: job_id,
          job_class: job_class,
          user_id: user_id,
          tenant_id: tenant_id,
          organization_id: organization_id,
          sampled: sampled,
          baggage: baggage,
          ip_address: ip_address,
          user_agent: user_agent
        }.compact
      end
      
      # Check if we're in a traced context
      def traced?
        trace_id.present?
      end
      
      # Create a new span (child of current span)
      def create_span(name)
        new_span_id = E11y::TraceContext.generate_span_id
        
        span = Span.new(
          trace_id: trace_id || E11y::TraceContext.generate_id,
          span_id: new_span_id,
          parent_span_id: span_id,
          name: name,
          started_at: Time.now
        )
        
        # Update current span_id
        self.span_id = new_span_id
        
        span
      end
      
      # Add baggage (key-value metadata)
      def add_baggage(key, value)
        self.baggage ||= {}
        self.baggage[key.to_s] = value.to_s
      end
      
      # Get baggage value
      def get_baggage(key)
        baggage&.[](key.to_s)
      end
    end
    
    # Span helper class
    class Span
      attr_reader :trace_id, :span_id, :parent_span_id, :name, :started_at
      attr_accessor :finished_at, :status, :attributes
      
      def initialize(trace_id:, span_id:, parent_span_id:, name:, started_at:)
        @trace_id = trace_id
        @span_id = span_id
        @parent_span_id = parent_span_id
        @name = name
        @started_at = started_at
        @attributes = {}
      end
      
      def finish(status: :ok)
        @finished_at = Time.now
        @status = status
        
        duration = (@finished_at - @started_at) * 1000  # ms
        
        # Track span as event
        Events::Span.track(
          span_name: @name,
          trace_id: @trace_id,
          span_id: @span_id,
          parent_span_id: @parent_span_id,
          duration: duration,
          status: status,
          attributes: @attributes
        )
        
        self
      end
      
      def add_attribute(key, value)
        @attributes[key] = value
      end
    end
  end
end
```

### 3.2. Usage Examples

```ruby
# Read current context
E11y::Current.trace_id  # => "abc123..."
E11y::Current.user_id   # => 42

# Set context manually
E11y::Current.set(
  trace_id: 'custom-trace-123',
  user_id: 99,
  tenant_id: 'acme-corp'
)

# Check if traced
if E11y::Current.traced?
  puts "We're in a trace!"
end

# Get all context
E11y::Current.to_h
# => { trace_id: "abc...", user_id: 42, ... }

# Create a manual span
span = E11y::Current.create_span('database_query')
span.add_attribute('table', 'orders')
# ... do work ...
span.finish(status: :ok)

# Baggage (propagated metadata)
E11y::Current.add_baggage('experiment_id', 'exp-42')
E11y::Current.get_baggage('experiment_id')  # => "exp-42"
```

---

## 4. Trace ID Generation

### 4.1. Trace ID Generator

```ruby
# lib/e11y/trace_context/id_generator.rb
module E11y
  module TraceContext
    module IDGenerator
      # W3C Trace Context format:
      # trace-id: 32 hex chars (128 bits)
      # span-id: 16 hex chars (64 bits)
      
      # Generate trace ID (128 bits = 16 bytes)
      def self.generate_trace_id
        SecureRandom.hex(16)  # 32 hex chars
      end
      
      # Generate span ID (64 bits = 8 bytes)
      def self.generate_span_id
        SecureRandom.hex(8)   # 16 hex chars
      end
      
      # Validate trace ID format
      def self.valid_trace_id?(trace_id)
        trace_id.is_a?(String) &&
          trace_id.match?(/\A[0-9a-f]{32}\z/) &&
          trace_id != '00000000000000000000000000000000'  # Not all zeros
      end
      
      # Validate span ID format
      def self.valid_span_id?(span_id)
        span_id.is_a?(String) &&
          span_id.match?(/\A[0-9a-f]{16}\z/) &&
          span_id != '0000000000000000'  # Not all zeros
      end
      
      # Convert UUID to trace ID (for compatibility)
      def self.uuid_to_trace_id(uuid)
        uuid.delete('-').downcase
      end
    end
    
    # Convenience methods
    def self.generate_id
      IDGenerator.generate_trace_id
    end
    
    def self.generate_span_id
      IDGenerator.generate_span_id
    end
  end
end
```

---

## 5. W3C Trace Context

### 5.1. W3C Trace Context Standard

**Format:** `traceparent: 00-{trace-id}-{parent-id}-{trace-flags}`

**Example:** `traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01`

- `00` = version
- `0af7651916cd43dd8448eb211c80319c` = trace-id (32 hex chars)
- `b7ad6b7169203331` = parent-id (16 hex chars)
- `01` = trace-flags (01 = sampled)

### 5.2. W3C Parser & Generator

```ruby
# lib/e11y/trace_context/w3c.rb
module E11y
  module TraceContext
    module W3C
      VERSION = '00'
      
      # Parse W3C traceparent header
      def self.parse_traceparent(header)
        return nil unless header.is_a?(String)
        
        parts = header.split('-')
        return nil unless parts.size == 4
        
        version, trace_id, parent_id, flags = parts
        
        # Validate format
        return nil unless version == VERSION
        return nil unless IDGenerator.valid_trace_id?(trace_id)
        return nil unless IDGenerator.valid_span_id?(parent_id)
        
        sampled = (flags.to_i(16) & 0x01) == 1
        
        {
          version: version,
          trace_id: trace_id,
          parent_span_id: parent_id,
          sampled: sampled,
          flags: flags
        }
      end
      
      # Generate W3C traceparent header
      def self.generate_traceparent(trace_id:, span_id:, sampled: true)
        flags = sampled ? '01' : '00'
        
        "#{VERSION}-#{trace_id}-#{span_id}-#{flags}"
      end
      
      # Parse W3C tracestate header (optional)
      def self.parse_tracestate(header)
        return {} unless header.is_a?(String)
        
        header.split(',').each_with_object({}) do |entry, hash|
          key, value = entry.split('=', 2)
          hash[key.strip] = value.strip if key && value
        end
      end
      
      # Generate W3C tracestate header
      def self.generate_tracestate(state_hash)
        state_hash.map { |k, v| "#{k}=#{v}" }.join(',')
      end
    end
  end
end
```

### 5.3. HTTP Header Extraction

```ruby
# lib/e11y/trace_context/http_extractor.rb
module E11y
  module TraceContext
    class HTTPExtractor
      TRACEPARENT_HEADER = 'HTTP_TRACEPARENT'
      TRACESTATE_HEADER = 'HTTP_TRACESTATE'
      
      # Legacy headers (fallback)
      X_REQUEST_ID = 'HTTP_X_REQUEST_ID'
      X_TRACE_ID = 'HTTP_X_TRACE_ID'
      X_CORRELATION_ID = 'HTTP_X_CORRELATION_ID'
      
      def self.extract(env)
        # Try W3C Trace Context first
        if env[TRACEPARENT_HEADER]
          extract_w3c(env)
        # Fallback to legacy headers
        elsif env[X_TRACE_ID]
          extract_legacy(env)
        else
          # No trace context → generate new
          generate_new
        end
      end
      
      private
      
      def self.extract_w3c(env)
        context = W3C.parse_traceparent(env[TRACEPARENT_HEADER])
        return generate_new unless context
        
        tracestate = W3C.parse_tracestate(env[TRACESTATE_HEADER])
        
        {
          trace_id: context[:trace_id],
          parent_span_id: context[:parent_span_id],
          span_id: IDGenerator.generate_span_id,  # New span for this service
          sampled: context[:sampled],
          tracestate: tracestate,
          format: :w3c
        }
      end
      
      def self.extract_legacy(env)
        trace_id = env[X_TRACE_ID] ||
                   env[X_REQUEST_ID] ||
                   env[X_CORRELATION_ID]
        
        # Convert to W3C format if needed
        trace_id = normalize_trace_id(trace_id)
        
        {
          trace_id: trace_id,
          span_id: IDGenerator.generate_span_id,
          sampled: true,  # Assume sampled for legacy
          format: :legacy
        }
      end
      
      def self.generate_new
        {
          trace_id: IDGenerator.generate_trace_id,
          span_id: IDGenerator.generate_span_id,
          sampled: true,
          format: :new
        }
      end
      
      def self.normalize_trace_id(trace_id)
        # If UUID format, convert to W3C
        if trace_id.include?('-') && trace_id.length == 36
          IDGenerator.uuid_to_trace_id(trace_id)
        # If already 32 hex chars, use as-is
        elsif trace_id.match?(/\A[0-9a-f]{32}\z/i)
          trace_id.downcase
        # Otherwise, hash it to 32 hex chars
        else
          Digest::SHA256.hexdigest(trace_id)[0...32]
        end
      end
    end
  end
end
```

---

## 6. Context Propagation

### 6.1. HTTP Propagator (Outgoing Requests)

```ruby
# lib/e11y/trace_context/http_propagator.rb
module E11y
  module TraceContext
    class HTTPPropagator
      # Inject trace context into HTTP headers
      def self.inject(headers = {})
        return headers unless E11y::Current.traced?
        
        trace_id = E11y::Current.trace_id
        span_id = E11y::Current.span_id
        sampled = E11y::Current.sampled
        
        # W3C Trace Context
        headers['traceparent'] = W3C.generate_traceparent(
          trace_id: trace_id,
          span_id: span_id,
          sampled: sampled
        )
        
        # Add tracestate if baggage present
        if E11y::Current.baggage&.any?
          headers['tracestate'] = W3C.generate_tracestate(
            E11y::Current.baggage
          )
        end
        
        # Legacy headers (for backwards compatibility)
        headers['X-Request-ID'] = E11y::Current.request_id if E11y::Current.request_id
        headers['X-Trace-ID'] = trace_id
        
        headers
      end
      
      # Helper for common HTTP clients
      def self.wrap_faraday(conn)
        conn.use :instrumentation do |faraday|
          faraday.request :headers do |req|
            inject(req.headers)
          end
        end
      end
      
      def self.wrap_http_rb(http)
        headers = inject
        headers.each { |k, v| http = http.headers(k => v) }
        http
      end
    end
  end
end
```

### 6.2. Job Propagator (Sidekiq/ActiveJob)

Already implemented in ADR-008, but here's the core logic:

```ruby
# lib/e11y/trace_context/job_propagator.rb
module E11y
  module TraceContext
    class JobPropagator
      # Inject trace context into job metadata
      def self.inject(job_metadata = {})
        return job_metadata unless E11y::Current.traced?
        
        job_metadata['e11y_trace_id'] = E11y::Current.trace_id
        job_metadata['e11y_span_id'] = E11y::Current.span_id
        job_metadata['e11y_sampled'] = E11y::Current.sampled
        
        # Propagate baggage
        if E11y::Current.baggage&.any?
          job_metadata['e11y_baggage'] = E11y::Current.baggage
        end
        
        # Propagate user/tenant context
        job_metadata['e11y_user_id'] = E11y::Current.user_id if E11y::Current.user_id
        job_metadata['e11y_tenant_id'] = E11y::Current.tenant_id if E11y::Current.tenant_id
        
        job_metadata
      end
      
      # Extract trace context from job metadata
      def self.extract(job_metadata)
        return {} unless job_metadata['e11y_trace_id']
        
        {
          trace_id: job_metadata['e11y_trace_id'],
          parent_span_id: job_metadata['e11y_span_id'],
          span_id: IDGenerator.generate_span_id,  # New span for job
          sampled: job_metadata['e11y_sampled'],
          baggage: job_metadata['e11y_baggage'],
          user_id: job_metadata['e11y_user_id'],
          tenant_id: job_metadata['e11y_tenant_id']
        }
      end
    end
  end
end
```

### 6.3. Structured Log Propagator

```ruby
# lib/e11y/trace_context/log_propagator.rb
module E11y
  module TraceContext
    class LogPropagator
      # Add trace context to structured log entry
      def self.inject(log_entry = {})
        return log_entry unless E11y::Current.traced?
        
        log_entry.merge(
          trace_id: E11y::Current.trace_id,
          span_id: E11y::Current.span_id,
          parent_span_id: E11y::Current.parent_span_id,
          user_id: E11y::Current.user_id,
          tenant_id: E11y::Current.tenant_id
        ).compact
      end
    end
  end
end
```

---

## 7. Sampling Decisions

### 7.1. Trace-Consistent Sampling

**Design Decision:** Sampling decision is made at trace entry point and propagated.

```ruby
# lib/e11y/trace_context/sampler.rb
module E11y
  module TraceContext
    class Sampler
      def initialize(config)
        @default_rate = config.default_sample_rate
        @per_event_rates = config.per_event_sample_rates
      end
      
      # Decide if this trace should be sampled
      def should_sample?(context = {})
        # If sampling decision already made (from parent), respect it
        return context[:sampled] if context.key?(:sampled)
        
        # Apply sampling rules
        sample_rate = determine_sample_rate(context)
        
        # Random sampling
        rand < sample_rate
      end
      
      private
      
      def determine_sample_rate(context)
        # Priority 1: Always sample errors
        return 1.0 if context[:error]
        
        # Priority 2: Per-event sampling
        if context[:event_name]
          rate = @per_event_rates[context[:event_name]]
          return rate if rate
        end
        
        # Priority 3: Per-user sampling (for debugging)
        if context[:user_id] && debug_user?(context[:user_id])
          return 1.0
        end
        
        # Default sampling rate
        @default_rate
      end
      
      def debug_user?(user_id)
        # Check if user is in debug mode (e.g., via feature flag)
        E11y.config.debug_users.include?(user_id)
      end
    end
  end
end
```

### 7.2. Sampling Configuration

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.tracing do
    # Default sample rate (10% of traces)
    default_sample_rate 0.1
    
    # Per-event sampling
    per_event_sample_rates do
      event 'payment.processed', sample_rate: 1.0   # Always sample
      event 'order.created', sample_rate: 0.5       # 50%
      event 'health_check', sample_rate: 0.01       # 1%
    end
    
    # Always sample for debug users
    debug_users [123, 456]  # User IDs
    
    # Respect parent sampling decision
    respect_parent_sampling true  # Default: true
  end
end
```

---

## 8. Context Inheritance

### 8.1. Context Inheritance Patterns

```ruby
# lib/e11y/trace_context/inheritance.rb
module E11y
  module TraceContext
    module Inheritance
      # Execute block with inherited context
      def self.with_inherited_context(parent_context, &block)
        previous_context = E11y::Current.attributes
        
        begin
          # Inherit from parent, but create new span
          E11y::Current.set(
            trace_id: parent_context[:trace_id],
            parent_span_id: parent_context[:span_id],
            span_id: IDGenerator.generate_span_id,
            sampled: parent_context[:sampled],
            baggage: parent_context[:baggage]&.dup,
            user_id: parent_context[:user_id],
            tenant_id: parent_context[:tenant_id]
          )
          
          yield
        ensure
          E11y::Current.set(previous_context)
        end
      end
      
      # Fork context for parallel execution (e.g., Thread, Fiber)
      def self.fork_context(&block)
        parent_context = E11y::Current.to_h
        
        Thread.new do
          with_inherited_context(parent_context, &block)
        end
      end
    end
  end
end
```

### 8.2. Usage Examples

```ruby
# Execute with inherited context
parent_context = E11y::Current.to_h

E11y::TraceContext::Inheritance.with_inherited_context(parent_context) do
  # This block runs with parent's trace_id but new span_id
  Events::ChildTask.track(task_id: 42)
end

# Fork context for parallel execution
threads = 5.times.map do |i|
  E11y::TraceContext::Inheritance.fork_context do
    # Each thread gets its own span but shares trace_id
    Events::ParallelTask.track(index: i)
  end
end

threads.each(&:join)
```

---

## 9. Trade-offs

### 9.1. Key Decisions

| Decision | Pro | Con | Rationale |
|----------|-----|-----|-----------|
| **ActiveSupport::CurrentAttributes** | Rails-native, thread-safe | Rails dependency | Perfect fit for Rails 8+ |
| **W3C Trace Context** | Industry standard | More complex than UUID | Future-proof, interop |
| **128-bit trace ID** | No collisions | Longer strings | W3C requirement |
| **Trace-consistent sampling** | Distributed traces work | Complex propagation | Critical for multi-service |
| **Auto-enrich events** | Zero boilerplate | Implicit behavior | DX > explicit |
| **Baggage propagation** | Flexible metadata | Size overhead | Limited use, opt-in |
| **Manual spans** | Simple | Less automation | v1.0 scope |

### 9.2. Alternatives Considered

**A) Global variables for context**
- ❌ Rejected: Not thread-safe

**B) OpenTelemetry SDK**
- ❌ Rejected for v1.0: Too heavy, see ADR-007

**C) UUID v4 for trace ID**
- ❌ Rejected: Not W3C compliant

**D) Automatic span creation**
- ❌ Rejected for v1.0: Complexity, performance

**E) Context stored in Database**
- ❌ Rejected: Too slow, high overhead

---

## 10. Configuration Reference

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.tracing do
    # Enable tracing
    enabled true
    
    # Trace ID generation
    id_generator :secure_random  # or :uuid, :custom
    
    # W3C Trace Context
    w3c_trace_context do
      enabled true
      version '00'
      
      # Legacy header support (fallback)
      support_legacy_headers true
      legacy_headers ['X-Request-ID', 'X-Trace-ID', 'X-Correlation-ID']
    end
    
    # Sampling
    sampling do
      default_sample_rate 0.1
      
      per_event_sample_rates do
        event 'payment.*', sample_rate: 1.0
        event 'health_check', sample_rate: 0.01
      end
      
      debug_users [123, 456]
      respect_parent_sampling true
    end
    
    # Context propagation
    propagation do
      # HTTP outgoing requests
      http do
        enabled true
        inject_headers ['traceparent', 'tracestate', 'X-Request-ID']
      end
      
      # Background jobs
      jobs do
        enabled true
        propagate_baggage true
        propagate_user_context true
      end
      
      # Structured logs
      logs do
        enabled true
        fields [:trace_id, :span_id, :user_id]
      end
    end
    
    # Baggage (optional metadata)
    baggage do
      enabled true
      max_size 1024  # bytes
      max_entries 10
    end
  end
end
```

---

**Status:** ✅ Draft Complete  
**Next:** ADR-011 (Testing Strategy) or ADR-012 (Event Evolution)  
**Estimated Implementation:** 2 weeks

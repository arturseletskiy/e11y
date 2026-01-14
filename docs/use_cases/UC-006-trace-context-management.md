# UC-006: Trace Context Management

**Status:** MVP Feature  
**Complexity:** Intermediate  
**Setup Time:** 15 minutes  
**Target Users:** Backend Developers, SRE, DevOps

---

## 📋 Overview

### Problem Statement

**Current Approach (Disconnected Logs):**
```ruby
# Request 1:
Rails.logger.info "Order created: 123"
Rails.logger.info "Payment processed: $99"

# Request 2:
Rails.logger.info "Order created: 456"

# Request 1:
Rails.logger.info "Email sent for order 123"

# Problem: Can't tell which logs belong to same request!
# All logs are mixed together chronologically
```

### E11y Solution

**Automatic trace correlation:**
```ruby
# Request 1 (trace_id: abc-123)
Events::OrderCreated.track(order_id: '123')
# → { trace_id: 'abc-123', event: 'order.created' }

Events::PaymentProcessed.track(order_id: '123', amount: 99)
# → { trace_id: 'abc-123', event: 'payment.processed' }

# Request 2 (trace_id: def-456)
Events::OrderCreated.track(order_id: '456')
# → { trace_id: 'def-456', event: 'order.created' }

# Request 1 background job (trace_id: abc-123 - PRESERVED!)
Events::EmailSent.track(order_id: '123')
# → { trace_id: 'abc-123', event: 'email.sent' }

# In Grafana/Loki:
# {trace_id="abc-123"} → Shows COMPLETE request timeline across services
```

---

## 🎯 Features

### 1. Automatic Trace ID Propagation

**Rails Request Integration:**
```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  # Auto-extract trace_id from various sources
  config.trace_id do
    # Priority order (first found wins):
    
    # 1. Rails request ID (default)
    from_rails_request_id true
    
    # 2. HTTP headers (OpenTelemetry / W3C Trace Context)
    from_http_headers ['traceparent', 'X-Request-ID', 'X-Trace-ID']
    
    # 3. Current.request_id (Rails CurrentAttributes)
    from_current_attributes :request_id
    
    # 4. Thread local (for background jobs)
    from_thread_local :trace_id
    
    # 5. Generate new if none found
    generator -> { SecureRandom.uuid }
  end
end
```

**How it works:**
```ruby
# In controller, trace_id automatically extracted
class OrdersController < ApplicationController
  def create
    # E11y automatically uses request.uuid as trace_id
    Events::OrderCreated.track(order_id: params[:id])
    # → trace_id = request.uuid (e.g., "abc-123-def")
    
    # All events in this request share same trace_id
    Events::PaymentProcessed.track(order_id: params[:id], amount: 99)
    # → trace_id = "abc-123-def" (same!)
  end
end
```

---

### 2. Background Job Propagation

**Problem:** Background jobs lose trace_id context

**Solution:** Automatic propagation via Sidekiq middleware

```ruby
# lib/e11y/integrations/sidekiq.rb (built-in)
module E11y
  module Integrations
    class SidekiqMiddleware
      def call(worker, job, queue)
        # Extract trace_id from job payload
        trace_id = job['trace_id']
        
        # Set thread-local trace_id
        E11y::TraceId.with_trace_id(trace_id) do
          yield  # Execute job
        end
      end
    end
  end
end

# Sidekiq configuration (auto-configured by E11y)
Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add E11y::Integrations::SidekiqMiddleware
  end
end

Sidekiq.configure_client do |config|
  config.client_middleware do |chain|
    chain.add E11y::Integrations::SidekiqClientMiddleware
  end
end
```

**Usage (automatic!):**
```ruby
# In controller (trace_id: abc-123)
class OrdersController < ApplicationController
  def create
    order = Order.create!(params)
    
    # Enqueue job (trace_id automatically passed)
    SendOrderConfirmationJob.perform_later(order.id)
    # → Job payload includes: { 'trace_id' => 'abc-123' }
    
    render json: order
  end
end

# In job (trace_id: abc-123 - PRESERVED!)
class SendOrderConfirmationJob < ApplicationJob
  def perform(order_id)
    order = Order.find(order_id)
    
    # trace_id is automatically restored!
    Events::EmailSending.track(order_id: order.id)
    # → trace_id = 'abc-123' (same as original request!)
    
    UserMailer.order_confirmation(order).deliver_now
    
    Events::EmailSent.track(order_id: order.id)
    # → trace_id = 'abc-123' (still same!)
  end
end

# Timeline in Grafana:
# 10:00:00.000 [abc-123] order.created (controller)
# 10:00:00.050 [abc-123] payment.processed (controller)
# 10:00:00.100 [abc-123] email.sending (job, 3 seconds later)
# 10:00:03.200 [abc-123] email.sent (job)
# → Complete trace across HTTP request + background job!
```

---

### 3. Cross-Service Propagation

**Microservices scenario:**
```ruby
# Service A: API Gateway
class OrdersController < ApplicationController
  def create
    # trace_id: abc-123 (from HTTP request)
    Events::OrderReceived.track(order_id: params[:id])
    
    # Call Service B (Payment Service)
    response = HTTP
      .headers('X-Trace-ID' => E11y::TraceId.current)  # Propagate!
      .post('http://payment-service/process', json: { order_id: params[:id] })
    
    Events::OrderCreated.track(order_id: params[:id])
    render json: { status: 'ok' }
  end
end

# Service B: Payment Service
class PaymentsController < ApplicationController
  def process
    # trace_id: abc-123 (extracted from X-Trace-ID header!)
    Events::PaymentProcessing.track(order_id: params[:order_id])
    
    # Process payment...
    
    Events::PaymentSucceeded.track(order_id: params[:order_id])
    render json: { status: 'paid' }
  end
end

# Timeline in Grafana:
# Service A:
# 10:00:00.000 [abc-123] order.received
# 10:00:00.200 [abc-123] order.created
#
# Service B:
# 10:00:00.050 [abc-123] payment.processing  ← Same trace_id!
# 10:00:00.150 [abc-123] payment.succeeded   ← Same trace_id!
#
# → Complete distributed trace across 2 services!
```

---

### 4. OpenTelemetry Integration

**W3C Trace Context support:**
```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.trace_id do
    # Parse W3C traceparent header
    # Format: 00-{trace_id}-{span_id}-{flags}
    # Example: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
    
    from_http_headers ['traceparent']
    parser :w3c_trace_context  # Built-in parser
  end
end

# Automatic parsing:
# HTTP Header: traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
# E11y extracts: trace_id = "4bf92f3577b34da6a3ce929d0e0e4736"
```

**Span creation (optional):**
```ruby
# Create OpenTelemetry span from E11y event
Events::PaymentProcessed.track(
  order_id: '123',
  amount: 99,
  create_span: true  # ← Creates OTel span
) do
  process_payment  # Span duration measured
end

# Result:
# - E11y event with duration_ms
# - OpenTelemetry span with same trace_id
# - Automatic parent-child span relationship
```

---

### 5. Manual Trace Management

**Override trace_id:**
```ruby
# Sometimes you want to use custom trace_id
E11y::TraceId.with_trace_id('custom-trace-123') do
  Events::OrderCreated.track(order_id: '456')
  # → trace_id = 'custom-trace-123'
  
  Events::PaymentProcessed.track(order_id: '456', amount: 99)
  # → trace_id = 'custom-trace-123'
end

# Outside block, trace_id reverts to original
Events::UserLoggedIn.track(user_id: '789')
# → trace_id = original request trace_id
```

**Explicit trace_id:**
```ruby
# Override for single event
Events::OrderCreated.track(
  order_id: '123',
  trace_id: 'explicit-trace-456'  # ← Explicit override
)
# → trace_id = 'explicit-trace-456'

# Next event reverts to automatic
Events::PaymentProcessed.track(order_id: '123', amount: 99)
# → trace_id = automatic (from request)
```

---

## 💻 Implementation Examples

### Example 1: Complete Request Timeline

```ruby
# app/controllers/orders_controller.rb
class OrdersController < ApplicationController
  def create
    # 1. Validate input
    Events::OrderValidationStarted.track(params: sanitized_params)
    
    begin
      validate_order_params!
      Events::OrderValidationSucceeded.track
    rescue ValidationError => e
      Events::OrderValidationFailed.track(error: e.message, severity: :error)
      return render json: { error: e.message }, status: :unprocessable_entity
    end
    
    # 2. Create order
    order = Order.create!(order_params)
    Events::OrderCreated.track(order_id: order.id, amount: order.total)
    
    # 3. Process payment
    Events::PaymentProcessing.track(order_id: order.id, amount: order.total)
    
    begin
      payment = PaymentService.charge(order)
      Events::PaymentSucceeded.track(
        order_id: order.id,
        transaction_id: payment.id,
        severity: :success
      )
    rescue PaymentError => e
      Events::PaymentFailed.track(
        order_id: order.id,
        error: e.message,
        severity: :error
      )
      raise
    end
    
    # 4. Enqueue background jobs
    SendOrderConfirmationJob.perform_later(order.id)
    UpdateInventoryJob.perform_later(order.id)
    
    Events::OrderCompleted.track(order_id: order.id, severity: :success)
    
    render json: order
  end
end

# Grafana query: {trace_id="abc-123"}
# Result:
# 10:00:00.000 order.validation.started
# 10:00:00.010 order.validation.succeeded
# 10:00:00.020 order.created
# 10:00:00.030 payment.processing
# 10:00:00.150 payment.succeeded
# 10:00:00.160 order.completed
# 10:00:02.000 email.sending (background job)
# 10:00:03.500 email.sent (background job)
# 10:00:04.000 inventory.updated (background job)
```

---

### Example 2: Distributed Trace Across Services

```ruby
# Service A: API Gateway
class OrdersController < ApplicationController
  def create
    trace_id = E11y::TraceId.current  # abc-123
    
    Events::OrderReceived.track(order_id: params[:id])
    
    # Call Payment Service (with trace propagation)
    payment_response = call_payment_service(trace_id, params)
    
    # Call Inventory Service (with trace propagation)
    inventory_response = call_inventory_service(trace_id, params)
    
    Events::OrderCreated.track(order_id: params[:id])
    
    render json: { status: 'ok' }
  end
  
  private
  
  def call_payment_service(trace_id, params)
    HTTP
      .headers('X-Trace-ID' => trace_id)
      .post('http://payment-service/charge', json: params)
  end
  
  def call_inventory_service(trace_id, params)
    HTTP
      .headers('X-Trace-ID' => trace_id)
      .post('http://inventory-service/reserve', json: params)
  end
end

# Service B: Payment Service
class PaymentsController < ApplicationController
  def charge
    # trace_id automatically extracted from X-Trace-ID header
    Events::PaymentReceived.track(amount: params[:amount])
    
    # Process payment...
    
    Events::PaymentCharged.track(
      transaction_id: transaction.id,
      amount: params[:amount],
      severity: :success
    )
    
    render json: { status: 'charged' }
  end
end

# Service C: Inventory Service
class InventoryController < ApplicationController
  def reserve
    # trace_id automatically extracted from X-Trace-ID header
    Events::InventoryReserveRequested.track(items: params[:items])
    
    # Reserve inventory...
    
    Events::InventoryReserved.track(
      items: params[:items],
      severity: :success
    )
    
    render json: { status: 'reserved' }
  end
end

# Timeline in Grafana: {trace_id="abc-123"}
# 10:00:00.000 [api-gateway] order.received
# 10:00:00.010 [payment-service] payment.received
# 10:00:00.015 [inventory-service] inventory.reserve.requested
# 10:00:00.100 [payment-service] payment.charged
# 10:00:00.120 [inventory-service] inventory.reserved
# 10:00:00.150 [api-gateway] order.created
# → Complete distributed trace!
```

---

### Example 3: Nested Trace Contexts

```ruby
# Sometimes you need to track sub-operations separately
class BulkOrderProcessor
  def process(orders)
    # Parent trace_id from current request
    parent_trace_id = E11y::TraceId.current
    
    Events::BulkProcessingStarted.track(
      order_count: orders.count,
      trace_id: parent_trace_id
    )
    
    orders.each do |order|
      # Create child trace for each order
      child_trace_id = "#{parent_trace_id}-order-#{order.id}"
      
      E11y::TraceId.with_trace_id(child_trace_id) do
        Events::OrderProcessing.track(order_id: order.id)
        
        process_single_order(order)
        
        Events::OrderProcessed.track(order_id: order.id, severity: :success)
      end
    end
    
    # Back to parent trace
    Events::BulkProcessingCompleted.track(
      order_count: orders.count,
      trace_id: parent_trace_id,
      severity: :success
    )
  end
end

# Timeline:
# [parent-123] bulk.processing.started (order_count: 3)
# [parent-123-order-1] order.processing
# [parent-123-order-1] order.processed
# [parent-123-order-2] order.processing
# [parent-123-order-2] order.processed
# [parent-123-order-3] order.processing
# [parent-123-order-3] order.processed
# [parent-123] bulk.processing.completed
```

---

### 6. Trace-Consistent Sampling Integration

**Critical Feature:** Sampling decisions must be consistent across trace boundaries

**See:** [UC-014: Adaptive Sampling - Strategy 7: Trace-Consistent Sampling](./UC-014-adaptive-sampling.md#strategy-7-trace-consistent-sampling)

**Why it matters:**

```ruby
# ❌ PROBLEM: Inconsistent sampling breaks distributed traces
# 
# HTTP request (trace_id: abc-123):
# → Sampled at 10% → NOT sampled
# 
# Background job (trace_id: abc-123):
# → Sampled at 10% independently → MAYBE sampled
# 
# RESULT: Job event exists, but parent HTTP event is missing!
# → Can't understand context (orphaned event)
```

**Solution:** Propagate sample decision with trace_id

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.trace_id do
    # Enable trace context propagation
    from_rails_request_id true
    from_http_headers ['traceparent', 'X-Trace-ID']
    
    # ✅ CRITICAL: Propagate sample decision
    propagate_sample_decision true
    
    # Include in outbound HTTP requests
    propagate_via_headers [
      'X-Trace-ID',        # Trace ID
      'X-E11y-Sampled'     # Sample decision (true/false)
    ]
  end
  
  config.adaptive_sampling do
    # Enable trace-consistent sampling
    trace_consistent do
      enabled true
      propagate_decision true
      sample_decision_key 'e11y_sampled'  # Metadata key for jobs
      
      # Sample entire trace if ANY event is error
      sample_on_error true
    end
  end
end
```

**How trace context + sampling work together:**

```ruby
# === HTTP REQUEST (trace_id: abc-123) ===
class OrdersController < ApplicationController
  def create
    # 1. Trace context extracted from request
    # → E11y::Current.trace_id = 'abc-123'
    
    # 2. Sample decision made at entry point
    # → rand < 0.1 = 0.05 → SAMPLED!
    # → E11y::Current.sampled = true
    
    Events::OrderCreated.track(order_id: '123')
    # → trace_id: 'abc-123', sampled: true → TRACKED
    
    # 3. Enqueue job (both trace_id + sample decision propagated)
    SendEmailJob.perform_later(order_id: '123')
    # Job metadata: {
    #   trace_id: 'abc-123',        ← From E11y::Current.trace_id
    #   e11y_sampled: true          ← From E11y::Current.sampled
    # }
    
    Events::OrderCompleted.track(order_id: '123')
    # → trace_id: 'abc-123', sampled: true → TRACKED
  end
end

# === BACKGROUND JOB ===
class SendEmailJob < ApplicationJob
  def perform(order_id)
    # 4. Trace context + sample decision restored from job metadata
    # → E11y::Current.trace_id = 'abc-123'
    # → E11y::Current.sampled = true
    
    Events::EmailSending.track(order_id: order_id)
    # → trace_id: 'abc-123', sampled: true → TRACKED (consistent!)
    
    send_email(order_id)
    
    Events::EmailSent.track(order_id: order_id)
    # → trace_id: 'abc-123', sampled: true → TRACKED
  end
end

# RESULT in Loki: Complete trace!
# {trace_id="abc-123"}
# 10:00:00.000 order.created
# 10:00:00.050 order.completed
# 10:00:02.000 email.sending
# 10:00:03.500 email.sent
```

**Cross-service example:**

```ruby
# Service A: API Gateway
class OrdersController < ApplicationController
  def create
    # trace_id: abc-123, sampled: true
    Events::OrderReceived.track(order_id: '123')
    
    # Call Service B (propagate BOTH trace_id + sample decision)
    response = HTTP
      .headers(
        'X-Trace-ID' => E11y::Current.trace_id,      # ← Trace ID
        'X-E11y-Sampled' => E11y::Current.sampled    # ← Sample decision
      )
      .post('http://payment-service/charge', json: { order_id: '123' })
    
    Events::OrderCreated.track(order_id: '123')
  end
end

# Service B: Payment Service
class PaymentsController < ApplicationController
  before_action :extract_trace_context
  
  def charge
    # trace_id: abc-123 (from header)
    # sampled: true (from header)
    
    Events::PaymentProcessing.track(order_id: params[:order_id])
    # → Tracked (consistent with Service A!)
    
    process_payment
    
    Events::PaymentSucceeded.track(order_id: params[:order_id])
    # → Tracked
  end
  
  private
  
  def extract_trace_context
    # E11y automatically extracts from headers:
    # X-Trace-ID → E11y::Current.trace_id
    # X-E11y-Sampled → E11y::Current.sampled
  end
end

# RESULT: Complete distributed trace!
# [Service A] order.received
# [Service A] order.created
# [Service B] payment.processing  ← Same trace_id + sampled!
# [Service B] payment.succeeded
```

**Exception: sample_on_error**

```ruby
# Scenario: Request initially NOT sampled, but error occurs
# 
# 1. HTTP request: trace_id = 'abc-123', sampled = false
# 2. Events buffered (not sent)
# 3. Payment error occurs!
# 4. sample_on_error = true → Override: sampled = true
# 5. Flush buffer → Send all events
# 6. Job metadata updated: e11y_sampled = true
# 7. Job tracks all events
# 
# RESULT: Complete error trace (even though initially not sampled!)

E11y.configure do |config|
  config.adaptive_sampling do
    trace_consistent do
      enabled true
      
      # ✅ Override sample decision on error
      sample_on_error true
      
      # This works with request-scoped debug buffering
      # See: UC-001 (Request-Scoped Debug Buffering)
    end
  end
end
```

**Best practices:**

1. **Always propagate sample decision with trace_id**
   ```ruby
   # ✅ GOOD: Both trace_id + sampled
   HTTP.headers(
     'X-Trace-ID' => E11y::Current.trace_id,
     'X-E11y-Sampled' => E11y::Current.sampled
   ).post(url, json: data)
   ```

2. **Use trace-consistent sampling in production**
   ```ruby
   # ✅ GOOD: Prevents incomplete traces
   config.adaptive_sampling.trace_consistent.enabled = true
   ```

3. **Always sample critical patterns (override trace decision)**
   ```ruby
   # ✅ GOOD: Critical events always tracked
   config.adaptive_sampling.always_sample event_patterns: ['payment.*', 'security.*']
   ```

**See also:**
- **[UC-014: Adaptive Sampling - Strategy 7](./UC-014-adaptive-sampling.md#strategy-7-trace-consistent-sampling)** - Detailed implementation
- **[UC-001: Request-Scoped Debug Buffering](./UC-001-request-scoped-debug-buffering.md)** - How `sample_on_error` works

---

## 🔧 Configuration API

### Full Configuration

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.trace_id do
    # === SOURCE PRIORITY (first found wins) ===
    
    # 1. Rails request UUID
    from_rails_request_id true
    
    # 2. HTTP headers (W3C Trace Context, custom headers)
    from_http_headers [
      'traceparent',      # W3C Trace Context (OpenTelemetry)
      'X-Request-ID',     # Common Rails default
      'X-Trace-ID',       # Custom header
      'X-Amzn-Trace-Id'   # AWS X-Ray
    ]
    
    # 3. Rails CurrentAttributes
    from_current_attributes :request_id
    
    # 4. Thread-local storage (background jobs)
    from_thread_local :trace_id
    
    # 5. Custom extractor
    custom_extractor -> {
      # Example: Extract from Sentry context
      Sentry.get_current_scope&.transaction&.trace_id
    }
    
    # 6. Generator (last resort)
    generator -> { SecureRandom.uuid }
    
    # === PARSING ===
    
    # W3C Trace Context parser (00-{trace_id}-{span_id}-{flags})
    parser :w3c_trace_context
    
    # OR custom parser
    parser ->(header_value) {
      # Extract trace_id from custom format
      header_value.split('-').first
    }
    
    # === PROPAGATION ===
    
    # Which HTTP headers to set when making outbound requests
    propagate_via_headers ['X-Trace-ID', 'traceparent']
    
    # Include in all E11y events
    include_in_events true  # Default
    
    # Include in logs (Rails.logger)
    include_in_logs true
    
    # Include in Sentry
    include_in_sentry true
  end
end
```

---

## 📊 Monitoring

### Trace ID Coverage

```ruby
# Self-monitoring metric
E11y.configure do |config|
  config.self_monitoring do
    # Track events with vs without trace_id
    counter :events_with_trace_id_total
    counter :events_without_trace_id_total
    
    # Alert if too many events lack trace_id
    # events_without_trace_id_total > 5% → alert
  end
end
```

---

## 🧪 Testing

```ruby
# spec/e11y/trace_id_spec.rb
RSpec.describe 'Trace ID Management' do
  it 'extracts trace_id from Rails request' do
    get '/orders', headers: { 'X-Request-ID' => 'test-trace-123' }
    
    # Verify event has correct trace_id
    event = E11y::Buffer.pop
    expect(event[:trace_id]).to eq('test-trace-123')
  end
  
  it 'propagates trace_id to background jobs' do
    # Set trace_id in request
    E11y::TraceId.with_trace_id('request-trace-456') do
      # Enqueue job
      TestJob.perform_later
    end
    
    # Verify job has same trace_id
    job_payload = Sidekiq::Queue.new.first
    expect(job_payload['trace_id']).to eq('request-trace-456')
  end
  
  it 'generates trace_id if none found' do
    # No request context, no headers
    Events::TestEvent.track(foo: 'bar')
    
    event = E11y::Buffer.pop
    expect(event[:trace_id]).to match(/^[0-9a-f-]{36}$/)  # UUID format
  end
end
```

---

## 💡 Best Practices

### ✅ DO

**1. Always propagate trace_id in HTTP calls**
```ruby
# ✅ GOOD: Propagate trace_id
HTTP.headers('X-Trace-ID' => E11y::TraceId.current).post(url, json: data)
```

**2. Use nested traces for sub-operations**
```ruby
# ✅ GOOD: Parent-child relationship
child_trace = "#{parent_trace}-operation-#{id}"
```

**3. Include trace_id in error logs**
```ruby
# ✅ GOOD: Easy to correlate
Rails.logger.error "Payment failed (trace_id: #{E11y::TraceId.current})"
```

---

### ❌ DON'T

**1. Don't generate new trace_id in background jobs**
```ruby
# ❌ BAD: Loses correlation
E11y::TraceId.with_trace_id(SecureRandom.uuid) do  # ← DON'T!
  perform_work
end

# ✅ GOOD: Use propagated trace_id (automatic!)
perform_work  # Trace ID already set by middleware
```

---

## 📚 Related Use Cases

- **[UC-014: Adaptive Sampling - Strategy 7](./UC-014-adaptive-sampling.md#strategy-7-trace-consistent-sampling)** - Trace-consistent sampling implementation
- **[UC-001: Request-Scoped Debug Buffering](./UC-001-request-scoped-debug-buffering.md)** - How `sample_on_error` works with buffering
- **[UC-005: Sentry Integration](./UC-005-sentry-integration.md)** - Trace correlation with Sentry
- **[UC-008: OpenTelemetry Integration](./UC-008-opentelemetry-integration.md)** - Full OTel support
- **[UC-009: Multi-Service Tracing](./UC-009-multi-service-tracing.md)** - Cross-service trace propagation

---

**Document Version:** 1.0  
**Last Updated:** January 12, 2026  
**Status:** ✅ Complete

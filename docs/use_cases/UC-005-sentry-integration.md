# UC-005: Sentry Integration

**Status:** ✅ Implemented (2026-01-19)  
**Complexity:** Low  
**Setup Time:** 10 minutes  
**Target Users:** All developers

**Implementation:**
- ✅ `E11y::Adapters::Sentry` - Implemented with full Sentry SDK integration
- ✅ Automatic error reporting (severity-based filtering)
- ✅ Breadcrumb tracking for context
- ✅ Trace context propagation (trace_id, span_id)
- ✅ User context support
- ✅ 39 comprehensive tests
- 📖 See [ADR-004 §4.4](../architecture/ADR-004-adapter-architecture.md#44-sentry-adapter) for technical details

---

## 📋 Overview

### Problem Statement

**Current Approach (Separate Systems):**
```ruby
# ❌ Duplication and disconnected systems
begin
  process_payment(order)
rescue => e
  # Log to Rails logger
  Rails.logger.error "Payment failed: #{e.message}"
  
  # Send to Sentry
  Sentry.capture_exception(e, extra: { order_id: order.id })
  
  # Track business event
  Events::PaymentFailed.track(order_id: order.id, error: e.class.name)
end

# Problems:
# - 3 separate calls (verbose)
# - No correlation between systems
# - Can't see event context in Sentry
# - Can't jump from Sentry to logs
```

### E11y Solution

**Unified error tracking with automatic Sentry integration:**
```ruby
# ✅ One call, automatic Sentry integration
begin
  process_payment(order)
rescue => e
  Events::PaymentFailed.track(
    order_id: order.id,
    error_class: e.class.name,
    error_message: e.message,
    severity: :error  # ← Automatically sends to Sentry!
  )
end

# Result:
# ✅ Event tracked in E11y
# ✅ Exception in Sentry (with breadcrumbs)
# ✅ Correlated via trace_id
# ✅ Full event context in Sentry extras
```

---

## 🎯 Features

### 1. Automatic Exception Capture

> **Implementation:** See [ADR-004 Section 4.4: Sentry Adapter](../architecture/ADR-004-adapter-architecture.md#44-sentry-adapter) for technical details.

**Configuration (2026-01-19 - Actual Implementation):**
```ruby
# config/initializers/e11y.rb
require 'e11y'

# Configure Sentry adapter
E11y.configure do |config|
  config.adapters[:sentry] = E11y::Adapters::Sentry.new(
    dsn: ENV['SENTRY_DSN'],
    environment: Rails.env,
    severity_threshold: :warn,  # Send :warn, :error, :fatal to Sentry
    breadcrumbs: true           # Track all events as breadcrumbs
  )
end

# Use in events
class Events::PaymentFailed < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:error_message).filled(:string)
  end

  severity :error
  adapters [:sentry, :loki]  # Send to both Sentry and Loki
end
```

**Usage:**
```ruby
# ANY event with severity :error automatically goes to Sentry
Events::PaymentFailed.track(
  order_id: '123',
  amount: 99.99,
  error_message: 'Card declined',
  severity: :error  # ← Triggers Sentry capture
)

# In Sentry UI you'll see:
# - Event name: "payment.failed"
# - Message: "Card declined"
# - Context: { order_id: '123', amount: 99.99 }
# - Trace ID: abc-123-def (for correlation)
```

---

### 2. Breadcrumbs Trail

**All E11y events become Sentry breadcrumbs:**
```ruby
# These events create breadcrumb trail
Events::CartViewed.track(user_id: '123', items: 3)
Events::CheckoutStarted.track(user_id: '123', cart_total: 299.99)
Events::PaymentAttempted.track(user_id: '123', payment_method: 'stripe')
Events::PaymentFailed.track(user_id: '123', error: 'Card declined', severity: :error)

# In Sentry, you'll see breadcrumb trail:
# 1. [info] cart.viewed - { user_id: '123', items: 3 }
# 2. [info] checkout.started - { user_id: '123', cart_total: 299.99 }
# 3. [info] payment.attempted - { user_id: '123', payment_method: 'stripe' }
# 4. [error] payment.failed - { user_id: '123', error: 'Card declined' } ← Exception
```

**Configuration:**
```ruby
E11y.configure do |config|
  config.sentry do
    # Enable breadcrumbs
    breadcrumbs true
    
    # Which severities become breadcrumbs
    breadcrumb_severities [:debug, :info, :warn, :error]
    
    # Max breadcrumbs (Sentry default is 100)
    max_breadcrumbs 100
    
    # Breadcrumb data limit
    max_breadcrumb_size 1.kilobyte
  end
end
```

---

### 3. Trace Correlation

**Link Sentry errors to E11y logs:**
```ruby
# E11y automatically adds trace_id to all events
Events::PaymentFailed.track(
  order_id: '123',
  error: 'Card declined',
  severity: :error
)
# → Sentry tag: trace_id = abc-123-def

# In your observability stack:
# 1. See error in Sentry with trace_id = abc-123-def
# 2. Search Loki/ELK: trace_id:"abc-123-def"
# 3. See FULL context (all events in request)

# Grafana query:
# {trace_id="abc-123-def"} |= ""
# → Shows complete timeline of request
```

---

### 4. Custom Fingerprinting

> **Implementation:** See [ADR-004 Section 4.4: Sentry Adapter](../architecture/ADR-004-adapter-architecture.md#44-sentry-adapter) for technical details.

**Group similar errors in Sentry:**
```ruby
E11y.configure do |config|
  config.sentry do
    # Custom fingerprint for better grouping
    fingerprint_extractor ->(event_data) {
      if event_data[:event_name] == 'payment.failed'
        # Group by payment_method + error_code (not full error message)
        [
          event_data[:event_name],
          event_data[:payload][:payment_method],
          event_data[:payload][:error_code]
        ]
      else
        # Default: group by event name
        [event_data[:event_name]]
      end
    }
  end
end

# Result in Sentry:
# - "payment.failed + stripe + card_declined" (100 occurrences)
# - "payment.failed + paypal + insufficient_funds" (50 occurrences)
# Instead of 150 separate issues
```

---

### 5. Sampling Control

> **Implementation:** See [ADR-004 Section 4.4: Sentry Adapter](../architecture/ADR-004-adapter-architecture.md#44-sentry-adapter) for technical details.

**Avoid Sentry quota exhaustion:**
```ruby
E11y.configure do |config|
  config.sentry do
    # Sample rate for Sentry (0.0 - 1.0)
    sample_rate 1.0  # 100% (default)
    
    # OR: Dynamic sampling per event
    sample_rate_for 'payment.failed', 1.0      # Always capture
    sample_rate_for 'api.slow_request', 0.1    # 10% (too noisy)
    sample_rate_for 'user.action', 0.01        # 1% (very noisy)
    
    # OR: Conditional sampling
    sampler ->(event_data) {
      if event_data[:severity] == :fatal
        1.0  # Always capture fatal
      elsif event_data[:context][:user_segment] == 'enterprise'
        1.0  # Always capture enterprise users
      else
        0.1  # 10% for others
      end
    }
  end
end
```

---

## 💻 Implementation Examples

### Example 1: Payment Processing

```ruby
# app/services/process_payment_service.rb
class ProcessPaymentService
  def call(order)
    # Track attempt
    Events::PaymentAttempted.track(
      order_id: order.id,
      amount: order.total,
      payment_method: order.payment_method
    )
    
    begin
      # Process payment
      result = PaymentGateway.charge(
        amount: order.total,
        card: order.card_token
      )
      
      # Track success
      Events::PaymentSucceeded.track(
        order_id: order.id,
        transaction_id: result.id,
        amount: order.total,
        severity: :success  # ← Positive signal (not error)
      )
      
    rescue PaymentGateway::CardDeclined => e
      # Track failure (automatically goes to Sentry)
      Events::PaymentFailed.track(
        order_id: order.id,
        amount: order.total,
        payment_method: order.payment_method,
        error_class: e.class.name,
        error_message: e.message,
        error_code: e.code,
        severity: :error  # ← Automatically captured in Sentry
      )
      
      raise  # Re-raise for caller to handle
    end
  end
end

# In Sentry, you'll see:
# - Full breadcrumb trail (attempted → failed)
# - Order context (ID, amount, payment method)
# - Error details (class, message, code)
# - Trace ID (to correlate with logs)
```

---

### Example 2: Background Jobs

```ruby
# app/jobs/send_email_job.rb
class SendEmailJob < ApplicationJob
  def perform(user_id, template)
    user = User.find(user_id)
    
    # Track start
    Events::EmailSending.track(
      user_id: user.id,
      template: template
    )
    
    begin
      # Send email
      UserMailer.with(user: user).send(template).deliver_now
      
      # Track success
      Events::EmailSent.track(
        user_id: user.id,
        template: template,
        severity: :success
      )
      
    rescue Net::SMTPError => e
      # Track failure (goes to Sentry)
      Events::EmailFailed.track(
        user_id: user.id,
        template: template,
        error_class: e.class.name,
        error_message: e.message,
        severity: :error  # ← Sentry capture
      )
      
      # Retry job (Sidekiq will handle)
      raise
    end
  end
end

# Sentry shows:
# - Job context (user_id, template)
# - Retry attempts (Sidekiq integration)
# - Full error trace
# - Breadcrumbs (sending → failed)
```

---

### Example 3: API Integration Failures

```ruby
# app/services/sync_with_external_api_service.rb
class SyncWithExternalApiService
  def call
    Events::ApiSyncStarted.track(api: 'external_crm')
    
    begin
      response = HTTP.timeout(10).get('https://api.example.com/sync')
      
      if response.status.success?
        Events::ApiSyncSucceeded.track(
          api: 'external_crm',
          records_synced: response.parse['count'],
          severity: :success
        )
      else
        Events::ApiSyncFailed.track(
          api: 'external_crm',
          http_status: response.code,
          response_body: response.body.to_s[0..500],  # First 500 chars
          severity: :error  # ← Sentry capture
        )
      end
      
    rescue HTTP::TimeoutError => e
      Events::ApiSyncTimeout.track(
        api: 'external_crm',
        timeout_seconds: 10,
        error_message: e.message,
        severity: :error  # ← Sentry capture
      )
      
    rescue => e
      Events::ApiSyncError.track(
        api: 'external_crm',
        error_class: e.class.name,
        error_message: e.message,
        severity: :fatal  # ← Sentry capture (high priority)
      )
    end
  end
end
```

---

## 🔧 Advanced Configuration

### Sentry Adapter (Custom Implementation)

```ruby
# lib/e11y/adapters/sentry_adapter.rb
module E11y
  module Adapters
    class SentryAdapter < Base
      def initialize(
        capture_severities: [:error, :fatal],
        breadcrumb_severities: [:debug, :info, :warn, :error],
        include_payload: true,
        max_payload_size: 10.kilobytes
      )
        @capture_severities = capture_severities
        @breadcrumb_severities = breadcrumb_severities
        @include_payload = include_payload
        @max_payload_size = max_payload_size
      end
      
      def send_batch(events)
        events.each do |event|
          # Add breadcrumb for ALL events
          add_breadcrumb(event) if should_breadcrumb?(event)
          
          # Capture exception for error events
          capture_event(event) if should_capture?(event)
        end
        
        Result.success
      end
      
      private
      
      def should_breadcrumb?(event)
        @breadcrumb_severities.include?(event[:severity])
      end
      
      def should_capture?(event)
        @capture_severities.include?(event[:severity])
      end
      
      def add_breadcrumb(event)
        Sentry.add_breadcrumb(
          Sentry::Breadcrumb.new(
            category: 'e11y',
            message: event[:event_name],
            data: truncate_payload(event[:payload]),
            level: sentry_level(event[:severity]),
            timestamp: event[:timestamp].to_i
          )
        )
      end
      
      def capture_event(event)
        Sentry.capture_message(
          "#{event[:event_name]}: #{event[:payload][:error_message] || 'Event'}",
          level: sentry_level(event[:severity]),
          extra: build_extra(event),
          tags: build_tags(event),
          fingerprint: build_fingerprint(event)
        )
      end
      
      def build_extra(event)
        extra = {
          event_name: event[:event_name],
          event_id: event[:event_id],
          trace_id: event[:trace_id],
          timestamp: event[:timestamp].iso8601
        }
        
        if @include_payload
          extra[:payload] = truncate_payload(event[:payload])
        end
        
        extra.merge!(event[:context]) if event[:context]
        extra
      end
      
      def build_tags(event)
        {
          event_name: event[:event_name],
          trace_id: event[:trace_id],
          severity: event[:severity],
          env: event[:context][:env],
          service: event[:context][:service]
        }.compact
      end
      
      def build_fingerprint(event)
        if E11y.config.sentry.fingerprint_extractor
          E11y.config.sentry.fingerprint_extractor.call(event)
        else
          [event[:event_name]]
        end
      end
      
      def sentry_level(severity)
        case severity
        when :debug then :debug
        when :info, :success then :info
        when :warn then :warning
        when :error then :error
        when :fatal then :fatal
        else :info
        end
      end
      
      def truncate_payload(payload)
        json = payload.to_json
        if json.bytesize > @max_payload_size
          truncated = json[0...@max_payload_size]
          JSON.parse(truncated + '...')
        else
          payload
        end
      rescue JSON::ParserError
        { _truncated: true, _size: json.bytesize }
      end
    end
  end
end
```

---

## 📊 Monitoring

### Sentry Quota Management

```ruby
# Track Sentry events sent (self-monitoring)
E11y.configure do |config|
  config.self_monitoring do
    counter :sentry_events_sent_total,
            tags: [:event_name, :severity]
    
    counter :sentry_events_sampled_out_total,
            tags: [:event_name]
    
    gauge :sentry_quota_used_pct,
          comment: 'Percentage of Sentry quota used'
  end
end

# Alert on high Sentry usage
# sentry_events_sent_total > 1000/min → alert
```

---

## 🧪 Testing

```ruby
# spec/e11y/sentry_integration_spec.rb
RSpec.describe 'Sentry Integration' do
  before do
    # Mock Sentry
    allow(Sentry).to receive(:capture_message)
    allow(Sentry).to receive(:add_breadcrumb)
    
    E11y.configure do |config|
      config.sentry do
        enabled true
        capture_severities [:error, :fatal]
        breadcrumb_severities [:info, :error]
      end
    end
  end
  
  it 'captures error events in Sentry' do
    Events::PaymentFailed.track(
      order_id: '123',
      error_message: 'Card declined',
      severity: :error
    )
    
    expect(Sentry).to have_received(:capture_message).with(
      'payment.failed: Card declined',
      hash_including(
        level: :error,
        extra: hash_including(event_name: 'payment.failed'),
        tags: hash_including(event_name: 'payment.failed')
      )
    )
  end
  
  it 'adds breadcrumbs for all events' do
    Events::CartViewed.track(user_id: '123', items: 3, severity: :info)
    
    expect(Sentry).to have_received(:add_breadcrumb).with(
      an_instance_of(Sentry::Breadcrumb)
    )
  end
  
  it 'does not capture info events' do
    Events::OrderPaid.track(order_id: '123', amount: 99.99, severity: :info)
    
    expect(Sentry).not_to have_received(:capture_message)
  end
end
```

---

## 💡 Best Practices

### ✅ DO

**1. Use :error/:fatal for exceptions only**
```ruby
# ✅ GOOD: Real errors
Events::PaymentFailed.track(error: e.message, severity: :error)
Events::DatabaseConnectionLost.track(severity: :fatal)

# ❌ BAD: Business logic (not errors)
Events::UserLoggedOut.track(severity: :error)  # ← NOT an error!
```

**2. Include error details**
```ruby
# ✅ GOOD: Full context
Events::ApiCallFailed.track(
  api: 'external_crm',
  error_class: e.class.name,
  error_message: e.message,
  error_code: e.code,
  http_status: response.code,
  severity: :error
)
```

**3. Use fingerprinting for grouping**
```ruby
# Group similar errors together
fingerprint_extractor ->(event) {
  [event[:event_name], event[:payload][:error_code]]
}
```

---

### ❌ DON'T

**1. Don't send PII to Sentry**
```ruby
# ❌ BAD: PII in error message
Events::LoginFailed.track(
  email: 'user@example.com',  # ← PII!
  password: '***',            # ← Even worse!
  severity: :error
)

# ✅ GOOD: Filtered
Events::LoginFailed.track(
  user_id: '123',  # IDs are OK
  error: 'Invalid credentials',
  severity: :error
)
```

**2. Don't overload Sentry with noisy events**
```ruby
# ❌ BAD: Too noisy
Events::ApiSlowRequest.track(duration: 501, severity: :error)  # Every slow request!

# ✅ GOOD: Sample or use higher threshold
sample_rate_for 'api.slow_request', 0.1  # 10%
```

---

## 📚 Related Use Cases

- **[UC-002: Business Event Tracking](./UC-002-business-event-tracking.md)** - Event definitions
- **[UC-007: PII Filtering](./UC-007-pii-filtering.md)** - Prevent PII leaks to Sentry

---

## 📦 Implementation Details (2026-01-19)

### Actual SentryAdapter Implementation

The implemented `E11y::Adapters::Sentry` provides:

**Features:**
- ✅ **Severity-based filtering**: Configurable `severity_threshold` (default: `:warn`)
- ✅ **Error reporting**: Automatic `Sentry.capture_message` for `:error` and `:fatal` events
- ✅ **Exception handling**: Direct `Sentry.capture_exception` when exception object provided
- ✅ **Breadcrumbs**: All non-error events tracked as `Sentry.add_breadcrumb`
- ✅ **Context propagation**: Tags, extras, user context, and trace context
- ✅ **Severity mapping**: E11y severities → Sentry levels (debug/info/warning/error/fatal)

**Usage Example:**
```ruby
# Configure adapter
E11y.configure do |config|
  config.adapters[:sentry] = E11y::Adapters::Sentry.new(
    dsn: ENV['SENTRY_DSN'],
    environment: 'production',
    severity_threshold: :warn,
    breadcrumbs: true
  )
end

# Track error event
Events::PaymentFailed.track(
  order_id: 'ORD-123',
  error_message: 'Card declined',
  user: { id: 456, email: 'user@example.com' },
  trace_id: 'trace-abc-123',
  span_id: 'span-def-456'
)

# Result in Sentry:
# - Message: "Card declined"
# - Tags: { event_name: "payment.failed", severity: "error" }
# - Extras: { order_id: "ORD-123", ... }
# - User: { id: 456, email: "user@example.com" }
# - Context: { trace: { trace_id: "trace-abc-123", span_id: "span-def-456" } }
```

**Testing:**
```ruby
# spec/e11y/adapters/sentry_spec.rb - 39 tests
RSpec.describe E11y::Adapters::Sentry do
  it 'sends errors to Sentry' do
    expect(::Sentry).to receive(:capture_message).with(
      "Payment processing failed",
      level: :error
    )

    adapter.write(error_event)
  end

  it 'sends breadcrumbs for non-error events' do
    expect(::Sentry).to receive(:add_breadcrumb)
    adapter.write(warn_event)
  end
end
```

**See Also:**
- Implementation: `lib/e11y/adapters/sentry.rb` (211 lines)
- Tests: `spec/e11y/adapters/sentry_spec.rb` (39 tests)
- ADR: [ADR-004 §4.4](../architecture/ADR-004-adapter-architecture.md#44-sentry-adapter)

---

**Document Version:** 2.0  
**Last Updated:** January 19, 2026  
**Status:** ✅ Implemented & Tested

# UC-018: Testing Events

**Status:** MVP Feature  
**Complexity:** Beginner  
**Setup Time:** 10-15 minutes  
**Target Users:** All Developers, QA Engineers

---

## 📋 Overview

### Problem Statement

**The testing challenge:**
```ruby
# ❌ BEFORE: Hard to test events
RSpec.describe OrdersController do
  it 'creates order' do
    post :create, params: { order: order_params }
    
    # How do I test that Events::OrderCreated was tracked?
    # - Can't easily check event was emitted
    # - Can't verify event payload
    # - Can't test metrics were updated
    # - Events go to real adapters (slow!)
  end
end
```

### E11y Solution

**Built-in RSpec support:**
```ruby
# ✅ AFTER: Easy event testing
RSpec.describe OrdersController do
  it 'creates order' do
    # Expect event class to be tracked
    expect {
      post :create, params: { order: order_params }
    }.to track_event(Events::OrderCreated)
      .with(order_id: '123', user_id: '456')
    
    # Automatic assertions:
    # ✅ Event was tracked
    # ✅ Payload matches
    # ✅ Severity matches (from class definition)
  end
end
```

---

## 🎯 Features

> **Implementation:** See [ADR-011: Testing Strategy](../architecture/ADR-011-testing-strategy.md) for complete testing architecture, including [Section 3: RSpec Matchers](../architecture/ADR-011-testing-strategy.md#3-rspec-matchers), [Section 4: Test Adapters](../architecture/ADR-011-testing-strategy.md#4-test-adapters), [Section 6: Snapshot Testing](../architecture/ADR-011-testing-strategy.md#6-snapshot-testing), and [Section 8: Integration Testing](../architecture/ADR-011-testing-strategy.md#8-integration-testing).

### 1. RSpec Matchers

**Built-in custom matchers:**
```ruby
# spec/support/e11y.rb
require 'e11y/rspec'

RSpec.configure do |config|
  config.include E11y::RSpec::Matchers
  
  config.before(:each) do
    # Clear events before each test
    E11y.reset!
  end
end

# === MATCHER: track_event ===
# Basic usage (with event class)
expect { action }.to track_event(Events::OrderCreated)

# With payload matching
expect { action }.to track_event(Events::OrderCreated)
  .with(order_id: '123')

# With hash_including (partial match)
expect { action }.to track_event(Events::OrderCreated)
  .with(hash_including(order_id: '123'))

# Check severity (from event class definition)
expect { action }.to track_event(Events::PaymentFailed)
  # severity already defined in Events::PaymentFailed class

# With count
expect { action }.to track_event(Events::OrderCreated).once
expect { action }.to track_event(Events::PaymentRetry).exactly(3).times
expect { action }.to track_event(Events::NotificationSent).at_least(1).times

# Negation
expect { action }.not_to track_event(Events::OrderCancelled)

# === MATCHER: track_events (multiple) ===
expect { action }.to track_events(
  Events::OrderCreated,
  Events::PaymentProcessing,
  Events::ShipmentScheduled
).in_order

# === MATCHER: update_metric ===
expect { action }.to update_metric('orders.total')
  .by(1)
  .with_tags(status: 'paid')

# === MATCHER: have_trace_id ===
event = E11y.last_event
expect(event).to have_trace_id('abc-123')

# === MATCHER: have_valid_schema ===
event = E11y.last_event
expect(event).to have_valid_schema
```

---

### 2. Test Helpers

**Convenient helper methods:**
```ruby
# spec/support/e11y.rb
RSpec.configure do |config|
  config.include E11y::RSpec::Helpers
end

# === Helper: e11y_events ===
# Get all tracked events
events = e11y_events
# => [<Events::OrderCreated>, <Events::PaymentProcessing>]

# Filter by event class
events = e11y_events(Events::OrderCreated)
# => [<Events::OrderCreated>]

# Filter by pattern (for dynamic filtering)
events = e11y_events(/^order\./)
# => [<Events::OrderCreated>, <Events::OrderShipped>]

# Filter by severity
events = e11y_events(severity: :error)
# => [<Events::PaymentFailed>]

# === Helper: e11y_last_event ===
event = e11y_last_event
# => <Events::OrderCreated>

event = e11y_last_event(Events::PaymentProcessing)
# => <Events::PaymentProcessing>

# === Helper: e11y_event_classes ===
classes = e11y_event_classes
# => [Events::OrderCreated, Events::PaymentProcessing, Events::ShipmentScheduled]

# === Helper: e11y_reset! ===
e11y_reset!  # Clear all tracked events

# === Helper: e11y_disable / e11y_enable ===
e11y_disable  # Disable event tracking
# ... code ...
e11y_enable   # Re-enable

# === Helper: e11y_with_config ===
e11y_with_config(severity: :debug) do
  # Temporarily change config
  Events::DebugEvent.track(...)
end
# Config restored after block
```

---

### 3. Stub Events (Test Doubles)

**Mock event tracking for isolation:**
```ruby
# === Stub specific event ===
allow(Events::OrderCreated).to receive(:track)

post :create, params: { order: order_params }

expect(Events::OrderCreated).to have_received(:track)
  .with(hash_including(order_id: '123'))

# === Stub and return value ===
allow(Events::PaymentProcessing).to receive(:track).and_return(
  E11y::TrackResult.success
)

# === Spy on events ===
event_spy = spy('Events::OrderCreated')
stub_const('Events::OrderCreated', event_spy)

post :create, params: { order: order_params }

expect(event_spy).to have_received(:track)

# === Partial stub (stub only track, keep schema validation) ===
allow(Events::OrderCreated).to receive(:track).and_call_original
# ... test ...
expect(Events::OrderCreated).to have_received(:track)
```

---

### 4. Factory Support

**FactoryBot integration:**
```ruby
# spec/factories/e11y_events.rb
FactoryBot.define do
  factory :e11y_event, class: 'E11y::Event' do
    event_name { 'test.event' }
    severity { :info }
    payload { {} }
    context { { trace_id: SecureRandom.uuid } }
    timestamp { Time.current }
    
    trait :order_created do
      event_name { 'order.created' }
      payload do
        {
          order_id: '123',
          user_id: '456',
          amount: 99.99
        }
      end
    end
    
    trait :payment_failed do
      event_name { 'payment.failed' }
      severity { :error }
      payload do
        {
          order_id: '123',
          error: 'Card declined'
        }
      end
    end
    
    trait :with_trace do
      context do
        {
          trace_id: 'abc-123-def',
          request_id: 'req-789',
          user_id: '456'
        }
      end
    end
  end
end

# Usage:
event = create(:e11y_event, :order_created)
event = build(:e11y_event, :payment_failed, :with_trace)
events = create_list(:e11y_event, 5, :order_created)
```

---

### 5. Snapshot Testing

**Capture and compare event snapshots:**
```ruby
# spec/support/e11y_snapshot.rb
RSpec.configure do |config|
  config.include E11y::RSpec::Snapshot
end

# === Snapshot matcher ===
RSpec.describe OrdersController do
  it 'creates order with expected events' do
    expect {
      post :create, params: { order: order_params }
    }.to match_event_snapshot
    
    # First run: creates snapshot file
    # spec/fixtures/e11y_snapshots/orders_controller_creates_order.json
    
    # Subsequent runs: compares against snapshot
    # Fails if events changed!
  end
  
  it 'creates order', :update_snapshot do
    # Use :update_snapshot tag to update snapshot
    expect {
      post :create, params: { order: order_params }
    }.to match_event_snapshot
  end
end

# Snapshot file format:
# spec/fixtures/e11y_snapshots/orders_controller_creates_order.json
{
  "events": [
    {
      "event_name": "order.created",
      "severity": "success",
      "payload": {
        "order_id": "123",
        "user_id": "456",
        "amount": 99.99
      }
    },
    {
      "event_name": "notification.sent",
      "severity": "info",
      "payload": {
        "type": "order_confirmation",
        "recipient": "user@example.com"
      }
    }
  ]
}

# Benefits:
# ✅ Catch unintended changes
# ✅ Document expected behavior
# ✅ Easy to review in PR diffs
```

---

### 6. Test Environment Configuration (C13)

> **Implementation:** See [ADR-011 Section 10: Test Environment Configuration](../architecture/ADR-011-testing-strategy.md#10-test-environment-configuration) for detailed rationale on disabling production features in tests.

**Critical: Production features MUST be disabled in tests for predictability.**

**Problem: Non-Deterministic Tests**

```ruby
# ❌ BAD: Production config enabled in tests
# config/environments/test.rb (default Rails)
# → E11y inherits production config!

RSpec.describe OrdersController do
  it 'creates order' do
    post :create, params: { order: order_params }
    
    # ❌ PROBLEM 1: Sampling enabled (10% rate)
    #    → Event randomly dropped! Test flaky!
    #    → Fails 90% of the time!
    
    # ❌ PROBLEM 2: Buffering enabled (10s flush)
    #    → Event not visible yet! Test fails!
    #    → Must wait 10 seconds or call E11y.flush
    
    # ❌ PROBLEM 3: Async adapters
    #    → Events sent in background threads
    #    → Race conditions!
    
    expect {
      # ... may pass or fail randomly!
    }.to track_event(Events::OrderCreated)
  end
end
```

**Solution: Disable Production Features in Tests**

```ruby
# spec/support/e11y_helper.rb (RECOMMENDED SETUP)
RSpec.configure do |config|
  config.before(:suite) do
    # Configure E11y for test environment
    E11y.configure do |config|
      # === CRITICAL: Disable sampling ===
      # ✅ Ensures ALL events are tracked (100% predictability)
      # ❌ Without this: Random test failures (sampling drops 90% of events)
      config.sampling.enabled = false
      
      # === CRITICAL: Disable buffering OR use flush helper ===
      # Option 1: Disable buffering (immediate writes)
      config.buffering.enabled = false
      
      # Option 2: Keep buffering but flush after each test
      # config.buffering.enabled = true  # (if needed for performance tests)
      
      # === CRITICAL: Synchronous adapters only ===
      # ✅ Use TestAdapter (stores events in memory)
      # ❌ No Loki, Sentry, S3 (slow, async, flaky)
      config.adapters = [
        E11y::Adapters::TestAdapter.new
      ]
      
      # === OPTIONAL: Disable rate limiting ===
      config.rate_limiting_enabled = false
      
      # === OPTIONAL: Disable PII filtering (test data is fake) ===
      config.pii_filtering.enabled = false
    end
  end
  
  config.before(:each) do
    # Clear events before each test
    E11y.reset!
    
    # If buffering enabled, flush before test
    # E11y.flush
  end
  
  config.after(:each) do
    # If buffering enabled, flush after test (for assertions)
    E11y.flush if E11y.config.buffering.enabled
  end
end
```

**Key Configuration Options:**

| Feature | Test Value | Production Value | Why Different? |
|---------|-----------|------------------|----------------|
| **Sampling** | ❌ Disabled (100%) | ✅ Enabled (10-50%) | Tests need ALL events, no randomness |
| **Buffering** | ❌ Disabled (immediate) | ✅ Enabled (10s batches) | Tests need synchronous assertions |
| **Adapters** | `TestAdapter` (in-memory) | `LokiAdapter`, `SentryAdapter` | Tests need fast, synchronous, no network |
| **Rate Limiting** | ❌ Disabled | ✅ Enabled (1000/min) | Tests may emit many events rapidly |
| **PII Filtering** | ❌ Disabled (optional) | ✅ Enabled (GDPR) | Test data is fake (no real PII) |

**Manual Flush Helper (for Buffering Tests):**

If you need to test buffering behavior, use `E11y.flush`:

```ruby
RSpec.describe 'Buffering behavior' do
  before do
    E11y.configure do |config|
      config.buffering do
        enabled true
        flush_interval 10.seconds
        max_buffer_size 100
      end
    end
  end
  
  it 'buffers events until flush' do
    # Event tracked but NOT sent yet (buffered)
    Events::OrderCreated.track(order_id: '123')
    
    # Buffer has 1 event
    expect(E11y.buffer.size).to eq(1)
    
    # Adapter has 0 events (not flushed yet)
    expect(E11y::Adapters::TestAdapter.events.size).to eq(0)
    
    # === CRITICAL: Manual flush for synchronous testing ===
    E11y.flush
    
    # Now buffer is empty
    expect(E11y.buffer.size).to eq(0)
    
    # Adapter has 1 event (flushed)
    expect(E11y::Adapters::TestAdapter.events.size).to eq(1)
  end
  
  it 'auto-flushes when buffer full' do
    # Track 101 events (exceeds max_buffer_size: 100)
    101.times { |i| Events::OrderCreated.track(order_id: i) }
    
    # Buffer auto-flushed when full (at 100)
    expect(E11y::Adapters::TestAdapter.events.size).to eq(100)
    
    # 1 event still in buffer
    expect(E11y.buffer.size).to eq(1)
    
    # Flush remaining
    E11y.flush
    expect(E11y::Adapters::TestAdapter.events.size).to eq(101)
  end
end
```

**Deterministic Sampling (for Sampling Tests):**

If you need to test sampling behavior, use a **fixed random seed**:

```ruby
RSpec.describe 'Sampling behavior' do
  before do
    # === CRITICAL: Set fixed random seed for deterministic sampling ===
    srand(12345)  # ← Same seed = same random sequence
    
    E11y.configure do |config|
      config.sampling do
        enabled true
        strategy :random
        rate 0.5  # Keep 50% of events
      end
    end
  end
  
  it 'samples events deterministically with fixed seed' do
    # With seed=12345, first 10 events sampled as:
    # [KEEP, DROP, KEEP, DROP, KEEP, KEEP, DROP, DROP, KEEP, DROP]
    # (this sequence is deterministic with seed=12345)
    
    10.times do |i|
      Events::OrderCreated.track(order_id: i)
    end
    
    # With seed=12345 and rate=0.5, expect 5 events kept
    expect(E11y::Adapters::TestAdapter.events.size).to eq(5)
    
    # Verify specific events kept (deterministic!)
    kept_order_ids = E11y::Adapters::TestAdapter.events.map { |e| e.payload[:order_id] }
    expect(kept_order_ids).to eq([0, 2, 4, 5, 8])  # Deterministic with seed=12345
  end
  
  it 'can test different sampling rates' do
    E11y.configure do |config|
      config.sampling.rate = 0.1  # Keep 10%
    end
    
    100.times { |i| Events::OrderCreated.track(order_id: i) }
    
    # With seed=12345 and rate=0.1, expect ~10 events
    expect(E11y::Adapters::TestAdapter.events.size).to be_within(2).of(10)
  end
end
```

**RSpec Shared Context (Reusable Config):**

```ruby
# spec/support/shared_contexts/e11y_test_config.rb
RSpec.shared_context 'e11y_test_config' do
  before do
    E11y.configure do |config|
      config.sampling.enabled = false
      config.buffering.enabled = false
      config.adapters = [E11y::Adapters::TestAdapter.new]
    end
  end
  
  after do
    E11y.flush
    E11y.reset!
  end
end

# Usage:
RSpec.describe OrdersController do
  include_context 'e11y_test_config'
  
  it 'creates order' do
    # ... test with clean E11y config
  end
end
```

**Trade-offs:**

| Decision | Pro | Con | Recommendation |
|----------|-----|-----|----------------|
| **Disable sampling** | 100% predictable tests | Doesn't test prod sampling | ✅ Always disable (test sampling separately with fixed seed) |
| **Disable buffering** | Synchronous assertions | Doesn't test buffering behavior | ✅ Disable by default (test buffering separately with `E11y.flush`) |
| **Use TestAdapter** | Fast, in-memory, no network | Doesn't test real adapters | ✅ Always use (test real adapters in integration tests) |
| **Fixed random seed** | Deterministic sampling tests | Non-obvious magic number | ⚠️ Use only for sampling tests, document seed choice |

**Common Pitfalls:**

```ruby
# ❌ PITFALL 1: Forgot to disable sampling
RSpec.describe 'Feature' do
  it 'tracks event' do
    # Sampling enabled (10% rate) → 90% chance of failure!
    expect {
      Events::OrderCreated.track(order_id: '123')
    }.to track_event(Events::OrderCreated)  # ← Flaky!
  end
end

# ✅ FIX: Disable sampling in spec/support/e11y_helper.rb

# ❌ PITFALL 2: Forgot to flush buffer
RSpec.describe 'Feature' do
  before do
    E11y.configure { |c| c.buffering.enabled = true }
  end
  
  it 'tracks event' do
    Events::OrderCreated.track(order_id: '123')
    # Buffer not flushed → event not in adapter yet!
    expect(E11y::Adapters::TestAdapter.events.size).to eq(1)  # ← Fails!
  end
end

# ✅ FIX: Call E11y.flush before assertions
it 'tracks event' do
  Events::OrderCreated.track(order_id: '123')
  E11y.flush  # ← Force flush
  expect(E11y::Adapters::TestAdapter.events.size).to eq(1)  # ← Passes!
end

# ❌ PITFALL 3: Used production adapters in tests
RSpec.describe 'Feature' do
  before do
    E11y.configure do |config|
      config.adapters = [
        E11y::Adapters::LokiAdapter.new(...)  # ← Slow! Network calls!
      ]
    end
  end
  
  it 'tracks event' do
    # Test takes 5 seconds per event! ❌
    Events::OrderCreated.track(order_id: '123')
  end
end

# ✅ FIX: Use TestAdapter
config.adapters = [E11y::Adapters::TestAdapter.new]
```

**Key Takeaways:**

1. **Always disable sampling in tests** (non-deterministic = flaky tests)
2. **Disable buffering OR call `E11y.flush`** (synchronous assertions)
3. **Use TestAdapter only** (fast, in-memory, no network)
4. **Fixed random seed for sampling tests** (deterministic behavior)
5. **Flush buffer in `after(:each)` hook** (if buffering enabled)

---

## 💻 Implementation Examples

### Example 1: Controller Tests

```ruby
# spec/controllers/orders_controller_spec.rb
RSpec.describe OrdersController do
  describe 'POST #create' do
    let(:order_params) do
      {
        items: [{ product_id: '456', quantity: 2 }],
        payment_method: 'stripe'
      }
    end
    
    it 'tracks order creation' do
      expect {
        post :create, params: { order: order_params }
      }.to track_event(Events::OrderCreated)
        .with(hash_including(
          user_id: current_user.id,
          amount: 99.99
        ))
    end
    
    it 'tracks all order flow events' do
      expect {
        post :create, params: { order: order_params }
      }.to track_events(
        Events::OrderValidationStarted,
        Events::OrderValidationCompleted,
        Events::OrderCreated,
        Events::PaymentInitiated
      ).in_order
    end
    
    it 'updates order metrics' do
      expect {
        post :create, params: { order: order_params }
      }.to update_metric('orders.total').by(1)
    end
    
    context 'with invalid params' do
      let(:order_params) { { items: [] } }
      
      it 'tracks validation error' do
        expect {
          post :create, params: { order: order_params }
        }.to track_event(Events::OrderValidationFailed)
      end
      
      it 'does not create order event' do
        expect {
          post :create, params: { order: order_params }
        }.not_to track_event(Events::OrderCreated)
      end
    end
  end
end
```

---

### Example 2: Service Tests

```ruby
# spec/services/payment_service_spec.rb
RSpec.describe PaymentService do
  subject(:service) { described_class.new }
  
  describe '#charge' do
    let(:order) { create(:order, total: 99.99) }
    
    context 'when payment succeeds' do
      before do
        allow(StripeGateway).to receive(:charge).and_return(
          OpenStruct.new(id: 'tx_123', amount: 99.99)
        )
      end
      
      it 'tracks payment success' do
        expect {
          service.charge(order)
        }.to track_event(Events::PaymentSucceeded)
          .with(
            order_id: order.id,
            transaction_id: 'tx_123',
            amount: 99.99
          )
      end
      
      it 'includes trace context' do
        service.charge(order)
        
        event = e11y_last_event(Events::PaymentSucceeded)
        expect(event).to have_trace_id
        expect(event.trace_id).not_to be_nil
      end
    end
    
    context 'when payment fails' do
      before do
        allow(StripeGateway).to receive(:charge).and_raise(
          StripeGateway::CardDeclined.new('Insufficient funds')
        )
      end
      
      it 'tracks payment failure' do
        expect {
          service.charge(order) rescue nil
        }.to track_event(Events::PaymentFailed)
          .with(
            order_id: order.id,
            error: 'Insufficient funds'
          )
      end
    end
  end
end
```

---

### Example 3: Job Tests

```ruby
# spec/jobs/process_order_job_spec.rb
RSpec.describe ProcessOrderJob do
  include ActiveJob::TestHelper
  
  describe '#perform' do
    let(:order) { create(:order) }
    
    it 'tracks job execution' do
      # E11y auto-tracks job lifecycle (UC-010)
      # Just test business events!
      
      expect {
        perform_enqueued_jobs do
          ProcessOrderJob.perform_later(order.id)
        end
      }.to track_events(
        Events::OrderProcessingStarted,
        Events::InventoryChecked,
        Events::PaymentCaptured,
        Events::ShipmentScheduled,
        Events::OrderProcessingCompleted
      ).in_order
    end
    
    it 'preserves trace context' do
      # Set trace context before enqueuing
      E11y::TraceContext.with_context(trace_id: 'abc-123') do
        ProcessOrderJob.perform_later(order.id)
      end
      
      perform_enqueued_jobs
      
      # All events should have same trace_id
      events = e11y_events  # All events
      trace_ids = events.map(&:trace_id).uniq
      expect(trace_ids).to eq(['abc-123'])
    end
    
    it 'tracks errors' do
      allow_any_instance_of(Order).to receive(:process!).and_raise(
        StandardError.new('Processing failed')
      )
      
      expect {
        perform_enqueued_jobs do
          ProcessOrderJob.perform_later(order.id)
        end rescue nil
      }.to track_event(Events::OrderProcessingFailed)
        .with(
          order_id: order.id.to_s,
          error: 'Processing failed'
        )
    end
  end
end
```

---

### Example 4: Integration Tests

```ruby
# spec/integration/order_flow_spec.rb
RSpec.describe 'Order Flow', type: :request do
  it 'tracks complete order lifecycle' do
    # Capture all events during full flow
    e11y_reset!
    
    # 1. Create order
    post '/api/orders', params: { order: order_params }
    expect(response).to have_http_status(:created)
    
    # 2. Process payment
    order_id = JSON.parse(response.body)['id']
    post "/api/orders/#{order_id}/payment", params: { payment: payment_params }
    expect(response).to have_http_status(:ok)
    
    # 3. Ship order
    post "/api/orders/#{order_id}/ship"
    expect(response).to have_http_status(:ok)
    
    # Verify complete event flow
    expect(e11y_event_classes).to match_array([
      Events::OrderCreated,
      Events::PaymentProcessing,
      Events::PaymentSucceeded,
      Events::ShipmentRequested,
      Events::ShipmentCreated,
      Events::NotificationSent
    ])
    
    # Verify all events share same trace_id
    trace_ids = e11y_events.map(&:trace_id).uniq
    expect(trace_ids.size).to eq(1)
    
    # Take snapshot for regression testing
    expect {
      # Re-run full flow
    }.to match_event_snapshot
  end
end
```

---

### Example 5: Event Schema Tests

```ruby
# spec/events/order_created_spec.rb
RSpec.describe Events::OrderCreated do
  describe '.track' do
    it 'validates required fields' do
      expect {
        described_class.track(order_id: '123')  # Missing user_id
      }.to raise_error(E11y::ValidationError, /user_id is missing/)
    end
    
    it 'validates field types' do
      expect {
        described_class.track(
          order_id: '123',
          user_id: '456',
          amount: 'not-a-number'  # Wrong type
        )
      }.to raise_error(E11y::ValidationError, /amount must be a decimal/)
    end
    
    it 'tracks valid event' do
      expect {
        described_class.track(
          order_id: '123',
          user_id: '456',
          amount: 99.99,
          currency: 'USD'
        )
      }.to track_event(Events::OrderCreated)
    end
    
    it 'has valid schema definition' do
      event = build(:e11y_event, :order_created)
      expect(event).to have_valid_schema
    end
  end
end
```

---

## 🔧 Configuration

### Test Configuration

```ruby
# spec/rails_helper.rb
require 'e11y/rspec'

RSpec.configure do |config|
  # Include E11y helpers
  config.include E11y::RSpec::Matchers
  config.include E11y::RSpec::Helpers
  
  # Setup E11y for tests
  config.before(:suite) do
    E11y.configure do |c|
      # Use memory adapter (fast!)
      c.adapters = [E11y::Adapters::MemoryAdapter.new]
      
      # Disable features that slow down tests
      c.rate_limiting.enabled = false
      c.sampling.enabled = false
      c.buffering.enabled = false
      
      # Enable test mode
      c.test_mode = true
    end
  end
  
  # Clear events before each test
  config.before(:each) do
    E11y.reset!
  end
  
  # Snapshot testing
  config.include E11y::RSpec::Snapshot, type: :request
  config.before(:each, :update_snapshot) do
    E11y::Snapshot.update_mode = true
  end
  config.after(:each, :update_snapshot) do
    E11y::Snapshot.update_mode = false
  end
end
```

---

## 💡 Best Practices

### ✅ DO

**1. Test event tracking, not implementation**
```ruby
# ✅ GOOD: Test behavior (event class)
expect {
  service.call
}.to track_event(Events::OrderCreated)

# ❌ BAD: Test implementation details (mocking)
expect(Events::OrderCreated).to receive(:track)
# (unless you specifically need a stub for isolation)
```

**2. Use partial matching for flexible tests**
```ruby
# ✅ GOOD: Test important fields only
expect {
  service.call
}.to track_event(Events::OrderCreated)
  .with(hash_including(order_id: '123'))

# ❌ BAD: Test every field (brittle!)
expect {
  service.call
}.to track_event(Events::OrderCreated)
  .with(
    order_id: '123',
    user_id: '456',
    created_at: Time.current,
    ...  # 20 more fields
  )
```

**3. Test event order when it matters**
```ruby
# ✅ GOOD: Test critical sequences
expect {
  service.call
}.to track_events(
  Events::PaymentAuthorized,
  Events::PaymentCaptured  # Must be after authorized!
).in_order
```

**4. Clear events between tests**
```ruby
# ✅ GOOD: Isolated tests
config.before(:each) do
  E11y.reset!
end
```

---

### ❌ DON'T

**1. Don't test E11y internals**
```ruby
# ❌ BAD: Testing E11y, not your code
expect(E11y::Buffer).to receive(:push)
expect(E11y::Adapters::LokiAdapter).to receive(:write)

# ✅ GOOD: Test your events
expect { action }.to track_event(Events::OrderCreated)
```

**2. Don't use real adapters in tests**
```ruby
# ❌ BAD: Slow tests!
config.adapters = [
  E11y::Adapters::LokiAdapter.new(...)  # Real HTTP calls!
]

# ✅ GOOD: Memory adapter
config.adapters = [
  E11y::Adapters::MemoryAdapter.new  # Fast!
]
```

**3. Don't forget to reset between tests**
```ruby
# ❌ BAD: Events leak between tests
it 'test 1' do
  # tracks event A
end

it 'test 2' do
  events = e11y_events
  # Still contains event A! 💥
end

# ✅ GOOD: Reset before each
config.before(:each) { E11y.reset! }
```

---

## 📚 Related Use Cases

- **[UC-017: Local Development](./UC-017-local-development.md)** - Development setup
- **[UC-016: Rails Logger Migration](./UC-016-rails-logger-migration.md)** - Migration testing

---

## 🎯 Summary

### Testing Features

| Feature | Description | Benefit |
|---------|-------------|---------|
| **RSpec Matchers** | `track_event`, `update_metric` | Expressive tests |
| **Helpers** | `e11y_events`, `e11y_last_event` | Easy assertions |
| **Stubs** | Mock event tracking | Isolation |
| **Factories** | FactoryBot integration | Test data |
| **Snapshots** | Capture event flow | Regression testing |

**Test Speed:**
- Memory adapter: <1ms per event
- No network calls
- No external dependencies

**Developer Experience:**
- Familiar RSpec matchers
- Clear error messages
- Easy to debug

---

**Document Version:** 1.0  
**Last Updated:** January 12, 2026  
**Status:** ✅ Complete

# UC-003 Pattern-Based Metrics: Integration Test Plan

**Task:** FEAT-5399 - UC-003 Phase 2: Planning Complete  
**Date:** 2026-01-26  
**Status:** Planning Complete

---

## 📋 Executive Summary

**Test Strategy:** Event-based integration tests using Rails dummy app, following pattern from rate limiting and high cardinality protection integration tests.

**Scope:** 6 core scenarios covering counter, gauge, histogram metrics, custom labels, pattern matching, and regex performance.

**Test Infrastructure:** Rails dummy app (`spec/dummy`), in-memory adapter, event classes with metrics DSL, Yabeda/Prometheus integration, Registry pattern matching.

**Note:** Tests focus on pattern-based metric matching and Yabeda integration. Assertions verify pattern matching, label extraction, value extraction, and Yabeda metric updates.

---

## 🎯 Test Strategy Overview

### 1. Test Approach

**Pattern:** Follow `spec/integration/rate_limiting_integration_spec.rb` and `spec/integration/high_cardinality_protection_integration_spec.rb` structure

**Key Components:**
- Rails dummy app (`spec/dummy`)
- Event classes in `spec/dummy/app/events/events/` with metric definitions (metrics DSL)
- Registry pattern matching (`E11y::Metrics::Registry.find_matching`)
- Yabeda adapter for Prometheus export
- In-memory adapter for event capture (verify events tracked)
- Yabeda metrics inspection (verify metrics exported correctly)

**Test Structure:**
```ruby
RSpec.describe "Pattern-Based Metrics Integration", :integration do
  let(:memory_adapter) { E11y.config.adapters[:memory] }
  let(:yabeda_adapter) { E11y.config.adapters[:yabeda] }
  let(:registry) { E11y::Metrics::Registry.instance }
  
  before do
    memory_adapter.clear!
    Yabeda.reset! if defined?(Yabeda)
    
    # Configure Yabeda adapter
    yabeda_adapter_instance = E11y::Adapters::Yabeda.new(
      auto_register: true
    )
    E11y.config.adapters[:yabeda] = yabeda_adapter_instance
    
    # Configure Yabeda metrics (will be auto-registered from Registry)
    Yabeda.configure do
      group :e11y do
        # Metrics will be registered automatically from Registry
      end
    end
    Yabeda.configure!
    
    E11y.config.fallback_adapters = [:memory, :yabeda]
  end
  
  after do
    memory_adapter.clear!
    Yabeda.reset! if defined?(Yabeda)
    registry.clear!
  end
  
  describe "Scenario 1: Counter metrics" do
    # Test implementation
  end
  
  # ... other scenarios
end
```

### 2. Assertion Strategy

**Pattern Matching Assertions:**
- ✅ Pattern matching: `Registry.find_matching(event_name)` returns matching metrics
- ✅ Pattern compilation: Patterns compiled to regex correctly
- ✅ Multiple matches: Event matches multiple patterns (all processed)

**Metric Value Assertions:**
- ✅ Counter incremented: `Yabeda.e11y.counter_name.get(labels)` returns correct count
- ✅ Gauge set: `Yabeda.e11y.gauge_name.get(labels)` returns correct value
- ✅ Histogram observed: `Yabeda.e11y.histogram_name.get(labels)` returns correct buckets

**Label Extraction Assertions:**
- ✅ Tags extracted: Labels extracted from event payload correctly
- ✅ Missing tags: Missing tags handled gracefully (nil or omitted)
- ✅ Multiple tags: All tags extracted correctly

**Performance Assertions:**
- ✅ Pattern matching speed: <0.1μs per pattern match
- ✅ Pattern compilation overhead: <1ms for 100 patterns
- ✅ Metric update overhead: <0.1ms per event (with metrics)

---

## 📊 6 Core Integration Test Scenarios

### Scenario 1: Counter Metrics

**Objective:** Verify counter metrics work with pattern matching and label extraction.

**Setup:**
- Event class: `Events::OrderPaid` with counter metric
- Pattern: exact match (event name: `"Events::OrderPaid"`)
- Tags: `[:currency]`

**Test Steps:**
1. Define event class with counter metric:
   ```ruby
   class Events::OrderPaid < E11y::Event::Base
     schema do
       required(:order_id).filled(:string)
       required(:currency).filled(:string)
     end
     
     metrics do
       counter :orders_paid_total, tags: [:currency]
     end
   end
   ```
2. Track event: `Events::OrderPaid.track(order_id: '123', currency: 'USD')`
3. Verify pattern matching: `registry.find_matching("Events::OrderPaid")` returns metric config
4. Verify label extraction: Tags extracted from event payload (`currency: 'USD'`)
5. Verify Yabeda export: Counter incremented in Yabeda (`Yabeda.e11y.orders_paid_total.get(currency: 'USD')`)

**Assertions:**
- Pattern matches event name: `expect(matching_metrics).not_to be_empty`
- Counter incremented: `expect(Yabeda.e11y.orders_paid_total.get(currency: 'USD')).to eq(1)`
- Labels extracted correctly: Verify tags in Yabeda metric labels

**Test Data:**
- Event: `Events::OrderPaid`
- Payload: `{ order_id: '123', currency: 'USD' }`
- Expected metric: `orders_paid_total{currency="USD"}` = 1

---

### Scenario 2: Gauge Metrics

**Objective:** Verify gauge metrics work with value extraction.

**Setup:**
- Event class: `Events::OrderStatus` with gauge metric
- Pattern: exact match (event name: `"Events::OrderStatus"`)
- Value field: `:status`
- Tags: `[:order_id]`

**Test Steps:**
1. Define event class with gauge metric:
   ```ruby
   class Events::OrderStatus < E11y::Event::Base
     schema do
       required(:order_id).filled(:string)
       required(:status).filled(:string)
     end
     
     metrics do
       gauge :order_status, value: :status, tags: [:order_id]
     end
   end
   ```
2. Track event: `Events::OrderStatus.track(order_id: '123', status: 'active')`
3. Verify value extraction: Value extracted from event payload (`status: 'active'`)
4. Verify Yabeda export: Gauge set in Yabeda (`Yabeda.e11y.order_status.get(order_id: '123')`)

**Assertions:**
- Value extracted correctly: Verify value in event payload
- Gauge set: `expect(Yabeda.e11y.order_status.get(order_id: '123')).to eq('active')`
- Labels extracted correctly: Verify tags in Yabeda metric labels

**Test Data:**
- Event: `Events::OrderStatus`
- Payload: `{ order_id: '123', status: 'active' }`
- Expected metric: `order_status{order_id="123"}` = 'active'

---

### Scenario 3: Histogram Metrics

**Objective:** Verify histogram metrics work with buckets and value extraction.

**Setup:**
- Event class: `Events::OrderAmount` with histogram metric
- Pattern: exact match (event name: `"Events::OrderAmount"`)
- Value field: `:amount`
- Buckets: `[10, 50, 100, 500, 1000]`
- Tags: `[:currency]`

**Test Steps:**
1. Define event class with histogram metric:
   ```ruby
   class Events::OrderAmount < E11y::Event::Base
     schema do
       required(:order_id).filled(:string)
       required(:amount).filled(:float)
       required(:currency).filled(:string)
     end
     
     metrics do
       histogram :orders_amount, value: :amount, tags: [:currency], buckets: [10, 50, 100, 500, 1000]
     end
   end
   ```
2. Track events with various amounts: `[5, 25, 75, 150, 250, 750]`
3. Verify value extraction: Values extracted from event payload
4. Verify bucket assignment: Values assigned to correct buckets
5. Verify Yabeda export: Histogram buckets updated in Yabeda

**Assertions:**
- Values extracted correctly: Verify values in event payloads
- Buckets assigned correctly: Verify bucket counts in Yabeda histogram
- Histogram updated: `expect(Yabeda.e11y.orders_amount.get(currency: 'USD')).to be_a(Hash)` (buckets)

**Test Data:**
- Event: `Events::OrderAmount`
- Payloads: 
  - `{ order_id: '1', amount: 5, currency: 'USD' }` → bucket `le="10"`
  - `{ order_id: '2', amount: 25, currency: 'USD' }` → bucket `le="50"`
  - `{ order_id: '3', amount: 75, currency: 'USD' }` → bucket `le="100"`
  - `{ order_id: '4', amount: 150, currency: 'USD' }` → bucket `le="500"`
  - `{ order_id: '5', amount: 750, currency: 'USD' }` → bucket `le="1000"`

---

### Scenario 4: Custom Labels (Tags)

**Objective:** Verify custom labels extracted from event payload.

**Setup:**
- Event class: `Events::OrderPayment` with multiple tags
- Pattern: exact match (event name: `"Events::OrderPayment"`)
- Tags: `[:currency, :payment_method, :status]`

**Test Steps:**
1. Define event class with multiple tags:
   ```ruby
   class Events::OrderPayment < E11y::Event::Base
     schema do
       required(:order_id).filled(:string)
       required(:currency).filled(:string)
       required(:payment_method).filled(:string)
       required(:status).filled(:string)
     end
     
     metrics do
       counter :orders_payment_total, tags: [:currency, :payment_method, :status]
     end
   end
   ```
2. Track event: `Events::OrderPayment.track(order_id: '123', currency: 'USD', payment_method: 'stripe', status: 'success')`
3. Verify label extraction: All tags extracted from payload
4. Verify Yabeda export: Labels exported correctly

**Assertions:**
- All tags extracted: Verify all tags present in Yabeda metric labels
- Labels exported correctly: `expect(Yabeda.e11y.orders_payment_total.get(currency: 'USD', payment_method: 'stripe', status: 'success')).to eq(1)`
- Missing tags handled: Test with missing optional tags (should handle gracefully)

**Test Data:**
- Event: `Events::OrderPayment`
- Payload: `{ order_id: '123', currency: 'USD', payment_method: 'stripe', status: 'success' }`
- Expected metric: `orders_payment_total{currency="USD",payment_method="stripe",status="success"}` = 1

---

### Scenario 5: Pattern Matching

**Objective:** Verify pattern matching works with different patterns (exact, `*`, `**`).

**Setup:**
- Multiple event classes: `Events::OrderPaid`, `Events::OrderCreated`, `Events::OrderCancelled`
- Multiple metric patterns:
  - Exact: `"Events::OrderPaid"`
  - Wildcard: `"Events::Order.*"`
  - Double wildcard: `"Events::Order.**"`

**Test Steps:**
1. Define event classes:
   ```ruby
   class Events::OrderPaid < E11y::Event::Base
     metrics do
       counter :orders_paid_total, tags: [:currency]
     end
   end
   
   class Events::OrderCreated < E11y::Event::Base
     metrics do
       counter :orders_created_total, tags: [:status]
     end
   end
   ```
2. Register metrics with different patterns (via Registry directly for testing):
   ```ruby
   registry.register(
     type: :counter,
     pattern: "Events::Order.*",
     name: :orders_all_total,
     tags: [:event_name]
   )
   ```
3. Track events: `Events::OrderPaid.track(...)`, `Events::OrderCreated.track(...)`
4. Verify pattern matching: Correct metrics matched for each event
5. Verify multiple matches: Event matches multiple patterns (all processed)

**Assertions:**
- Exact pattern matches: `expect(registry.find_matching("Events::OrderPaid").map { |m| m[:name] }).to include(:orders_paid_total)`
- Wildcard pattern matches: `expect(registry.find_matching("Events::OrderPaid").map { |m| m[:name] }).to include(:orders_all_total)`
- Double wildcard matches: Test with `Events::Order.Paid.Completed` (if applicable)
- Multiple patterns processed: Verify all matching metrics updated

**Test Data:**
- Events: `Events::OrderPaid`, `Events::OrderCreated`
- Patterns:
  - Exact: `"Events::OrderPaid"` → matches `Events::OrderPaid` only
  - Wildcard: `"Events::Order.*"` → matches `Events::OrderPaid`, `Events::OrderCreated`
  - Double wildcard: `"Events::Order.**"` → matches `Events::Order.Paid.Completed` (if exists)

---

### Scenario 6: Regex Performance

**Objective:** Verify pattern matching performance meets requirements (<0.1μs per pattern match).

**Setup:**
- 100 registered metrics with various patterns
- Benchmark pattern matching speed

**Test Steps:**
1. Register 100 metrics with different patterns:
   ```ruby
   100.times do |i|
     registry.register(
       type: :counter,
       pattern: "Events::Test#{i}.*",
       name: "test_#{i}_total".to_sym,
       tags: []
     )
   end
   ```
2. Benchmark `Registry.find_matching(event_name)` for 10,000 events:
   ```ruby
   require 'benchmark'
   times = []
   10_000.times do |i|
     event_name = "Events::Test#{i % 100}.Paid"
     time = Benchmark.realtime do
       registry.find_matching(event_name)
     end
     times << time
   end
   average_time = times.sum / times.size
   ```
3. Calculate average time per pattern match
4. Verify performance: <0.1μs per pattern match

**Assertions:**
- Pattern matching speed: `expect(average_time).to be < 0.0001` (0.1μs = 0.0001ms)
- Pattern compilation overhead: Measure time to register 100 patterns (<1ms)
- No performance degradation: Verify performance consistent with many patterns

**Test Data:**
- 100 metrics with patterns: `"Events::Test0.*"`, `"Events::Test1.*"`, ..., `"Events::Test99.*"`
- 10,000 event names: `"Events::Test0.Paid"`, `"Events::Test1.Paid"`, ..., `"Events::Test99.Paid"` (cycled)

---

## 📝 Test Data Requirements

### Event Classes

**Required Event Classes:**
1. `Events::OrderPaid` - Counter metric, tags: `[:currency]`
2. `Events::OrderStatus` - Gauge metric, value: `:status`, tags: `[:order_id]`
3. `Events::OrderAmount` - Histogram metric, value: `:amount`, buckets: `[10, 50, 100, 500, 1000]`, tags: `[:currency]`
4. `Events::OrderPayment` - Counter metric, tags: `[:currency, :payment_method, :status]`
5. `Events::OrderCreated` - Counter metric, tags: `[:status]` (for pattern matching tests)

**Location:** `spec/dummy/app/events/events/`

### Test Patterns

**Required Patterns:**
- Exact: `"Events::OrderPaid"` (from event class metrics DSL)
- Wildcard: `"Events::Order.*"` (registered via Registry for testing)
- Double wildcard: `"Events::Order.**"` (registered via Registry for testing)
- Global: `"*"` (matches all events, if needed)

### Test Payloads

**Required Payloads:**
- Counter: `{ order_id: '123', currency: 'USD' }`
- Gauge: `{ order_id: '123', status: 'active' }`
- Histogram: `{ order_id: '1', amount: 25, currency: 'USD' }`
- Multiple tags: `{ order_id: '123', currency: 'USD', payment_method: 'stripe', status: 'success' }`

---

## ✅ Definition of Done

**Planning is complete when:**
1. ✅ All 6 scenarios planned with detailed test steps
2. ✅ Test data requirements documented (event classes, patterns, payloads)
3. ✅ Assertion strategy defined for each scenario
4. ✅ Test infrastructure requirements documented
5. ✅ Performance benchmarks defined (regex performance scenario)
6. ✅ Test structure follows existing integration test patterns

---

## 📚 References

- **UC-003 Analysis:** `docs/analysis/UC-003-PATTERN-BASED-METRICS-ANALYSIS.md`
- **UC-003 Use Case:** `docs/use_cases/UC-003-event-metrics.md`
- **Integration Tests:** `spec/integration/pattern_metrics_integration_spec.rb` ✅ (All 6 scenarios implemented)
- **Registry Implementation:** `lib/e11y/metrics/registry.rb`
- **Metrics DSL:** `lib/e11y/event/base.rb`
- **Yabeda Adapter:** `lib/e11y/adapters/yabeda.rb`
- **Rate Limiting Tests:** `spec/integration/rate_limiting_integration_spec.rb` (reference pattern)
- **High Cardinality Tests:** `spec/integration/high_cardinality_protection_integration_spec.rb` (reference pattern)

---

**Planning Complete:** 2026-01-26  
**Next Step:** UC-003 Phase 3: Skeleton Complete

# UC-003 Pattern-Based Metrics: Integration Test Analysis

**Task:** FEAT-5398 - UC-003 Phase 1: Analysis Complete  
**Date:** 2026-01-26  
**Status:** Analysis Complete

---

## 📋 Executive Summary

**Current State:**
- ✅ **Implemented:** Pattern-based metric matching via `E11y::Metrics::Registry`
- ✅ **Implemented:** Event-level metrics DSL (`metrics do ... end`)
- ✅ **Implemented:** Glob-style pattern compilation (exact, `*`, `**`)
- ✅ **Implemented:** Yabeda integration via `E11y::Adapters::Yabeda`
- ✅ **Implemented:** Automatic metric registration at boot time
- ✅ **Implemented:** Pattern matching at runtime (`Registry.find_matching`)

**Unit Test Coverage:** Good (comprehensive tests for Registry pattern matching, Metrics DSL, pattern compilation)

**Integration Test Coverage:** ✅ **COMPLETE** - All 6 scenarios implemented in `spec/integration/pattern_metrics_integration_spec.rb`

**Integration Test Status:**
1. ✅ Counter metrics (pattern matching, label extraction, Yabeda export) - Scenario 1 implemented
2. ✅ Gauge metrics (value extraction, Yabeda export) - Scenario 2 implemented
3. ✅ Histogram metrics (value extraction, buckets, Yabeda export) - Scenario 3 implemented
4. ✅ Custom labels (tags extraction from event payload) - Scenario 4 implemented
5. ✅ Pattern matching scenarios (exact match, `*`, `**`, multiple patterns) - Scenario 5 implemented
6. ✅ Regex performance benchmarks (pattern compilation overhead, matching speed) - Scenario 6 implemented

**Test File:** `spec/integration/pattern_metrics_integration_spec.rb` (372 lines)
**Test Scenarios:** All 6 scenarios from planning document are implemented and passing

---

## 🔍 1. Current Implementation Analysis

### 1.1. Code Structure

**Location:** `lib/e11y/metrics/registry.rb`

**Key Components:**
- `E11y::Metrics::Registry` - Singleton registry for metric configurations
- `compile_pattern(pattern)` - Converts glob patterns to regex (boot-time compilation)
- `find_matching(event_name)` - Runtime pattern matching (regex-based)
- `register(config)` - Registers metric configuration with pattern

**Pattern Syntax:**
- **Exact match**: `"order.paid"` matches `"order.paid"` only
- **Single wildcard**: `"order.*"` matches `"order.created"`, `"order.paid"` (single segment)
- **Double wildcard**: `"order.**"` matches `"order.paid.completed"` (multiple segments)
- **Global wildcard**: `"*"` matches any event name

**Pattern Compilation:**
- Patterns compiled to regex at registration time (not runtime)
- Regex format: `/\A#{compiled_pattern}\z/` (anchored, full match)
- Performance: ~0.1μs per pattern match (from UC-003 docs)

### 1.2. Current Features

| Feature | Status | Implementation |
|---------|--------|----------------|
| Pattern-based matching | ✅ Implemented | `Registry.find_matching(event_name)` |
| Event-level metrics DSL | ✅ Implemented | `metrics do ... end` in event classes |
| Counter metrics | ✅ Implemented | `counter :name, tags: [...]` |
| Histogram metrics | ✅ Implemented | `histogram :name, value: :field, buckets: [...]` |
| Gauge metrics | ✅ Implemented | `gauge :name, value: :field` |
| Custom labels (tags) | ✅ Implemented | Tags extracted from event payload |
| Pattern compilation | ✅ Implemented | Glob → regex at registration time |
| Yabeda integration | ✅ Implemented | Metrics exported via `E11y::Adapters::Yabeda` |
| Multiple pattern matches | ✅ Implemented | All matching patterns processed |
| Conflict detection | ✅ Implemented | Label/type conflicts validated at boot |

### 1.3. Configuration

**Current API (Event-Level DSL):**
```ruby
class Events::OrderPaid < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:float)
    required(:currency).filled(:string)
  end

  metrics do
    counter :orders_paid_total, tags: [:currency]
    histogram :orders_paid_amount, value: :amount, tags: [:currency], buckets: [10, 50, 100]
  end
end
```

**Pattern Matching Flow:**
1. Event tracked: `Events::OrderPaid.track(...)`
2. Event name resolved: `"Events::OrderPaid"` (from class name)
3. Registry.find_matching: Finds all metrics with matching patterns
4. Yabeda adapter: Extracts labels, applies cardinality protection, updates Yabeda metrics
5. Prometheus export: Yabeda metrics exported to Prometheus

**Note:** Global pattern-based metrics (`E11y.configure { metric_pattern ... }`) are NOT implemented (per AUDIT-024). Only event-level DSL is available.

---

## 📊 2. Unit Test Coverage Analysis

### 2.1. Test File: `spec/e11y/metrics/registry_spec.rb`

**Coverage Summary:**
- ✅ **Pattern matching tests** (exact, `*`, `**`, multiple patterns)
- ✅ **Pattern compilation tests** (glob → regex conversion)
- ✅ **Conflict detection tests** (label conflicts, type conflicts)
- ✅ **Registration tests** (counter, histogram, gauge)
- ✅ **find_matching tests** (single match, multiple matches, no matches)

**Key Test Scenarios:**
- Exact pattern matching: `"order.paid"` matches `"order.paid"`
- Wildcard matching: `"order.*"` matches `"order.created"`, `"order.paid"`
- Double wildcard: `"order.**"` matches `"order.paid.completed"`
- Multiple patterns: Same event matches multiple metric patterns
- Case sensitivity: Patterns are case-sensitive

### 2.2. Test File: `spec/e11y/event/metrics_dsl_spec.rb`

**Coverage Summary:**
- ✅ **Metrics DSL tests** (counter, histogram, gauge definitions)
- ✅ **Tag extraction tests** (tags from event payload)
- ✅ **Value extraction tests** (value from event payload for histogram/gauge)
- ✅ **Registration tests** (metrics registered in Registry at boot)

**Key Test Scenarios:**
- Counter definition: `counter :name, tags: [:field]`
- Histogram definition: `histogram :name, value: :field, buckets: [...]`
- Gauge definition: `gauge :name, value: :field`
- Tag extraction: Tags extracted from event payload
- Value extraction: Value extracted from event payload (symbol or proc)

---

## 🎯 3. Integration Test Requirements

### 3.1. Test Infrastructure

**Pattern:** Follow `spec/integration/rate_limiting_integration_spec.rb` structure

**Key Components:**
- Rails dummy app (`spec/dummy`)
- Event classes in `spec/dummy/app/events/events/` with metric definitions
- Yabeda adapter configured in test `before` blocks
- In-memory adapter for event capture
- Yabeda metrics inspection (verify metrics exported correctly)

**Test Structure:**
```ruby
RSpec.describe "Pattern-Based Metrics Integration", :integration do
  let(:memory_adapter) { E11y.config.adapters[:memory] }
  let(:yabeda_adapter) { E11y.config.adapters[:yabeda] }
  
  before do
    memory_adapter.clear!
    Yabeda.reset! if defined?(Yabeda)
    
    # Configure Yabeda adapter
    yabeda_adapter_instance = E11y::Adapters::Yabeda.new(...)
    E11y.config.adapters[:yabeda] = yabeda_adapter_instance
    
    # Configure Yabeda metrics
    Yabeda.configure do
      group :e11y do
        # Metrics defined here
      end
    end
    Yabeda.configure!
    
    E11y.config.fallback_adapters = [:memory, :yabeda]
  end
  
  after do
    memory_adapter.clear!
    Yabeda.reset! if defined?(Yabeda)
    E11y::Metrics::Registry.instance.clear!
  end
  
  describe "Scenario 1: Counter metrics" do
    # Test implementation
  end
  
  # ... other scenarios
end
```

### 3.2. Assertion Strategy

**Metric-Based Assertions:**
- ✅ Pattern matching: `Registry.find_matching(event_name)` returns matching metrics
- ✅ Label extraction: Tags extracted from event payload correctly
- ✅ Value extraction: Values extracted for histogram/gauge metrics
- ✅ Yabeda export: Metrics exported to Yabeda with correct labels/values
- ✅ Prometheus format: Metrics exported in Prometheus format

**Performance Assertions:**
- ✅ Pattern compilation overhead: <1ms for 100 patterns
- ✅ Pattern matching speed: <0.1μs per pattern match
- ✅ Metric update overhead: <0.1ms per event (with metrics)

---

## 📋 4. Integration Test Scenarios

### Scenario 1: Counter Metrics

**Objective:** Verify counter metrics work with pattern matching.

**Setup:**
- Event class with counter metric definition
- Pattern: exact match (event name)

**Test Steps:**
1. Define event class with counter metric
2. Track event: `Events::OrderPaid.track(currency: 'USD')`
3. Verify pattern matching: `Registry.find_matching("Events::OrderPaid")` returns metric
4. Verify label extraction: Tags extracted from event payload
5. Verify Yabeda export: Counter incremented in Yabeda

**Assertions:**
- Pattern matches event name
- Counter incremented in Yabeda
- Labels (tags) extracted correctly

### Scenario 2: Gauge Metrics

**Objective:** Verify gauge metrics work with value extraction.

**Setup:**
- Event class with gauge metric definition
- Value field in event payload

**Test Steps:**
1. Define event class with gauge metric (`value: :amount`)
2. Track event: `Events::OrderPaid.track(amount: 99.99, currency: 'USD')`
3. Verify value extraction: Value extracted from event payload
4. Verify Yabeda export: Gauge set in Yabeda

**Assertions:**
- Value extracted correctly
- Gauge set in Yabeda with correct value
- Labels extracted correctly

### Scenario 3: Histogram Metrics

**Objective:** Verify histogram metrics work with buckets and value extraction.

**Setup:**
- Event class with histogram metric definition
- Custom buckets: `[10, 50, 100, 500, 1000]`

**Test Steps:**
1. Define event class with histogram metric (`value: :amount`, `buckets: [10, 50, 100]`)
2. Track events with various amounts: `[5, 25, 75, 150]`
3. Verify value extraction: Values extracted from event payload
4. Verify bucket assignment: Values assigned to correct buckets
5. Verify Yabeda export: Histogram buckets updated in Yabeda

**Assertions:**
- Values extracted correctly
- Buckets assigned correctly
- Histogram buckets updated in Yabeda

### Scenario 4: Custom Labels (Tags)

**Objective:** Verify custom labels extracted from event payload.

**Setup:**
- Event class with multiple tags: `tags: [:currency, :payment_method, :status]`

**Test Steps:**
1. Define event class with multiple tags
2. Track event: `Events::OrderPaid.track(currency: 'USD', payment_method: 'stripe', status: 'success')`
3. Verify label extraction: All tags extracted from payload
4. Verify Yabeda export: Labels exported correctly

**Assertions:**
- All tags extracted from payload
- Labels exported to Yabeda correctly
- Missing tags handled gracefully (nil or omitted)

### Scenario 5: Pattern Matching

**Objective:** Verify pattern matching works with different patterns.

**Setup:**
- Multiple event classes with different names
- Multiple metric patterns (exact, `*`, `**`)

**Test Steps:**
1. Register metrics with different patterns:
   - Exact: `"Events::OrderPaid"`
   - Wildcard: `"Events::Order.*"`
   - Double wildcard: `"Events::Order.**"`
2. Track events: `Events::OrderPaid.track(...)`, `Events::OrderCreated.track(...)`
3. Verify pattern matching: Correct metrics matched for each event
4. Verify multiple matches: Event matches multiple patterns (all processed)

**Assertions:**
- Exact pattern matches correctly
- Wildcard pattern matches correctly
- Double wildcard pattern matches correctly
- Multiple patterns match same event (all processed)

### Scenario 6: Regex Performance

**Objective:** Verify pattern matching performance meets requirements (<0.1μs per pattern).

**Setup:**
- 100 registered metrics with various patterns
- Benchmark pattern matching speed

**Test Steps:**
1. Register 100 metrics with different patterns
2. Benchmark `Registry.find_matching(event_name)` for 10,000 events
3. Calculate average time per pattern match
4. Verify performance: <0.1μs per pattern match

**Assertions:**
- Pattern matching speed: <0.1μs per pattern
- Pattern compilation overhead: <1ms for 100 patterns
- No performance degradation with many patterns

---

## 🔗 5. Dependencies & Integration Points

### 5.1. Yabeda Integration

**Integration Point:** `E11y::Adapters::Yabeda`

**Flow:**
1. Event tracked → `Event.track(...)`
2. Middleware pipeline → `Routing` middleware routes to `:yabeda` adapter
3. Yabeda adapter → `write(event_data)` called
4. Registry.find_matching → Finds matching metrics
5. Label extraction → Tags extracted from event payload
6. Cardinality protection → Labels filtered (if enabled)
7. Yabeda metric update → Counter incremented / Histogram observed / Gauge set
8. Prometheus export → Yabeda metrics exported to Prometheus

**Test Requirements:**
- Yabeda adapter configured in test `before` blocks
- Yabeda metrics registered before adapter creation
- Yabeda.reset! called in `after` blocks for test isolation

### 5.2. Event System Integration

**Integration Point:** `E11y::Event::Base`

**Flow:**
1. Event class loaded → `metrics do ... end` evaluated
2. Metrics registered → `register_metrics_in_registry!` called
3. Registry.register → Metrics registered with pattern (event name)
4. Event tracked → `Event.track(...)` called
5. Event name resolved → `event_name` method returns class name

**Test Requirements:**
- Event classes defined in `spec/dummy/app/events/events/`
- Metrics DSL evaluated at class load time
- Event names match patterns correctly

### 5.3. Registry Integration

**Integration Point:** `E11y::Metrics::Registry`

**Flow:**
1. Metrics registered → `Registry.register(config)` called
2. Pattern compiled → `compile_pattern(pattern)` converts glob to regex
3. Pattern stored → Regex stored in `pattern_regex` field
4. Event tracked → `Registry.find_matching(event_name)` called
5. Pattern matched → Regex matches event name

**Test Requirements:**
- Registry cleared in `after` blocks for test isolation
- Patterns compiled correctly (glob → regex)
- Pattern matching works correctly (exact, `*`, `**`)

---

## ⚠️ 6. Known Limitations & Gaps

### 6.1. Global Pattern-Based Metrics

**Status:** ❌ **NOT IMPLEMENTED**

**Gap:** Global `E11y.configure { metric_pattern ... }` API is not implemented (per AUDIT-024).

**Current Workaround:** Use event-level DSL (`metrics do ... end`) instead.

**Impact:** Integration tests should focus on event-level DSL, not global configuration.

### 6.2. Pattern Performance

**Status:** ✅ **IMPLEMENTED** (per UC-003 docs: ~0.1μs per pattern match)

**Note:** Performance benchmarks should verify this claim in integration tests.

### 6.3. Multiple Pattern Matches

**Status:** ✅ **IMPLEMENTED** (all matching patterns processed)

**Note:** Integration tests should verify that multiple patterns matching same event all process correctly.

---

## 📝 7. Test Data Requirements

### 7.1. Event Classes

**Required Event Classes:**
- `Events::OrderPaid` - Counter metric, tags: `[:currency]`
- `Events::OrderCreated` - Counter metric, tags: `[:status]`
- `Events::OrderAmount` - Histogram metric, value: `:amount`, buckets: `[10, 50, 100]`
- `Events::OrderStatus` - Gauge metric, value: `:status`
- `Events::OrderPayment` - Multiple tags: `[:currency, :payment_method, :status]`

### 7.2. Test Patterns

**Required Patterns:**
- Exact: `"Events::OrderPaid"`
- Wildcard: `"Events::Order.*"`
- Double wildcard: `"Events::Order.**"`
- Global: `"*"` (matches all events)

### 7.3. Test Payloads

**Required Payloads:**
- Counter: `{ currency: 'USD' }`
- Histogram: `{ amount: 99.99, currency: 'USD' }`
- Gauge: `{ status: 'active' }`
- Multiple tags: `{ currency: 'USD', payment_method: 'stripe', status: 'success' }`

---

## ✅ 8. Definition of Done

**Integration tests status:** ✅ **COMPLETE** - All requirements met

**Verification:**
1. ✅ All 6 scenarios implemented and passing (`spec/integration/pattern_metrics_integration_spec.rb`)
2. ✅ Counter metrics tested (pattern matching, label extraction, Yabeda export) - Scenario 1
3. ✅ Gauge metrics tested (value extraction, Yabeda export) - Scenario 2
4. ✅ Histogram metrics tested (value extraction, buckets, Yabeda export) - Scenario 3
5. ✅ Custom labels tested (tag extraction from payload) - Scenario 4
6. ✅ Pattern matching tested (exact, `*`, `**`, multiple patterns) - Scenario 5
7. ✅ Regex performance tested (<0.1μs per pattern match) - Scenario 6
8. ✅ Yabeda integration verified (metrics exported correctly)
9. ✅ Test isolation verified (Registry cleared between tests)
10. ✅ All tests pass in CI

---

## 📚 9. References

- **UC-003:** `docs/use_cases/UC-003-pattern-based-metrics.md`
- **UC-003 Planning:** `docs/planning/UC-003-PATTERN-BASED-METRICS-PLAN.md`
- **Integration Tests:** `spec/integration/pattern_metrics_integration_spec.rb` ✅ (All 6 scenarios implemented)
- **ADR-002:** `docs/ADR-002-metrics-yabeda.md` (Section 3: Pattern-Based Metrics)
- **AUDIT-024:** `docs/researches/post_implementation/AUDIT-024-UC-003-PATTERN-MATCHING.md`
- **Registry Implementation:** `lib/e11y/metrics/registry.rb`
- **Metrics DSL:** `lib/e11y/event/base.rb` (metrics DSL)
- **Yabeda Adapter:** `lib/e11y/adapters/yabeda.rb`

---

**Analysis Complete:** 2026-01-26  
**Next Step:** UC-003 Phase 2: Planning Complete

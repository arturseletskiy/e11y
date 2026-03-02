# UC-014 Adaptive Sampling: Integration Test Analysis

**Task:** FEAT-5414 - UC-014 Phase 1: Analysis Complete  
**Date:** 2026-01-26  
**Status:** Analysis Complete

---

## 📋 Executive Summary

**Current State:**
- ✅ **Implemented:** Error-Based Adaptive Sampling (`E11y::Sampling::ErrorSpikeDetector`) - 100% sampling during error spikes
- ✅ **Implemented:** Load-Based Adaptive Sampling (`E11y::Sampling::LoadMonitor`) - Tiered sampling (100%/50%/10%/1%) based on event volume
- ✅ **Implemented:** Value-Based Sampling (`E11y::Sampling::ValueExtractor`) - Event DSL for sampling by payload values
- ✅ **Implemented:** Stratified Sampling (`E11y::Sampling::StratifiedTracker`) - SLO-accurate sampling with correction (C11 Resolution)
- ✅ **Implemented:** Sampling Middleware (`E11y::Middleware::Sampling`) - Applies sampling decisions, drops unsampled events
- ✅ **Implemented:** Trace-aware sampling (C05 Resolution) - Same trace_id gets same sampling decision
- ⚠️ **PARTIAL:** Budget exhaustion (sampling reduces when budget exceeded) - May not be fully implemented
- ⚠️ **PARTIAL:** Priority sampling (high-value events always sampled) - Value-based sampling exists but priority may not be explicit

**Unit Test Coverage:** Good (comprehensive tests for ErrorSpikeDetector, LoadMonitor, ValueExtractor, StratifiedTracker, Sampling middleware)

**Integration Test Coverage:** ❌ **NONE** - No integration tests exist for adaptive sampling

**Gap Analysis:** Integration tests needed for:
1. Dynamic rate adjustment (sampling rate changes based on conditions)
2. Error spike detection (100% sampling during error spikes)
3. Traffic patterns (load-based tiered sampling)
4. Budget exhaustion (sampling reduces when budget exceeded)
5. Priority sampling (high-value events always sampled)
6. Value-based sampling (events with high values always sampled)
7. Stratified sampling (error/success ratio preserved)
8. Trace-aware sampling (same trace_id = same sampling decision)

---

## 🔍 1. Current Implementation Analysis

### 1.1. Code Structure

**Location:** `lib/e11y/middleware/sampling.rb`, `lib/e11y/sampling/error_spike_detector.rb`, `lib/e11y/sampling/load_monitor.rb`, `lib/e11y/sampling/value_extractor.rb`, `lib/e11y/sampling/stratified_tracker.rb`

**Key Components:**
- `E11y::Middleware::Sampling` - Applies sampling decisions, drops unsampled events
- `E11y::Sampling::ErrorSpikeDetector` - Detects error spikes, triggers 100% sampling
- `E11y::Sampling::LoadMonitor` - Monitors event rate, adjusts sampling based on load tiers
- `E11y::Sampling::ValueExtractor` - Extracts values from event payload for value-based sampling
- `E11y::Sampling::StratifiedTracker` - Tracks error/success ratio, preserves SLO accuracy

**Sampling Flow:**
1. Event tracked → `Event.track(...)`
2. Sampling middleware → Determines if event should be sampled
3. Priority chain: Error spike → Value-based → Load-based → Severity → Event-level → Default
4. Event dropped if not sampled (returns nil)
5. Event passed to next middleware if sampled

**Sampling Decision Priority:**
1. **Error spike override** (100% during spike) - HIGHEST
2. Value-based sampling (100% for high-value events)
3. Load-based adaptive (10-100% based on load)
4. Severity-based defaults
5. Event-level sample_rate
6. Default sample_rate (fallback)

### 1.2. Current Features

| Feature | Status | Implementation |
|---------|--------|----------------|
| Error-Based Adaptive | ✅ Implemented | ErrorSpikeDetector detects spikes, triggers 100% sampling |
| Load-Based Adaptive | ✅ Implemented | LoadMonitor monitors event rate, tiered sampling (100%/50%/10%/1%) |
| Value-Based Sampling | ✅ Implemented | ValueExtractor extracts payload values, event DSL for thresholds |
| Stratified Sampling | ✅ Implemented | StratifiedTracker tracks error/success ratio, SLO correction |
| Trace-Aware Sampling | ✅ Implemented | Same trace_id gets same sampling decision (C05 Resolution) |
| Budget Exhaustion | ⚠️ PARTIAL | May not be fully implemented |
| Priority Sampling | ⚠️ PARTIAL | Value-based exists but priority may not be explicit |

### 1.3. Configuration

**Current API:**
```ruby
# Error-Based Adaptive Sampling
E11y.configure do |config|
  config.pipeline.use E11y::Middleware::Sampling,
    default_sample_rate: 0.1,
    error_based_adaptive: true,
    error_spike_config: {
      window: 60,
      absolute_threshold: 100,
      relative_threshold: 3.0,
      spike_duration: 300
    }
end

# Load-Based Adaptive Sampling
E11y.configure do |config|
  config.pipeline.use E11y::Middleware::Sampling,
    default_sample_rate: 0.1,
    load_based_adaptive: true,
    load_monitor_config: {
      window: 60,
      normal_threshold: 1_000,
      high_threshold: 10_000,
      very_high_threshold: 50_000,
      overload_threshold: 100_000
    }
end

# Value-Based Sampling (Event DSL)
class Events::OrderPaid < E11y::Event::Base
  sample_by_value field: "amount",
                  operator: :greater_than,
                  threshold: 1000,
                  sample_rate: 1.0
end
```

---

## 📊 2. Unit Test Coverage Analysis

### 2.1. Test File: `spec/e11y/sampling/error_spike_detector_spec.rb`

**Coverage Summary:**
- ✅ **Error spike detection** (absolute threshold, relative threshold)
- ✅ **Sliding window** (60-second window)
- ✅ **Baseline tracking** (exponential moving average)
- ✅ **Spike duration** (maintains elevated sampling)

**Key Test Scenarios:**
- Absolute threshold detection (100 errors/min)
- Relative threshold detection (3x baseline)
- Spike duration (5 minutes)
- Baseline calculation

### 2.2. Test File: `spec/e11y/sampling/load_monitor_spec.rb`

**Coverage Summary:**
- ✅ **Load monitoring** (event rate calculation)
- ✅ **Tiered sampling** (4 load levels)
- ✅ **Sliding window** (60-second window)
- ✅ **Thread safety** (concurrent access)

**Key Test Scenarios:**
- Normal load (<1k events/sec → 100% sampling)
- High load (1k-10k events/sec → 50% sampling)
- Very high load (10k-50k events/sec → 10% sampling)
- Overload (>100k events/sec → 1% sampling)

### 2.3. Test File: `spec/e11y/sampling/value_extractor_spec.rb`

**Coverage Summary:**
- ✅ **Value extraction** (payload field extraction)
- ✅ **Operators** (greater_than, less_than, equals, in_range)
- ✅ **Type coercion** (numeric strings to floats)
- ✅ **Nil handling** (missing values)

**Key Test Scenarios:**
- Field extraction (nested fields with dot notation)
- Operator evaluation (>, <, ==, in_range)
- Type coercion (string to float)
- Nil handling

### 2.4. Test File: `spec/e11y/sampling/stratified_tracker_spec.rb`

**Coverage Summary:**
- ✅ **Stratified tracking** (error/success ratio)
- ✅ **Sampling correction** (correction factors)
- ✅ **SLO accuracy** (<5% error margin)
- ✅ **Thread safety** (concurrent access)

**Key Test Scenarios:**
- Error/success ratio tracking
- Sampling correction calculation
- SLO accuracy verification

---

## 🎯 3. Integration Test Requirements

### 3.1. Test Infrastructure

**Pattern:** Follow `spec/integration/slo_tracking_integration_spec.rb` structure

**Key Components:**
- Rails dummy app (`spec/dummy`)
- Memory adapter for event capture
- Sampling middleware configured with adaptive strategies
- Event classes with value-based sampling DSL
- Simulated conditions (error spikes, high load, normal load)

**Test Structure:**
```ruby
RSpec.describe "Adaptive Sampling Integration", :integration do
  let(:memory_adapter) { E11y.config.adapters[:memory] }
  
  before do
    memory_adapter.clear!
    
    # Configure sampling middleware with adaptive strategies
    E11y.config.pipeline.use E11y::Middleware::Sampling,
      default_sample_rate: 0.1,
      error_based_adaptive: true,
      load_based_adaptive: true,
      error_spike_config: { ... },
      load_monitor_config: { ... }
    
    E11y.config.fallback_adapters = [:memory]
  end
  
  after do
    memory_adapter.clear!
  end
  
  describe "Scenario 1: Dynamic rate adjustment" do
    # Test implementation
  end
  
  # ... other scenarios
end
```

### 3.2. Assertion Strategy

**Sampling Rate Assertions:**
- ✅ Expected rate: `expect(sampled_count / total_count).to be_within(0.05).of(expected_rate)` (±5% tolerance)
- ✅ Rate changes: Sampling rate changes based on conditions
- ✅ Rate consistency: Same conditions produce same sampling rate

**Event Drop Assertions:**
- ✅ Sampled events: Events with `sampled: true` passed to adapters
- ✅ Dropped events: Events with `sampled: false` return nil (not passed to adapters)
- ✅ Event count: Sampled event count matches expected rate

**Adaptive Behavior Assertions:**
- ✅ Error spike: 100% sampling during error spikes
- ✅ Load tiers: Sampling rate matches load tier (100%/50%/10%/1%)
- ✅ Value-based: High-value events always sampled (100%)
- ✅ Stratified: Error/success ratio preserved

---

## 📋 4. Integration Test Scenarios

### Scenario 1: Dynamic Rate Adjustment

**Objective:** Verify sampling rate changes dynamically based on conditions.

**Setup:**
- Sampling middleware with error-based and load-based adaptive enabled
- Normal conditions → Error spike → High load → Normal conditions

**Test Steps:**
1. Normal conditions: Track 1000 events, verify 10% sampling (100 events sampled)
2. Trigger error spike: Track 100 errors, verify 100% sampling (all events sampled)
3. High load: Track 15000 events/sec, verify 10% sampling (very high load tier)
4. Return to normal: Track 500 events/sec, verify 100% sampling (normal load tier)

**Assertions:**
- Rate changes: Sampling rate changes based on conditions
- Rate accuracy: Sampled event count matches expected rate (±5% tolerance)

---

### Scenario 2: Error Spike Sampling

**Objective:** Verify 100% sampling during error spikes.

**Setup:**
- ErrorSpikeDetector configured (absolute_threshold: 100, relative_threshold: 3.0)
- Normal baseline: 10 errors/min

**Test Steps:**
1. Normal conditions: Track 100 events (10 errors), verify 10% sampling
2. Trigger error spike: Track 150 errors/min (exceeds absolute threshold)
3. Verify: All events sampled (100% sampling)
4. Wait for spike duration: Verify 100% sampling maintained for 5 minutes
5. After spike: Verify return to 10% sampling

**Assertions:**
- Error spike detection: `expect(detector.error_spike?).to be(true)`
- 100% sampling: All events sampled during spike
- Spike duration: 100% sampling maintained for configured duration

---

### Scenario 3: Traffic Patterns (Load-Based Tiered Sampling)

**Objective:** Verify tiered sampling based on event volume.

**Setup:**
- LoadMonitor configured (normal: 1k, high: 10k, very_high: 50k, overload: 100k)
- Simulate different load levels

**Test Steps:**
1. Normal load (<1k events/sec): Track 500 events/sec, verify 100% sampling
2. High load (1k-10k events/sec): Track 5000 events/sec, verify 50% sampling
3. Very high load (10k-50k events/sec): Track 15000 events/sec, verify 10% sampling
4. Overload (>100k events/sec): Track 120000 events/sec, verify 1% sampling

**Assertions:**
- Load tier detection: `expect(monitor.load_level).to eq(:overload)`
- Sampling rate: Sampled event count matches expected rate for each tier
- Dynamic adjustment: Sampling rate changes as load changes

---

### Scenario 4: Budget Exhaustion

**Objective:** Verify sampling reduces when budget exceeded (if implemented).

**Setup:**
- Budget tracking configured (if implemented)
- Simulate budget exhaustion

**Test Steps:**
1. Normal conditions: Track events, verify normal sampling rate
2. Exceed budget: Simulate budget exhaustion
3. Verify: Sampling rate reduces to conserve budget

**Assertions:**
- Budget tracking: Budget tracked correctly (if implemented)
- Rate reduction: Sampling rate reduces when budget exceeded
- Budget recovery: Sampling rate returns to normal when budget available

**Note:** Budget exhaustion may not be implemented. Tests should verify current state or note limitation.

---

### Scenario 5: Priority Sampling

**Objective:** Verify high-value events always sampled.

**Setup:**
- Value-based sampling configured (amount > 1000 → 100% sampling)
- Mix of high-value and low-value events

**Test Steps:**
1. Track high-value events: Track 10 events with amount > 1000
2. Track low-value events: Track 100 events with amount < 1000
3. Verify: All high-value events sampled (100%)
4. Verify: Low-value events sampled at default rate (10%)

**Assertions:**
- High-value sampling: `expect(high_value_sampled_count).to eq(10)`
- Low-value sampling: `expect(low_value_sampled_count).to be_within(5).of(10)` (±5% tolerance)
- Priority preserved: High-value events always sampled regardless of load

---

### Scenario 6: Value-Based Sampling

**Objective:** Verify value-based sampling works correctly.

**Setup:**
- Event class with `sample_by_value` DSL
- Different payload values

**Test Steps:**
1. Track events with high values: Track events with amount > 1000
2. Track events with low values: Track events with amount < 1000
3. Verify: High-value events always sampled (100%)
4. Verify: Low-value events sampled at default rate

**Assertions:**
- Value extraction: Values extracted correctly from payload
- Operator evaluation: Operators (>, <, ==, in_range) work correctly
- Sampling decision: High-value events always sampled

---

### Scenario 7: Stratified Sampling

**Objective:** Verify error/success ratio preserved for SLO accuracy.

**Setup:**
- StratifiedTracker configured
- Mix of error and success events

**Test Steps:**
1. Track events: Track 1000 events (900 success, 100 errors)
2. Apply stratified sampling: Errors 100%, success 10%
3. Verify: All errors sampled (100 errors)
4. Verify: Success sampled at 10% (~90 events)
5. Verify: Error/success ratio preserved (100/900 ≈ 11.1%)

**Assertions:**
- Error sampling: `expect(error_sampled_count).to eq(100)`
- Success sampling: `expect(success_sampled_count).to be_within(5).of(90)` (±5% tolerance)
- Ratio preservation: Error/success ratio matches expected ratio

---

### Scenario 8: Trace-Aware Sampling

**Objective:** Verify same trace_id gets same sampling decision.

**Setup:**
- Trace-aware sampling enabled
- Multiple events with same trace_id

**Test Steps:**
1. Track first event: Track Events::OrderCreated (trace_id: "abc-123")
2. Determine sampling: Event sampled or dropped
3. Track second event: Track Events::PaymentProcessed (trace_id: "abc-123")
4. Verify: Second event gets same sampling decision as first event

**Assertions:**
- Same decision: `expect(event1[:sampled]).to eq(event2[:sampled])`
- Trace consistency: All events in same trace have same sampling decision
- Trace cache: Sampling decision cached per trace_id

---

## 🔗 5. Dependencies & Integration Points

### 5.1. Sampling Middleware Integration

**Integration Point:** `E11y::Middleware::Sampling`

**Flow:**
1. Event tracked → `Event.track(...)`
2. Sampling middleware → Determines if event should be sampled
3. Event dropped if not sampled (returns nil)
4. Event passed to adapters if sampled

**Test Requirements:**
- Sampling middleware configured in pipeline
- Adaptive strategies enabled (error-based, load-based)
- Events tracked through pipeline
- Sampled events stored in adapters

### 5.2. ErrorSpikeDetector Integration

**Integration Point:** `E11y::Sampling::ErrorSpikeDetector`

**Flow:**
1. Event tracked → Sampling middleware records error events
2. ErrorSpikeDetector → Detects error spikes
3. Sampling middleware → Uses `error_spike?` to determine sampling rate

**Test Requirements:**
- ErrorSpikeDetector configured
- Error events tracked correctly
- Spike detection works correctly
- 100% sampling during spikes

### 5.3. LoadMonitor Integration

**Integration Point:** `E11y::Sampling::LoadMonitor`

**Flow:**
1. Event tracked → Sampling middleware records events
2. LoadMonitor → Calculates event rate
3. Sampling middleware → Uses `load_level` to determine sampling rate

**Test Requirements:**
- LoadMonitor configured
- Event rate calculated correctly
- Load tiers detected correctly
- Sampling rate matches load tier

---

## ⚠️ 6. Known Limitations & Gaps

### 6.1. Budget Exhaustion

**Status:** ⚠️ **PARTIAL** (may not be fully implemented)

**Gap:** Budget tracking and exhaustion handling may not be implemented.

**Impact:** Integration tests should verify current state or note limitation.

### 6.2. Priority Sampling

**Status:** ⚠️ **PARTIAL** (value-based exists but priority may not be explicit)

**Gap:** Priority sampling may not be explicitly implemented as a separate strategy.

**Impact:** Integration tests should verify value-based sampling works correctly.

### 6.3. ML-Based Sampling

**Status:** ❌ **NOT IMPLEMENTED**

**Gap:** ML-based sampling strategy not implemented.

**Impact:** Integration tests should note limitation.

---

## 📝 7. Test Data Requirements

### 7.1. Event Classes

**Required Event Classes:**
- `Events::OrderPaid` - Value-based sampling (amount > 1000)
- `Events::PaymentFailed` - Error events (for error spike detection)
- `Events::OrderCreated` - Normal events (for load-based sampling)

**Location:** `spec/dummy/app/events/events/`

### 7.2. Test Conditions

**Required Conditions:**
- Normal load: 500 events/sec
- High load: 5000 events/sec
- Very high load: 15000 events/sec
- Overload: 120000 events/sec
- Error spike: 150 errors/min

### 7.3. Test Payloads

**Required Payloads:**
- High-value: `{ amount: 5000, order_id: "123" }`
- Low-value: `{ amount: 50, order_id: "456" }`
- Error events: `{ error: "Payment failed", order_id: "789" }`

---

## ✅ 8. Definition of Done

**Integration tests are complete when:**
1. ✅ All 8 scenarios implemented and passing
2. ✅ Dynamic rate adjustment tested (sampling rate changes based on conditions)
3. ✅ Error spike sampling tested (100% sampling during spikes)
4. ✅ Traffic patterns tested (load-based tiered sampling)
5. ✅ Budget exhaustion tested (if implemented, or current state verified)
6. ✅ Priority sampling tested (high-value events always sampled)
7. ✅ Value-based sampling tested (events with high values always sampled)
8. ✅ Stratified sampling tested (error/success ratio preserved)
9. ✅ Trace-aware sampling tested (same trace_id = same sampling decision)
10. ✅ All tests pass in CI

---

## 📚 9. References

- **UC-014:** `docs/use_cases/UC-014-adaptive-sampling.md`
- **ADR-009:** `docs/ADR-009-cost-optimization.md` (Section 3: Adaptive Sampling)
- **ErrorSpikeDetector:** `lib/e11y/sampling/error_spike_detector.rb`
- **LoadMonitor:** `lib/e11y/sampling/load_monitor.rb`
- **ValueExtractor:** `lib/e11y/sampling/value_extractor.rb`
- **StratifiedTracker:** `lib/e11y/sampling/stratified_tracker.rb`
- **Sampling Middleware:** `lib/e11y/middleware/sampling.rb`

---

**Analysis Complete:** 2026-01-26  
**Next Step:** UC-014 Phase 2: Planning Complete

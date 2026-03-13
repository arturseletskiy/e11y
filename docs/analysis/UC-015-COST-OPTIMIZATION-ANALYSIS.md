# UC-015 Cost Optimization: Integration Test Analysis

**Task:** FEAT-5415 - UC-015 Phase 1: Analysis Complete  
**Date:** 2026-01-26  
**Status:** Analysis Complete

---

## 📋 Executive Summary

**Current State:**
- ✅ **Implemented:** Adaptive Sampling (Error-Based, Load-Based, Value-Based, Stratified) - Reduces event volume
- ✅ **Implemented:** Retention-Based Routing (UC-019) - Routes events to appropriate storage tiers
- ⚠️ **PARTIAL:** Cost Tracking - May not be fully implemented (cost calculation, adapter pricing)
- ⚠️ **PARTIAL:** Budget Enforcement - May not be fully implemented (budget limits, cutoff behavior)
- ⚠️ **PARTIAL:** Cost Alerts - May not be fully implemented (alerts when budget exceeded)
- ❌ **NOT Implemented:** Compression - Per ADR-009, compression not started
- ❌ **NOT Implemented:** Payload Minimization - May not be fully implemented
- ❌ **NOT Implemented:** Tiered Storage - Replaced by Retention-Based Routing (UC-019)

**Unit Test Coverage:** Good (comprehensive tests for sampling strategies, routing)

**Integration Test Coverage:** ❌ **NONE** - No integration tests exist for cost optimization

**Gap Analysis:** Integration tests needed for:
1. Volume tracking (event volume tracked per adapter)
2. Budget enforcement (sampling reduces when budget exceeded)
3. Cost alerts (alerts when budget threshold reached)
4. Adapter pricing (cost calculation per adapter)
5. Cutoff behavior (events dropped when budget exceeded)
6. Cost calculation (total cost across adapters)
7. Multi-strategy integration (sampling + routing + cost tracking)

---

## 🔍 1. Current Implementation Analysis

### 1.1. Code Structure

**Location:** `lib/e11y/middleware/sampling.rb`, `lib/e11y/middleware/routing.rb`, `lib/e11y/sampling/error_spike_detector.rb`, `lib/e11y/sampling/load_monitor.rb`

**Key Components:**
- `E11y::Middleware::Sampling` - Reduces event volume via adaptive sampling
- `E11y::Middleware::Routing` - Routes events to appropriate adapters based on retention
- `E11y::Sampling::ErrorSpikeDetector` - Error-based adaptive sampling
- `E11y::Sampling::LoadMonitor` - Load-based adaptive sampling
- Cost tracking (if implemented) - Tracks event volume and costs per adapter

**Cost Optimization Flow:**
1. Event tracked → `Event.track(...)`
2. Sampling middleware → Reduces event volume (adaptive sampling)
3. Routing middleware → Routes events to appropriate adapters (retention-based)
4. Cost tracking (if implemented) → Tracks volume and costs per adapter
5. Budget enforcement (if implemented) → Reduces sampling when budget exceeded

**Gap:** Cost tracking and budget enforcement may not be fully implemented.

### 1.2. Current Features

| Feature | Status | Implementation |
|---------|--------|----------------|
| Adaptive Sampling | ✅ Implemented | Error-Based, Load-Based, Value-Based, Stratified |
| Retention-Based Routing | ✅ Implemented | Routes events to adapters based on retention_period |
| Cost Tracking | ⚠️ PARTIAL | May not be fully implemented |
| Budget Enforcement | ⚠️ PARTIAL | May not be fully implemented |
| Cost Alerts | ⚠️ PARTIAL | May not be fully implemented |
| Adapter Pricing | ⚠️ PARTIAL | May not be fully implemented |
| Cutoff Behavior | ⚠️ PARTIAL | May not be fully implemented |
| Compression | ❌ NOT Implemented | Per ADR-009, compression not started |
| Payload Minimization | ❌ NOT Implemented | May not be fully implemented |

### 1.3. Configuration

**Current API:**
```ruby
# Adaptive Sampling (reduces volume)
E11y.configure do |config|
  config.pipeline.use E11y::Middleware::Sampling,
    default_sample_rate: 0.1,
    error_based_adaptive: true,
    load_based_adaptive: true
end

# Retention-Based Routing (routes to appropriate adapters)
E11y.configure do |config|
  config.routing_rules = [
    ->(event) {
      days = (Time.parse(event[:retention_until]) - Time.now) / 86400
      days > 90 ? :archive : :loki
    }
  ]
end

# Cost Tracking (if implemented)
E11y.configure do |config|
  config.cost_optimization do
    cost_tracking do
      enabled true
      adapter_costs do
        loki 0.50
        sentry 10.00
        archive 0.02
      end
    end
  end
end
```

---

## 📊 2. Unit Test Coverage Analysis

### 2.1. Test File: `spec/e11y/middleware/sampling_spec.rb`

**Coverage Summary:**
- ✅ **Sampling decisions** (sample_rate calculation)
- ✅ **Adaptive sampling** (error-based, load-based)
- ✅ **Event dropping** (unsampled events return nil)

**Key Test Scenarios:**
- Sampling rate calculation
- Adaptive sampling behavior
- Event dropping

### 2.2. Test File: `spec/e11y/middleware/routing_spec.rb`

**Coverage Summary:**
- ✅ **Routing decisions** (adapter selection)
- ✅ **Retention-based routing** (routes based on retention_period)
- ✅ **Multiple adapters** (routes to multiple adapters)

**Key Test Scenarios:**
- Retention-based routing
- Multiple adapter routing
- Routing rules evaluation

---

## 🎯 3. Integration Test Requirements

### 3.1. Test Infrastructure

**Pattern:** Follow `spec/integration/slo_tracking_integration_spec.rb` structure

**Key Components:**
- Rails dummy app (`spec/dummy`)
- Memory adapter for event capture
- Multiple adapters (simulated) for cost tracking
- Cost tracking configuration (if implemented)
- Budget configuration (if implemented)

**Test Structure:**
```ruby
RSpec.describe "Cost Optimization Integration", :integration do
  let(:memory_adapter) { E11y.config.adapters[:memory] }
  
  before do
    memory_adapter.clear!
    
    # Configure cost tracking (if implemented)
    E11y.configure do |config|
      config.cost_optimization do
        cost_tracking do
          enabled true
          adapter_costs do
            memory 0.01
            loki 0.50
          end
        end
      end
    end
    
    E11y.config.fallback_adapters = [:memory]
  end
  
  after do
    memory_adapter.clear!
  end
  
  describe "Scenario 1: Volume tracking" do
    # Test implementation
  end
  
  # ... other scenarios
end
```

### 3.2. Assertion Strategy

**Volume Tracking Assertions:**
- ✅ Event count: `expect(adapter_volume[:memory]).to eq(100)`
- ✅ Volume per adapter: Volume tracked correctly per adapter
- ✅ Total volume: Total volume calculated correctly

**Budget Enforcement Assertions:**
- ✅ Budget limit: Budget enforced correctly
- ✅ Sampling reduction: Sampling rate reduces when budget exceeded
- ✅ Cutoff behavior: Events dropped when budget exceeded

**Cost Calculation Assertions:**
- ✅ Adapter costs: Cost calculated correctly per adapter
- ✅ Total cost: Total cost calculated correctly
- ✅ Cost accuracy: Cost matches expected values

---

## 📋 4. Integration Test Scenarios

### Scenario 1: Volume Tracking

**Objective:** Verify event volume tracked per adapter.

**Setup:**
- Multiple adapters configured (memory, loki)
- Cost tracking enabled

**Test Steps:**
1. Track events: Track 100 events routed to memory adapter
2. Track events: Track 50 events routed to loki adapter
3. Verify: Volume tracked correctly per adapter

**Assertions:**
- Memory volume: `expect(volume[:memory]).to eq(100)`
- Loki volume: `expect(volume[:loki]).to eq(50)`
- Total volume: `expect(total_volume).to eq(150)`

---

### Scenario 2: Budget Enforcement

**Objective:** Verify sampling reduces when budget exceeded.

**Setup:**
- Budget configured (e.g., 1000 events/month)
- Cost tracking enabled

**Test Steps:**
1. Normal conditions: Track events, verify normal sampling rate
2. Exceed budget: Track events until budget exceeded
3. Verify: Sampling rate reduces when budget exceeded

**Assertions:**
- Budget tracking: Budget tracked correctly
- Rate reduction: Sampling rate reduces when budget exceeded
- Cutoff behavior: Events dropped when budget exceeded

**Note:** Budget enforcement may not be implemented. Tests should verify current state or note limitation.

---

### Scenario 3: Cost Alerts

**Objective:** Verify alerts triggered when budget threshold reached.

**Setup:**
- Budget configured (e.g., 1000 events/month)
- Alert threshold configured (e.g., 80% of budget)

**Test Steps:**
1. Track events: Track events until 80% of budget consumed
2. Verify: Alert triggered at threshold
3. Continue tracking: Track events until 100% of budget consumed
4. Verify: Additional alerts triggered

**Assertions:**
- Alert threshold: Alert triggered at configured threshold
- Alert content: Alert contains budget information
- Multiple alerts: Multiple alerts triggered as budget consumed

**Note:** Cost alerts may not be implemented. Tests should verify current state or note limitation.

---

### Scenario 4: Adapter Pricing

**Objective:** Verify cost calculation per adapter.

**Setup:**
- Multiple adapters configured with pricing (memory: $0.01, loki: $0.50)
- Cost tracking enabled

**Test Steps:**
1. Track events: Track 100 events routed to memory adapter
2. Track events: Track 50 events routed to loki adapter
3. Verify: Cost calculated correctly per adapter

**Assertions:**
- Memory cost: `expect(cost[:memory]).to eq(100 * 0.01)` (1.0)
- Loki cost: `expect(cost[:loki]).to eq(50 * 0.50)` (25.0)
- Total cost: `expect(total_cost).to eq(26.0)`

**Note:** Adapter pricing may not be implemented. Tests should verify current state or note limitation.

---

### Scenario 5: Cutoff Behavior

**Objective:** Verify events dropped when budget exceeded.

**Setup:**
- Budget configured (e.g., 1000 events/month)
- Budget enforcement enabled

**Test Steps:**
1. Normal conditions: Track events, verify events stored
2. Exceed budget: Track events until budget exceeded
3. Verify: Events dropped when budget exceeded

**Assertions:**
- Event dropping: Events dropped when budget exceeded
- Drop rate: Drop rate matches expected value
- Critical events: Critical events (errors) still tracked even when budget exceeded

**Note:** Cutoff behavior may not be implemented. Tests should verify current state or note limitation.

---

### Scenario 6: Cost Calculation

**Objective:** Verify total cost calculated correctly across adapters.

**Setup:**
- Multiple adapters configured with pricing
- Cost tracking enabled

**Test Steps:**
1. Track events: Track events routed to multiple adapters
2. Verify: Cost calculated correctly per adapter
3. Verify: Total cost calculated correctly

**Assertions:**
- Per-adapter cost: Cost calculated correctly per adapter
- Total cost: Total cost = sum of adapter costs
- Cost accuracy: Cost matches expected values

---

### Scenario 7: Multi-Strategy Integration

**Objective:** Verify sampling + routing + cost tracking work together.

**Setup:**
- Adaptive sampling enabled
- Retention-based routing enabled
- Cost tracking enabled

**Test Steps:**
1. Track events: Track events with adaptive sampling
2. Verify: Events sampled correctly
3. Verify: Events routed correctly based on retention
4. Verify: Volume and cost tracked correctly

**Assertions:**
- Sampling works: Events sampled correctly
- Routing works: Events routed correctly
- Cost tracking works: Volume and cost tracked correctly
- Integration: All strategies work together without conflicts

---

## 🔗 5. Dependencies & Integration Points

### 5.1. Sampling Middleware Integration

**Integration Point:** `E11y::Middleware::Sampling`

**Flow:**
1. Event tracked → Sampling middleware reduces volume
2. Reduced volume → Lower cost per adapter

**Test Requirements:**
- Sampling middleware configured
- Adaptive sampling enabled
- Volume reduction verified

### 5.2. Routing Middleware Integration

**Integration Point:** `E11y::Middleware::Routing`

**Flow:**
1. Event tracked → Routing middleware routes to adapters
2. Adapter selection → Cost calculated per adapter

**Test Requirements:**
- Routing middleware configured
- Retention-based routing enabled
- Adapter selection verified

### 5.3. Cost Tracking Integration

**Integration Point:** Cost Tracking (if implemented)

**Flow:**
1. Event routed → Cost tracking records volume per adapter
2. Cost calculation → Cost calculated based on adapter pricing
3. Budget enforcement → Sampling reduces when budget exceeded

**Test Requirements:**
- Cost tracking configured
- Adapter pricing configured
- Budget limits configured
- Cost calculation verified

**Gap:** Cost tracking may not be fully implemented. Tests should verify current state or note limitation.

---

## ⚠️ 6. Known Limitations & Gaps

### 6.1. Cost Tracking

**Status:** ⚠️ **PARTIAL** (may not be fully implemented)

**Gap:** Cost tracking and calculation may not be fully implemented.

**Impact:** Integration tests should verify current state (volume tracking, if implemented) or note limitation.

### 6.2. Budget Enforcement

**Status:** ⚠️ **PARTIAL** (may not be fully implemented)

**Gap:** Budget enforcement and cutoff behavior may not be fully implemented.

**Impact:** Integration tests should verify current state or note limitation.

### 6.3. Cost Alerts

**Status:** ⚠️ **PARTIAL** (may not be fully implemented)

**Gap:** Cost alerts may not be fully implemented.

**Impact:** Integration tests should verify current state or note limitation.

### 6.4. Compression

**Status:** ❌ **NOT IMPLEMENTED** (per ADR-009)

**Gap:** Compression not started.

**Impact:** Integration tests should note limitation.

### 6.5. Payload Minimization

**Status:** ❌ **NOT IMPLEMENTED**

**Gap:** Payload minimization may not be fully implemented.

**Impact:** Integration tests should note limitation.

---

## 📝 7. Test Data Requirements

### 7.1. Event Classes

**Required Event Classes:**
- `Events::OrderCreated` - Normal events
- `Events::PaymentFailed` - Error events (for budget enforcement)

**Location:** `spec/dummy/app/events/events/`

### 7.2. Test Budgets

**Required Budgets:**
- Daily budget: 10000 events/day
- Monthly budget: 300000 events/month
- Alert threshold: 80% of budget

### 7.3. Test Adapter Pricing

**Required Pricing:**
- Memory adapter: $0.01 per event
- Loki adapter: $0.50 per event
- Archive adapter: $0.02 per event

---

## ✅ 8. Definition of Done

**Integration tests are complete when:**
1. ✅ All 7 scenarios implemented and passing
2. ✅ Volume tracking tested (event volume tracked per adapter)
3. ✅ Budget enforcement tested (if implemented, or current state verified)
4. ✅ Cost alerts tested (if implemented, or current state verified)
5. ✅ Adapter pricing tested (if implemented, or current state verified)
6. ✅ Cutoff behavior tested (if implemented, or current state verified)
7. ✅ Cost calculation tested (total cost across adapters)
8. ✅ Multi-strategy integration tested (sampling + routing + cost tracking)
9. ✅ All tests pass in CI

---

## 📚 9. References

- **UC-015:** `docs/use_cases/UC-015-cost-optimization.md`
- **ADR-009:** `docs/ADR-009-cost-optimization.md`
- **UC-014:** `docs/use_cases/UC-014-adaptive-sampling.md` (Adaptive Sampling)
- **UC-019:** `docs/use_cases/UC-019-retention-based-routing.md` (Retention-Based Routing)
- **Sampling Middleware:** `lib/e11y/middleware/sampling.rb`
- **Routing Middleware:** `lib/e11y/middleware/routing.rb`

---

**Analysis Complete:** 2026-01-26
**Next Step:** UC-015 Phase 2: Planning Complete

---

## 🔍 Production Readiness Audit — 2026-03-10

**Audit Date:** 2026-03-10
**Status:** ❌ NOT PRODUCTION-READY — Cost Tracking перенесён в v1.1

### Решение о версионировании

**UC-015 полностью переносится в v1.1.** Причина: основная ценность — снижение затрат через Adaptive Sampling (UC-014) — уже реализована и даёт 90% volume reduction. Явный Cost Tracking (измерение, бюджеты, алерты) не является блокером для v1.0.

### v1.1 Backlog Items для UC-015

Когда UC-015 будет реализован в v1.1:

1. **Cost Tracking Middleware** (`E11y::Middleware::CostTracking`):
   - Volume tracking per adapter (events_count, bytes_per_adapter)
   - Cost calculation (configurable pricing per adapter)
   - Budget comparison logic

2. **Budget Enforcement:**
   - `config.cost_tracking.budget = { loki: 100.0, elasticsearch: 50.0 }` ($/month)
   - Dynamic sampling rate reduction when budget exceeded
   - Cutoff behavior for non-critical events

3. **Cost Alerts:**
   - `config.cost_tracking.alert_threshold = 0.8` (80% of budget)
   - Integration with E11y self-monitoring events

4. **Integration Tests для v1.1:**
   - Volume tracking per adapter
   - Budget enforcement (sampling adjusts when budget exceeded)
   - Cost alerts trigger at threshold
   - Cutoff behavior verified

### Текущее состояние (v1.0)

UC-015 в части снижения затрат через sampling — **работает через UC-014** (Adaptive Sampling):
- ✅ Error-spike sampling — до 90% volume reduction
- ✅ Load-based tiered sampling
- ✅ Trace-aware caching
- ✅ Stratified sampling (SLO-accurate)
- Нет visibility в реальные затраты — по дизайну для v1.0

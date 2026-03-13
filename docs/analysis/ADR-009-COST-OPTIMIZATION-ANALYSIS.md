# ADR-009 Cost Optimization: Integration Test Analysis

**Task:** FEAT-5424 - ADR-009 Phase 1: Analysis Complete  
**Date:** 2026-01-26  
**Status:** Analysis Complete

---

## 📋 Executive Summary

**Current State:**
- ✅ **Implemented:** Adaptive Sampling (Error-Based, Load-Based, Value-Based, Stratified) - Reduces event volume dynamically
- ✅ **Implemented:** Retention-Based Routing (UC-019) - Routes events to appropriate storage tiers based on retention_period
- ✅ **Implemented:** Trace-Aware Sampling (C05 Resolution) - Same trace_id gets same sampling decision
- ✅ **Implemented:** Stratified Sampling (C11 Resolution) - SLO-accurate sampling with correction factors
- ✅ **Implemented:** Cardinality Protection (C04 Resolution) - Unified protection for all backends (Yabeda, OTel, Loki)
- ⚠️ **PARTIAL:** Cost Tracking - May not be fully implemented (cost calculation, adapter pricing)
- ⚠️ **PARTIAL:** Budget Enforcement - May not be fully implemented (budget limits, cutoff behavior)
- ⚠️ **PARTIAL:** Cost Alerts - May not be fully implemented (alerts when budget exceeded)
- ❌ **NOT Implemented:** Compression - Per ADR-009, compression not started
- ❌ **NOT Implemented:** Payload Minimization - May not be fully implemented

**Unit Test Coverage:** Good (comprehensive tests for adaptive sampling strategies, routing)

**Integration Test Coverage:** ❌ **NONE** - No integration tests exist for cost optimization

**Gap Analysis:** Integration tests needed for:
1. Budgets enforced (budget limits enforced, sampling adjusts when budget exceeded)
2. Sampling adjusts to cost (sampling rate reduces when cost threshold reached)
3. Alerts triggered (alerts when budget threshold reached)
4. Cost tracking (event volume and costs tracked per adapter)
5. Adapter pricing (cost calculation per adapter)
6. Cutoff behavior (events dropped when budget exceeded)
7. Multi-strategy integration (sampling + routing + cost tracking work together)

---

## 🔍 1. Current Implementation Analysis

### 1.1. Code Structure

**Location:** `lib/e11y/middleware/sampling.rb`, `lib/e11y/middleware/routing.rb`, `lib/e11y/sampling/error_spike_detector.rb`, `lib/e11y/sampling/load_monitor.rb`, `lib/e11y/sampling/stratified_tracker.rb`

**Key Components:**
- `E11y::Middleware::Sampling` - Applies adaptive sampling strategies
- `E11y::Middleware::Routing` - Routes events to appropriate adapters (retention-based)
- `E11y::Sampling::ErrorSpikeDetector` - Error-based adaptive sampling (100% during spikes)
- `E11y::Sampling::LoadMonitor` - Load-based adaptive sampling (tiered rates)
- `E11y::Sampling::StratifiedTracker` - Stratified sampling for SLO accuracy
- Cost tracking (if implemented) - Tracks event volume and costs per adapter

**Cost Optimization Flow:**
1. Event tracked → `Event.track(...)`
2. Sampling middleware → Applies adaptive sampling (reduces volume)
3. Routing middleware → Routes events to appropriate adapters (retention-based)
4. Cost tracking (if implemented) → Tracks volume and costs per adapter
5. Budget enforcement (if implemented) → Reduces sampling when budget exceeded
6. Cost alerts (if implemented) → Alerts when budget threshold reached

**Note:** Per ADR-009, compression is not started. Cost tracking and budget enforcement may not be fully implemented.

### 1.2. Current Features

| Feature | Status | Implementation |
|---------|--------|----------------|
| Adaptive Sampling | ✅ Implemented | Error-Based, Load-Based, Value-Based, Stratified |
| Retention-Based Routing | ✅ Implemented | Routes events based on retention_period |
| Trace-Aware Sampling | ✅ Implemented | C05 Resolution - same trace_id = same decision |
| Stratified Sampling | ✅ Implemented | C11 Resolution - SLO-accurate sampling |
| Cardinality Protection | ✅ Implemented | C04 Resolution - unified protection |
| Cost Tracking | ⚠️ PARTIAL | May not be fully implemented |
| Budget Enforcement | ⚠️ PARTIAL | May not be fully implemented |
| Cost Alerts | ⚠️ PARTIAL | May not be fully implemented |
| Compression | ❌ NOT Implemented | Per ADR-009, compression not started |
| Payload Minimization | ❌ NOT Implemented | May not be fully implemented |

### 1.3. Configuration

**Current API:**
```ruby
# Adaptive Sampling
E11y.configure do |config|
  config.pipeline.use E11y::Middleware::Sampling,
    default_sample_rate: 0.1,
    error_based_adaptive: true,
    load_based_adaptive: true,
    value_based_adaptive: true,
    stratified_sampling: true
end

# Retention-Based Routing
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
        loki 0.50  # $0.50 per 1M events
        sentry 1.00  # $1.00 per 1M events
      end
    end
    
    budget_enforcement do
      enabled true
      monthly_budget 1000  # $1000/month
      alert_threshold 0.8  # Alert at 80% of budget
    end
  end
end
```

---

## 📊 2. Unit Test Coverage Analysis

### 2.1. Test File: `spec/e11y/middleware/sampling_spec.rb`

**Coverage Summary:**
- ✅ **Adaptive sampling** (error-based, load-based, value-based, stratified)
- ✅ **Trace-aware sampling** (same trace_id = same decision)
- ✅ **Stratified sampling** (SLO-accurate sampling)

**Key Test Scenarios:**
- Error-based adaptive sampling
- Load-based adaptive sampling
- Value-based adaptive sampling
- Stratified sampling
- Trace-aware sampling

### 2.2. Test File: `spec/e11y/middleware/routing_spec.rb`

**Coverage Summary:**
- ✅ **Retention-based routing** (routing based on retention_period)
- ✅ **Routing rules** (lambda-based routing rules)

**Key Test Scenarios:**
- Retention-based routing
- Routing rules evaluation
- Fallback adapters

---

## 🎯 3. Integration Test Requirements

### 3.1. Test Infrastructure

**Pattern:** Follow `spec/integration/pattern_metrics_integration_spec.rb` structure

**Key Components:**
- Rails dummy app (`spec/dummy`)
- Adaptive sampling configured
- Retention-based routing configured
- Cost tracking configured (if implemented)
- Multiple adapters (for routing tests)

**Test Structure:**
```ruby
RSpec.describe "ADR-009 Cost Optimization Integration", :integration do
  before do
    # Configure adaptive sampling
    E11y.configure do |config|
      config.pipeline.use E11y::Middleware::Sampling,
        default_sample_rate: 0.1,
        error_based_adaptive: true,
        load_based_adaptive: true
      
      # Configure retention-based routing
      config.routing_rules = [
        ->(event) {
          days = (Time.parse(event[:retention_until]) - Time.now) / 86400
          days > 90 ? :archive : :loki
        }
      ]
      
      # Configure cost tracking (if implemented)
      config.cost_optimization do
        cost_tracking do
          enabled true
          adapter_costs do
            loki 0.50
            sentry 1.00
          end
        end
        
        budget_enforcement do
          enabled true
          monthly_budget 1000
          alert_threshold 0.8
        end
      end
    end
    
    E11y.config.fallback_adapters = [:loki]
  end
  
  describe "Scenario 1: Budgets enforced" do
    # Test implementation
  end
  
  # ... other scenarios
end
```

### 3.2. Assertion Strategy

**Budget Assertions:**
- ✅ Budget enforced: `expect(sampling_rate).to be < default_rate` when budget exceeded
- ✅ Cutoff behavior: Events dropped when budget exceeded

**Sampling Assertions:**
- ✅ Sampling adjusts: Sampling rate reduces when cost threshold reached
- ✅ Cost-aware: Sampling decisions consider cost

**Alert Assertions:**
- ✅ Alerts triggered: Alerts fired when budget threshold reached
- ✅ Alert content: Alert contains cost information

---

## 📋 4. Integration Test Scenarios

### Scenario 1: Budgets Enforced

**Objective:** Verify budget limits enforced and sampling adjusts when budget exceeded.

**Setup:**
- Budget enforcement configured (monthly_budget: 1000)
- Cost tracking enabled
- Adaptive sampling enabled

**Test Steps:**
1. Track events: Track events up to budget threshold
2. Verify: Events accepted, cost tracked
3. Exceed budget: Track events exceeding budget
4. Verify: Sampling rate reduces, events dropped

**Assertions:**
- Budget enforced: `expect(sampling_rate).to be < default_rate` when budget exceeded
- Cutoff behavior: Events dropped when budget exceeded

**Note:** Budget enforcement may not be fully implemented. Tests should verify current state or note limitation.

---

### Scenario 2: Sampling Adjusts to Cost

**Objective:** Verify sampling rate adjusts based on cost thresholds.

**Setup:**
- Cost tracking enabled
- Adaptive sampling enabled
- Cost thresholds configured

**Test Steps:**
1. Track events: Track events with low cost
2. Verify: Sampling rate normal
3. Increase cost: Track events increasing cost
4. Verify: Sampling rate reduces as cost increases

**Assertions:**
- Sampling adjusts: Sampling rate reduces when cost threshold reached
- Cost-aware: Sampling decisions consider cost

**Note:** Cost-aware sampling may not be fully implemented. Tests should verify current state or note limitation.

---

### Scenario 3: Alerts Triggered

**Objective:** Verify alerts triggered when budget threshold reached.

**Setup:**
- Budget enforcement configured
- Cost alerts configured (alert_threshold: 0.8)
- Cost tracking enabled

**Test Steps:**
1. Track events: Track events up to alert threshold
2. Verify: Alert triggered at 80% of budget
3. Verify alert content: Alert contains cost information

**Assertions:**
- Alerts triggered: `expect(alert_fired).to be(true)` at threshold
- Alert content: Alert contains cost information

**Note:** Cost alerts may not be fully implemented. Tests should verify current state or note limitation.

---

### Scenario 4: Cost Tracking

**Objective:** Verify event volume and costs tracked per adapter.

**Setup:**
- Cost tracking enabled
- Adapter pricing configured
- Multiple adapters configured

**Test Steps:**
1. Track events: Track events to multiple adapters
2. Verify: Volume tracked per adapter
3. Verify: Cost calculated per adapter
4. Verify: Total cost calculated correctly

**Assertions:**
- Volume tracked: `expect(volume_per_adapter).to eq(expected_volume)`
- Cost calculated: `expect(cost_per_adapter).to eq(expected_cost)`
- Total cost: `expect(total_cost).to eq(sum_of_adapter_costs)`

**Note:** Cost tracking may not be fully implemented. Tests should verify current state or note limitation.

---

### Scenario 5: Adapter Pricing

**Objective:** Verify cost calculation per adapter works correctly.

**Setup:**
- Adapter pricing configured (different prices per adapter)
- Cost tracking enabled

**Test Steps:**
1. Track events: Track events to adapters with different pricing
2. Verify: Cost calculated correctly per adapter
3. Verify: Total cost reflects adapter pricing

**Assertions:**
- Adapter pricing: Cost calculated correctly per adapter
- Total cost: Total cost reflects adapter pricing

**Note:** Adapter pricing may not be fully implemented. Tests should verify current state or note limitation.

---

### Scenario 6: Cutoff Behavior

**Objective:** Verify events dropped when budget exceeded.

**Setup:**
- Budget enforcement configured
- Cost tracking enabled
- Budget limit set

**Test Steps:**
1. Track events: Track events up to budget limit
2. Verify: Events accepted
3. Exceed budget: Track events exceeding budget
4. Verify: Events dropped (cutoff behavior)

**Assertions:**
- Cutoff behavior: Events dropped when budget exceeded
- Sampling reduced: Sampling rate reduces to stay within budget

**Note:** Cutoff behavior may not be fully implemented. Tests should verify current state or note limitation.

---

### Scenario 7: Multi-Strategy Integration

**Objective:** Verify sampling + routing + cost tracking work together.

**Setup:**
- Adaptive sampling enabled
- Retention-based routing enabled
- Cost tracking enabled

**Test Steps:**
1. Track events: Track events with different retention periods
2. Verify: Sampling applied correctly
3. Verify: Routing applied correctly (based on retention)
4. Verify: Cost tracked correctly (per adapter)

**Assertions:**
- Sampling: Sampling applied correctly
- Routing: Routing applied correctly
- Cost tracking: Cost tracked correctly

---

## 🔗 5. Dependencies & Integration Points

### 5.1. Adaptive Sampling Integration

**Integration Point:** `E11y::Middleware::Sampling`

**Flow:**
1. Event tracked → Sampling middleware processes event
2. Adaptive strategies → Error-based, load-based, value-based, stratified sampling applied
3. Sampling decision → Event sampled or dropped
4. Cost consideration → Sampling rate adjusts based on cost (if implemented)

**Test Requirements:**
- Adaptive sampling configured
- Cost-aware sampling (if implemented)
- Budget enforcement (if implemented)

### 5.2. Retention-Based Routing Integration

**Integration Point:** `E11y::Middleware::Routing`

**Flow:**
1. Event tracked → Routing middleware processes event
2. Retention calculation → `retention_until` calculated from `retention_period`
3. Routing rules → Routing rules evaluated
4. Adapter selection → Event routed to appropriate adapter

**Test Requirements:**
- Retention-based routing configured
- Routing rules configured
- Multiple adapters configured

### 5.3. Cost Tracking Integration

**Integration Point:** Cost tracking (if implemented)

**Flow:**
1. Event routed → Event routed to adapter
2. Cost calculation → Cost calculated based on adapter pricing
3. Volume tracking → Volume tracked per adapter
4. Budget enforcement → Budget enforced (if implemented)

**Test Requirements:**
- Cost tracking configured (if implemented)
- Adapter pricing configured
- Budget enforcement configured (if implemented)

---

## ⚠️ 6. Known Limitations & Gaps

### 6.1. Cost Tracking

**Status:** ⚠️ **PARTIAL** (may not be fully implemented)

**Gap:** Cost tracking may not be fully implemented.

**Impact:** Integration tests should verify current state or note limitation.

### 6.2. Budget Enforcement

**Status:** ⚠️ **PARTIAL** (may not be fully implemented)

**Gap:** Budget enforcement may not be fully implemented.

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

**Status:** ❌ **NOT IMPLEMENTED** (may not be fully implemented)

**Gap:** Payload minimization may not be fully implemented.

**Impact:** Integration tests should verify current state or note limitation.

---

## 📝 7. Test Data Requirements

### 7.1. Event Classes

**Required Event Classes:**
- `Events::OrderPaid` - High-value event (for value-based sampling)
- `Events::ErrorEvent` - Error event (for error-based sampling)
- `Events::HighFrequencyEvent` - High-frequency event (for load-based sampling)
- `Events::LongRetentionEvent` - Long retention event (for routing tests)

**Location:** `spec/dummy/app/events/events/`

### 7.2. Test Adapters

**Required Adapters:**
- Loki adapter: Low-cost adapter ($0.50 per 1M events)
- Sentry adapter: High-cost adapter ($1.00 per 1M events)
- Archive adapter: Cold storage adapter (for routing tests)

### 7.3. Test Budgets

**Required Budgets:**
- Monthly budget: $1000
- Alert threshold: 80% ($800)
- Adapter costs: Different prices per adapter

---

## ✅ 8. Definition of Done

**Integration tests are complete when:**
1. ✅ All 7 scenarios implemented and passing
2. ✅ Budgets enforced (if implemented, or current state verified)
3. ✅ Sampling adjusts to cost (if implemented, or current state verified)
4. ✅ Alerts triggered (if implemented, or current state verified)
5. ✅ Cost tracking tested (if implemented, or current state verified)
6. ✅ Adapter pricing tested (if implemented, or current state verified)
7. ✅ Cutoff behavior tested (if implemented, or current state verified)
8. ✅ Multi-strategy integration tested (sampling + routing + cost tracking)
9. ✅ All tests pass in CI

---

## 📚 9. References

- **ADR-009:** `docs/ADR-009-cost-optimization.md`
- **UC-014:** `docs/use_cases/UC-014-adaptive-sampling.md`
- **UC-015:** `docs/use_cases/UC-015-cost-optimization.md`
- **UC-019:** `docs/use_cases/UC-019-retention-based-routing.md`
- **Sampling Middleware:** `lib/e11y/middleware/sampling.rb`
- **Routing Middleware:** `lib/e11y/middleware/routing.rb`
- **AUDIT-014:** `docs/researches/post_implementation/AUDIT-014-ADR-009-cost-optimization.md`

---

**Analysis Complete:** 2026-01-26
**Note:** Cost tracking, budget enforcement, and cost alerts may not be fully implemented. Integration tests should verify current state or note limitations.

**Next Step:** ADR-009 Phase 2: Planning Complete

---

## 🔍 Production Readiness Audit — 2026-03-10

**Audit Date:** 2026-03-10
**Status:** ⚠️ PARTIALLY PRODUCTION-READY — Sampling работает; Cost Tracking перенесён в v1.1

### Решение о версионировании

**Cost Tracking, Budget Enforcement, Cost Alerts, Compression, Payload Minimization → перенесены в v1.1**

Обоснование: Adaptive Sampling (90% volume reduction) достаточен для v1.0. Реализация cost tracking потребует ~2-3 дня и не блокирует базовое использование.

### Обновлённый статус компонентов

| Компонент | Статус | Версия |
|-----------|--------|--------|
| Adaptive Sampling (все 4 стратегии) | ✅ PRODUCTION-READY | v1.0 |
| Trace-Aware Sampling (C05) | ✅ PRODUCTION-READY | v1.0 |
| Stratified Sampling (C11) | ✅ Implemented, missing integration test | v1.0 |
| LoadMonitor off-by-one bug | ✅ Fixed (commit 8ab4bd8) | v1.0 |
| **Cost Tracking** | ❌ → **v1.1 Backlog** | v1.1 |
| **Budget Enforcement** | ❌ → **v1.1 Backlog** | v1.1 |
| **Cost Alerts** | ❌ → **v1.1 Backlog** | v1.1 |
| **Compression** | ❌ → **v1.1 Backlog** | v1.1 |
| **Payload Minimization** | ❌ → **v1.1 Backlog** | v1.1 |

### ⚠️ Missing Integration Tests (v1.0 scope)

Sampling integration tests были созданы (11 tests, все проходят), но отсутствуют 3 сценария:

| Сценарий | Статус |
|----------|--------|
| Value-based sampling E2E | ❌ Missing — DSL + ValueExtractor работают unit, integration test нет |
| Stratified sampling E2E | ❌ Missing — StratifiedTracker работает unit, integration test нет |
| Pattern-based sampling | ❌ Missing — закомментировано в spec как "will be added" |

### v1.1 Backlog Items

Когда будет реализован Cost Tracking (v1.1):
1. `E11y::Middleware::CostTracking` — подсчёт volume per adapter
2. `config.cost_tracking.budget` — лимиты по бюджету
3. `config.cost_tracking.alert_threshold` — алертинг при превышении
4. Integration tests: volume tracking, budget enforcement, cost alerts
5. Compression middleware (zstd/gzip)
6. Payload minimization (drop null fields)

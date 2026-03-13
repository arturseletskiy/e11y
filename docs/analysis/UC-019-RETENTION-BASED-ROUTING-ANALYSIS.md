# UC-019 Retention-Based Routing: Integration Test Analysis

**Task:** FEAT-5416 - UC-019 Phase 1: Analysis Complete  
**Date:** 2026-01-26  
**Status:** Analysis Complete

---

## 📋 Executive Summary

**Current State:**
- ✅ **Implemented:** Routing Middleware (`E11y::Middleware::Routing`) - Routes events to adapters based on routing rules
- ✅ **Implemented:** Routing Rules (Lambda-based) - Configurable routing rules via `config.routing_rules`
- ✅ **Implemented:** Retention Period DSL (`retention_period`) - Event classes can declare retention period
- ✅ **Implemented:** Retention Until Calculation - `retention_until` calculated from `retention_period` at track time
- ✅ **Implemented:** Explicit Adapter Selection - Events can bypass routing rules with explicit `adapters` field
- ✅ **Implemented:** Fallback Adapters - Default adapters used when no routing rule matches
- ✅ **Implemented:** Multi-Adapter Fanout - Events can route to multiple adapters
- ❌ **NOT Implemented:** Tiered Storage Adapters (hot/warm/cold) - Per AUDIT-019, no hot/warm/cold adapters
- ❌ **NOT Implemented:** Automatic Lifecycle Transitions - No hot → warm → cold automation
- ❌ **NOT Implemented:** Retention Enforcement - No deletion after retention period

**Unit Test Coverage:** Good (comprehensive tests for Routing middleware, routing rules, fallback adapters)

**Integration Test Coverage:** ❌ **NONE** - No integration tests exist for retention-based routing

**Gap Analysis:** Integration tests needed for:
1. Hot/warm/cold routing (if tiered adapters implemented, or simulate with different adapters)
2. Age-based rules (routing based on retention_until calculation)
3. Priority routing (routing rules evaluated in order)
4. Adapter failover (fallback adapters when primary adapter fails)
5. Multi-adapter fanout (events routed to multiple adapters)
6. Explicit adapter selection (bypass routing rules)

---

## 🔍 1. Current Implementation Analysis

### 1.1. Code Structure

**Location:** `lib/e11y/middleware/routing.rb`, `lib/e11y/middleware/trace_context.rb` (retention_until calculation)

**Key Components:**
- `E11y::Middleware::Routing` - Routes events to adapters based on routing rules
- `E11y::Middleware::TraceContext` - Calculates `retention_until` from `retention_period`
- Routing rules (lambda-based) - Configurable routing logic
- Fallback adapters - Default adapters when no rule matches

**Routing Flow:**
1. Event tracked → `Event.track(...)` with `retention_period`
2. TraceContext middleware → Calculates `retention_until` from `retention_period`
3. Routing middleware → Applies routing rules to determine target adapters
4. Priority: Explicit adapters → Routing rules → Fallback adapters
5. Event written → Event written to selected adapters

**Routing Priority:**
1. **Explicit adapters** (`event_data[:adapters]`) - Highest priority, bypasses routing rules
2. **Routing rules** (`config.routing_rules`) - Lambda functions evaluated in order
3. **Fallback adapters** (`config.fallback_adapters`) - Default adapters if no rule matches

### 1.2. Current Features

| Feature | Status | Implementation |
|---------|--------|----------------|
| Routing Middleware | ✅ Implemented | Routes events to adapters based on rules |
| Routing Rules (Lambda) | ✅ Implemented | Configurable routing rules via `config.routing_rules` |
| Retention Period DSL | ✅ Implemented | Event classes can declare `retention_period` |
| Retention Until Calculation | ✅ Implemented | `retention_until` calculated from `retention_period` |
| Explicit Adapter Selection | ✅ Implemented | Events can bypass routing with explicit `adapters` |
| Fallback Adapters | ✅ Implemented | Default adapters when no rule matches |
| Multi-Adapter Fanout | ✅ Implemented | Events can route to multiple adapters |
| Tiered Storage Adapters | ❌ NOT Implemented | No hot/warm/cold adapters (Phase 5) |
| Lifecycle Transitions | ❌ NOT Implemented | No automatic hot → warm → cold transitions |
| Retention Enforcement | ❌ NOT Implemented | No deletion after retention period |

### 1.3. Configuration

**Current API:**
```ruby
# Event class with retention period
class DebugEvent < E11y::Event::Base
  retention_period 7.days  # Declare intent
end

class AuditEvent < E11y::Event::Base
  audit_event true
  retention_period 7.years  # Declare intent
end

# Routing configuration
E11y.configure do |config|
  # Routing rules (lambda-based)
  config.routing_rules = [
    # Rule 1: Audit events → encrypted storage
    ->(event) { :audit_encrypted if event[:audit_event] },
    
    # Rule 2: Long retention → cold storage (if implemented)
    ->(event) {
      return nil unless event[:retention_until]
      days = (Time.parse(event[:retention_until]) - Time.now) / 86400
      days > 90 ? :archive : :loki
    },
    
    # Rule 3: Errors → multiple adapters
    ->(event) { [:datadog, :loki] if event[:severity] == :error }
  ]
  
  # Fallback adapters
  config.fallback_adapters = [:memory]
end
```

---

## 📊 2. Unit Test Coverage Analysis

### 2.1. Test File: `spec/e11y/middleware/routing_spec.rb`

**Coverage Summary:**
- ✅ **Routing rules** (lambda evaluation)
- ✅ **Explicit adapters** (bypass routing rules)
- ✅ **Fallback adapters** (default when no rule matches)
- ✅ **Multi-adapter fanout** (route to multiple adapters)
- ✅ **Error handling** (routing failures don't break pipeline)

**Key Test Scenarios:**
- Routing rule evaluation
- Explicit adapter selection
- Fallback adapter selection
- Multi-adapter routing
- Error handling

---

## 🎯 3. Integration Test Requirements

### 3.1. Test Infrastructure

**Pattern:** Follow `spec/integration/audit_trail_integration_spec.rb` structure

**Key Components:**
- Rails dummy app (`spec/dummy`)
- Multiple adapters (memory, simulated hot/warm/cold adapters)
- Routing rules configured
- Event classes with retention_period DSL

**Test Structure:**
```ruby
RSpec.describe "Retention-Based Routing Integration", :integration do
  let(:hot_adapter) { E11y.config.adapters[:hot] }
  let(:warm_adapter) { E11y.config.adapters[:warm] }
  let(:cold_adapter) { E11y.config.adapters[:cold] }
  
  before do
    # Configure adapters (simulated hot/warm/cold)
    E11y.config.adapters[:hot] = E11y::Adapters::Memory.new
    E11y.config.adapters[:warm] = E11y::Adapters::Memory.new
    E11y.config.adapters[:cold] = E11y::Adapters::Memory.new
    
    # Configure routing rules
    E11y.config.routing_rules = [
      ->(event) {
        return nil unless event[:retention_until]
        days = (Time.parse(event[:retention_until]) - Time.now) / 86400
        if days > 90
          :cold
        elsif days > 7
          :warm
        else
          :hot
        end
      }
    ]
    
    E11y.config.fallback_adapters = [:hot]
  end
  
  after do
    hot_adapter.clear! if hot_adapter.respond_to?(:clear!)
    warm_adapter.clear! if warm_adapter.respond_to?(:clear!)
    cold_adapter.clear! if cold_adapter.respond_to?(:clear!)
  end
  
  describe "Scenario 1: Hot/warm/cold routing" do
    # Test implementation
  end
  
  # ... other scenarios
end
```

### 3.2. Assertion Strategy

**Routing Assertions:**
- ✅ Adapter selection: `expect(event[:routing][:adapters]).to include(:hot)`
- ✅ Routing metadata: `expect(event[:routing][:routing_type]).to eq(:rules)`
- ✅ Multi-adapter: Events routed to multiple adapters correctly

**Retention Assertions:**
- ✅ Retention calculation: `retention_until` calculated correctly from `retention_period`
- ✅ Age-based routing: Events routed based on retention age
- ✅ Retention period: `retention_period` preserved in event data

**Priority Assertions:**
- ✅ Explicit adapters: Explicit adapters bypass routing rules
- ✅ Rule order: Routing rules evaluated in order
- ✅ Fallback: Fallback adapters used when no rule matches

---

## 📋 4. Integration Test Scenarios

### Scenario 1: Hot/Warm/Cold Routing

**Objective:** Verify events routed to appropriate storage tiers based on retention period.

**Setup:**
- Three adapters configured (hot, warm, cold)
- Routing rules based on retention_until calculation

**Test Steps:**
1. Short retention: Track event with `retention_period: 7.days`
2. Verify: Event routed to hot adapter
3. Medium retention: Track event with `retention_period: 30.days`
4. Verify: Event routed to warm adapter
5. Long retention: Track event with `retention_period: 90.days`
6. Verify: Event routed to cold adapter

**Assertions:**
- Hot routing: `expect(event[:routing][:adapters]).to include(:hot)`
- Warm routing: `expect(event[:routing][:adapters]).to include(:warm)`
- Cold routing: `expect(event[:routing][:adapters]).to include(:cold)`

**Note:** Tiered storage adapters not implemented. Tests should simulate with different adapters or note limitation.

---

### Scenario 2: Age-Based Rules

**Objective:** Verify routing based on retention_until calculation.

**Setup:**
- Routing rules based on days until retention_until

**Test Steps:**
1. Track event: Track event with `retention_period: 7.days`
2. Verify: `retention_until` calculated correctly
3. Verify: Routing rule evaluates days correctly
4. Verify: Event routed to appropriate adapter

**Assertions:**
- Retention calculation: `expect(event[:retention_until]).to be_a(String)`
- Age calculation: Days calculated correctly from retention_until
- Routing decision: Event routed based on age

---

### Scenario 3: Priority Routing

**Objective:** Verify routing rules evaluated in priority order.

**Setup:**
- Multiple routing rules configured
- Rules evaluated in order

**Test Steps:**
1. Configure rules: Rule 1 (audit → encrypted), Rule 2 (long retention → cold)
2. Track audit event: Track event with `audit_event: true` and `retention_period: 90.days`
3. Verify: Event routed to encrypted adapter (Rule 1 matches first)
4. Track non-audit event: Track event with `retention_period: 90.days`
5. Verify: Event routed to cold adapter (Rule 2 matches)

**Assertions:**
- Rule priority: First matching rule determines routing
- Rule order: Rules evaluated in configured order
- Rule matching: Only first matching rule applied

---

### Scenario 4: Adapter Failover

**Objective:** Verify fallback adapters used when primary adapter fails.

**Setup:**
- Primary adapter configured (may fail)
- Fallback adapter configured

**Test Steps:**
1. Configure adapter: Primary adapter that fails
2. Configure fallback: Fallback adapter configured
3. Track event: Track event routed to primary adapter
4. Simulate failure: Primary adapter raises error
5. Verify: Event routed to fallback adapter

**Assertions:**
- Error handling: Routing errors don't break pipeline
- Failover: Fallback adapter used when primary fails
- Error logging: Routing errors logged correctly

**Note:** Adapter failover may not be fully implemented. Tests should verify current state or note limitation.

---

### Scenario 5: Multi-Adapter Fanout

**Objective:** Verify events routed to multiple adapters.

**Setup:**
- Routing rule returns array of adapters
- Multiple adapters configured

**Test Steps:**
1. Configure rule: Rule returns `[:datadog, :loki]` for errors
2. Track error event: Track event with `severity: :error`
3. Verify: Event routed to both datadog and loki adapters

**Assertions:**
- Multi-adapter: `expect(event[:routing][:adapters]).to include(:datadog, :loki)`
- Fanout: Event written to all specified adapters
- Adapter count: Correct number of adapters selected

---

### Scenario 6: Explicit Adapter Selection

**Objective:** Verify explicit adapters bypass routing rules.

**Setup:**
- Routing rules configured
- Event with explicit `adapters` field

**Test Steps:**
1. Configure rules: Routing rules configured
2. Track event: Track event with explicit `adapters: [:memory]`
3. Verify: Event routed to memory adapter (bypasses rules)
4. Verify: Routing metadata indicates explicit routing

**Assertions:**
- Explicit routing: `expect(event[:routing][:routing_type]).to eq(:explicit)`
- Rule bypass: Routing rules not evaluated
- Adapter selection: Explicit adapter used

---

## 🔗 5. Dependencies & Integration Points

### 5.1. TraceContext Middleware Integration

**Integration Point:** `E11y::Middleware::TraceContext`

**Flow:**
1. Event tracked → `retention_period` specified
2. TraceContext middleware → Calculates `retention_until` from `retention_period`
3. Routing middleware → Uses `retention_until` for routing decisions

**Test Requirements:**
- TraceContext middleware configured
- Retention period DSL used in event classes
- Retention until calculated correctly

### 5.2. Routing Middleware Integration

**Integration Point:** `E11y::Middleware::Routing`

**Flow:**
1. Event tracked → Routing middleware receives event_data
2. Routing middleware → Applies routing rules
3. Adapter selection → Event routed to selected adapters

**Test Requirements:**
- Routing middleware configured
- Routing rules configured
- Adapters configured
- Event routing verified

### 5.3. Adapter Integration

**Integration Point:** Adapters (`E11y::Adapters::*`)

**Flow:**
1. Event routed → Adapter selected
2. Adapter.write → Event written to adapter
3. Error handling → Failover if adapter fails

**Test Requirements:**
- Adapters configured
- Adapter.write works correctly
- Error handling verified

---

## ⚠️ 6. Known Limitations & Gaps

### 6.1. Tiered Storage Adapters

**Status:** ❌ **NOT IMPLEMENTED** (per AUDIT-019, Phase 5)

**Gap:** No hot/warm/cold tier adapters implemented.

**Impact:** Integration tests should simulate with different adapters or note limitation.

### 6.2. Lifecycle Transitions

**Status:** ❌ **NOT IMPLEMENTED** (Phase 5)

**Gap:** No automatic hot → warm → cold transitions.

**Impact:** Integration tests should note limitation.

### 6.3. Retention Enforcement

**Status:** ❌ **NOT IMPLEMENTED** (Phase 5)

**Gap:** No deletion after retention period.

**Impact:** Integration tests should note limitation.

---

## 📝 7. Test Data Requirements

### 7.1. Event Classes

**Required Event Classes:**
- `Events::DebugEvent` - Short retention (7 days)
- `Events::ApplicationEvent` - Medium retention (30 days)
- `Events::AuditEvent` - Long retention (7 years)

**Location:** `spec/dummy/app/events/events/`

### 7.2. Test Adapters

**Required Adapters:**
- Hot adapter: Memory adapter (simulated hot storage)
- Warm adapter: Memory adapter (simulated warm storage)
- Cold adapter: Memory adapter (simulated cold storage)

### 7.3. Test Retention Periods

**Required Retention Periods:**
- Short: 7 days
- Medium: 30 days
- Long: 90 days
- Very long: 7 years

---

## ✅ 8. Definition of Done

**Integration tests are complete when:**
1. ✅ All 6 scenarios implemented and passing
2. ✅ Hot/warm/cold routing tested (if implemented, or simulated)
3. ✅ Age-based rules tested (routing based on retention_until)
4. ✅ Priority routing tested (rules evaluated in order)
5. ✅ Adapter failover tested (if implemented, or current state verified)
6. ✅ Multi-adapter fanout tested (events routed to multiple adapters)
7. ✅ Explicit adapter selection tested (bypass routing rules)
8. ✅ All tests pass in CI

---

## 📚 9. References

- **UC-019:** `docs/use_cases/UC-019-retention-based-routing.md`
- **ADR-004:** `docs/ADR-004-adapter-architecture.md` (Section 14: Retention-Based Routing)
- **ADR-009:** `docs/ADR-009-cost-optimization.md` (Section 6: Cost Optimization via Routing)
- **AUDIT-019:** `docs/researches/post_implementation/AUDIT-019-UC-019-ROUTING-POLICIES.md`
- **Routing Middleware:** `lib/e11y/middleware/routing.rb`
- **TraceContext Middleware:** `lib/e11y/middleware/trace_context.rb`

---

**Analysis Complete:** 2026-01-26  
**Next Step:** UC-019 Phase 2: Planning Complete

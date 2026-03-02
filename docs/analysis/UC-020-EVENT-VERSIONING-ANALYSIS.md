# UC-020 Event Versioning: Integration Test Analysis

**Task:** FEAT-5417 - UC-020 Phase 1: Analysis Complete  
**Date:** 2026-01-26  
**Status:** Analysis Complete

---

## 📋 Executive Summary

**Current State:**
- ✅ **Implemented:** Versioning Middleware (`E11y::Middleware::Versioning`) - Extracts version from class name, normalizes event_name, adds `v:` field
- ✅ **Implemented:** Version Extraction - Extracts version from class name suffix (V2, V3, etc.)
- ✅ **Implemented:** Event Name Normalization - Normalizes event_name (removes version suffix for consistent queries)
- ✅ **Implemented:** Version Field (`v:`) - Adds `v:` field only if version > 1
- ✅ **Implemented:** Parallel Versions - V1 and V2 classes can coexist
- ✅ **Implemented:** Version DSL (`version`) - Event classes can declare version explicitly
- ⚠️ **PARTIAL:** Transform/Upgrade/Downgrade - May not be fully implemented (user responsibility per C15 Resolution)
- ⚠️ **PARTIAL:** Schema Registry - May not be fully implemented (Event Registry integration)
- ⚠️ **PARTIAL:** Mixed Versions - Multiple versions in same trace may not be fully tested

**Unit Test Coverage:** Good (comprehensive tests for Versioning middleware, version extraction, event name normalization)

**Integration Test Coverage:** ❌ **NONE** - No integration tests exist for event versioning

**Gap Analysis:** Integration tests needed for:
1. V1→V2 upgrade (tracking V1 event, then V2 event, verify both work)
2. V2→V1 downgrade (tracking V2 event, then V1 event, verify both work)
3. Transform (if implemented, verify version transformation works)
4. Mixed versions (multiple versions in same trace)
5. Schema registry (if implemented, verify version registration)
6. Version normalization (verify event_name normalized correctly)
7. Version field (verify `v:` field added correctly)

---

## 🔍 1. Current Implementation Analysis

### 1.1. Code Structure

**Location:** `lib/e11y/middleware/versioning.rb`, `lib/e11y/event/base.rb` (version DSL)

**Key Components:**
- `E11y::Middleware::Versioning` - Extracts version, normalizes event_name, adds `v:` field
- `Event::Base.version` - Version DSL for event classes
- Version extraction regex (`VERSION_REGEX = /V(\d+)$/`) - Matches V2, V3, etc. at end of class name

**Versioning Flow:**
1. Event tracked → `EventV2.track(...)`
2. Versioning middleware → Extracts version from class name (V2 → 2)
3. Versioning middleware → Normalizes event_name (removes version suffix)
4. Versioning middleware → Adds `v:` field if version > 1
5. Event stored → Event stored with normalized event_name and version field

**Middleware Order:**
- Versioning middleware is LAST in pipeline (after validation, PII filtering, rate limiting, sampling)
- Business logic uses ORIGINAL class name (e.g., `Events::OrderPaidV2`)
- Adapters receive NORMALIZED event_name (e.g., `order.paid`)

### 1.2. Current Features

| Feature | Status | Implementation |
|---------|--------|----------------|
| Version Extraction | ✅ Implemented | Extracts version from class name suffix (V2, V3, etc.) |
| Event Name Normalization | ✅ Implemented | Normalizes event_name (removes version suffix) |
| Version Field (`v:`) | ✅ Implemented | Adds `v:` field only if version > 1 |
| Parallel Versions | ✅ Implemented | V1 and V2 classes can coexist |
| Version DSL | ✅ Implemented | Event classes can declare `version` explicitly |
| Transform/Upgrade | ⚠️ PARTIAL | May not be fully implemented (user responsibility) |
| Schema Registry | ⚠️ PARTIAL | May not be fully implemented |
| Mixed Versions | ⚠️ PARTIAL | May not be fully tested |

### 1.3. Configuration

**Current API:**
```ruby
# Enable versioning middleware (opt-in)
E11y.configure do |config|
  config.pipeline.use E11y::Middleware::Versioning
end

# V1 Event (no version suffix)
class Events::OrderPaid < E11y::Event::Base
  version 1  # Optional for V1
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:decimal)
  end
end

# V2 Event (version suffix)
class Events::OrderPaidV2 < E11y::Event::Base
  version 2  # Explicit version
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:decimal)
    required(:currency).filled(:string)  # New required field
  end
end

# Usage
Events::OrderPaid.track(order_id: '123', amount: 99.99)
# → event_name: "order.paid", no v: field (V1 implicit)

Events::OrderPaidV2.track(order_id: '123', amount: 99.99, currency: 'USD')
# → event_name: "order.paid", v: 2
```

---

## 📊 2. Unit Test Coverage Analysis

### 2.1. Test File: `spec/e11y/middleware/versioning_spec.rb`

**Coverage Summary:**
- ✅ **Version extraction** (V1, V2, V3+)
- ✅ **Event name normalization** (removes version suffix)
- ✅ **Version field** (`v:` field added only if version > 1)
- ✅ **V1 events** (no `v:` field)
- ✅ **V2+ events** (`v:` field added)

**Key Test Scenarios:**
- Version extraction from class name
- Event name normalization
- Version field addition
- V1 vs V2+ behavior

---

## 🎯 3. Integration Test Requirements

### 3.1. Test Infrastructure

**Pattern:** Follow `spec/integration/audit_trail_integration_spec.rb` structure

**Key Components:**
- Rails dummy app (`spec/dummy`)
- Multiple event versions (V1, V2, V3)
- Memory adapter for event capture
- Versioning middleware enabled

**Test Structure:**
```ruby
RSpec.describe "Event Versioning Integration", :integration do
  let(:memory_adapter) { E11y.config.adapters[:memory] }
  
  before do
    memory_adapter.clear!
    
    # Enable versioning middleware
    E11y.config.pipeline.use E11y::Middleware::Versioning
    
    E11y.config.fallback_adapters = [:memory]
  end
  
  after do
    memory_adapter.clear!
  end
  
  describe "Scenario 1: V1→V2 upgrade" do
    # Test implementation
  end
  
  # ... other scenarios
end
```

### 3.2. Assertion Strategy

**Version Assertions:**
- ✅ Version extraction: `expect(event[:v]).to eq(2)`
- ✅ Event name normalization: `expect(event[:event_name]).to eq("order.paid")`
- ✅ V1 events: No `v:` field for V1 events
- ✅ V2+ events: `v:` field present for V2+ events

**Schema Assertions:**
- ✅ V1 schema: V1 events validate against V1 schema
- ✅ V2 schema: V2 events validate against V2 schema
- ✅ Schema differences: V1 and V2 schemas can differ

**Query Assertions:**
- ✅ Normalized queries: Query by `event_name` matches all versions
- ✅ Version-specific queries: Query by `event_name` and `v:` matches specific version

---

## 📋 4. Integration Test Scenarios

### Scenario 1: V1→V2 Upgrade

**Objective:** Verify V1 and V2 events can coexist during upgrade.

**Setup:**
- V1 event class (`Events::OrderPaid`)
- V2 event class (`Events::OrderPaidV2`)
- Versioning middleware enabled

**Test Steps:**
1. Track V1 event: Track `Events::OrderPaid.track(order_id: '123', amount: 99.99)`
2. Verify: Event stored with `event_name: "order.paid"`, no `v:` field
3. Track V2 event: Track `Events::OrderPaidV2.track(order_id: '456', amount: 199.99, currency: 'USD')`
4. Verify: Event stored with `event_name: "order.paid"`, `v: 2`
5. Query: Query events by `event_name: "order.paid"` returns both V1 and V2 events

**Assertions:**
- V1 event: `expect(v1_event[:v]).to be_nil`
- V2 event: `expect(v2_event[:v]).to eq(2)`
- Normalized name: Both events have `event_name: "order.paid"`
- Query: `expect(events.size).to eq(2)`

---

### Scenario 2: V2→V1 Downgrade

**Objective:** Verify V2 events can coexist with V1 events during downgrade.

**Setup:**
- V1 and V2 event classes
- Versioning middleware enabled

**Test Steps:**
1. Track V2 event: Track V2 event
2. Verify: Event stored with `v: 2`
3. Track V1 event: Track V1 event
4. Verify: Event stored without `v:` field
5. Query: Query events returns both versions

**Assertions:**
- V2 event: `expect(v2_event[:v]).to eq(2)`
- V1 event: `expect(v1_event[:v]).to be_nil`
- Coexistence: Both versions stored correctly

---

### Scenario 3: Transform

**Objective:** Verify version transformation works (if implemented).

**Setup:**
- V1 and V2 event classes
- Transform logic (if implemented)

**Test Steps:**
1. Track V1 event: Track V1 event
2. Transform: Transform V1 event to V2 format (if implemented)
3. Verify: Transformed event has V2 schema

**Assertions:**
- Transform: Transform works correctly (if implemented)
- Schema: Transformed event validates against V2 schema

**Note:** Transform may not be implemented. Tests should verify current state or note limitation.

---

### Scenario 4: Mixed Versions

**Objective:** Verify multiple versions in same trace work correctly.

**Setup:**
- V1 and V2 event classes
- Same trace_id for both events

**Test Steps:**
1. Track V1 event: Track V1 event with `trace_id: "abc-123"`
2. Track V2 event: Track V2 event with `trace_id: "abc-123"`
3. Verify: Both events have same trace_id
4. Verify: V1 event has no `v:` field, V2 event has `v: 2`

**Assertions:**
- Same trace: `expect(v1_event[:trace_id]).to eq(v2_event[:trace_id])`
- V1 version: `expect(v1_event[:v]).to be_nil`
- V2 version: `expect(v2_event[:v]).to eq(2)`

---

### Scenario 5: Schema Registry

**Objective:** Verify event registry tracks versions (if implemented).

**Setup:**
- Event registry (if implemented)
- Multiple event versions

**Test Steps:**
1. Register V1: Register V1 event class
2. Register V2: Register V2 event class
3. Verify: Registry tracks both versions
4. Query: Query registry for event versions

**Assertions:**
- Version tracking: Registry tracks all versions
- Version query: Can query versions for event name

**Note:** Schema registry may not be fully implemented. Tests should verify current state or note limitation.

---

### Scenario 6: Version Normalization

**Objective:** Verify event_name normalized correctly across versions.

**Setup:**
- V1, V2, V3 event classes
- Versioning middleware enabled

**Test Steps:**
1. Track V1: Track `Events::OrderPaid.track(...)`
2. Track V2: Track `Events::OrderPaidV2.track(...)`
3. Track V3: Track `Events::OrderPaidV3.track(...)`
4. Verify: All events have normalized `event_name: "order.paid"`

**Assertions:**
- Normalized name: `expect(event[:event_name]).to eq("order.paid")` for all versions
- Version field: V1 has no `v:`, V2 has `v: 2`, V3 has `v: 3`

---

### Scenario 7: Version Field

**Objective:** Verify `v:` field added correctly.

**Setup:**
- V1, V2, V3 event classes
- Versioning middleware enabled

**Test Steps:**
1. Track V1: Track V1 event
2. Verify: No `v:` field
3. Track V2: Track V2 event
4. Verify: `v: 2` field present
5. Track V3: Track V3 event
6. Verify: `v: 3` field present

**Assertions:**
- V1: `expect(v1_event[:v]).to be_nil`
- V2: `expect(v2_event[:v]).to eq(2)`
- V3: `expect(v3_event[:v]).to eq(3)`

---

## 🔗 5. Dependencies & Integration Points

### 5.1. Versioning Middleware Integration

**Integration Point:** `E11y::Middleware::Versioning`

**Flow:**
1. Event tracked → Versioning middleware receives event_data
2. Versioning middleware → Extracts version from class name
3. Versioning middleware → Normalizes event_name
4. Versioning middleware → Adds `v:` field if version > 1

**Test Requirements:**
- Versioning middleware configured
- Event classes with version suffixes
- Version extraction verified
- Event name normalization verified

### 5.2. Event Class Integration

**Integration Point:** `E11y::Event::Base`

**Flow:**
1. Event class defined → `class Events::OrderPaidV2`
2. Version extracted → Versioning middleware extracts version from class name
3. Event tracked → Event tracked with version metadata

**Test Requirements:**
- Multiple event versions defined
- Version DSL used correctly
- Schema differences between versions

### 5.3. Adapter Integration

**Integration Point:** Adapters (`E11y::Adapters::*`)

**Flow:**
1. Event routed → Adapter receives normalized event_name
2. Adapter.write → Event written with version metadata

**Test Requirements:**
- Adapters receive normalized event_name
- Version field preserved in stored events
- Query by event_name matches all versions

---

## ⚠️ 6. Known Limitations & Gaps

### 6.1. Transform/Upgrade/Downgrade

**Status:** ⚠️ **PARTIAL** (user responsibility per C15 Resolution)

**Gap:** Automatic version transformation may not be implemented. User responsible for migration logic.

**Impact:** Integration tests should verify current state (parallel versions work) or note limitation.

### 6.2. Schema Registry

**Status:** ⚠️ **PARTIAL** (may not be fully implemented)

**Gap:** Event registry integration may not be fully implemented.

**Impact:** Integration tests should verify current state or note limitation.

### 6.3. Mixed Versions in Trace

**Status:** ⚠️ **PARTIAL** (may not be fully tested)

**Gap:** Multiple versions in same trace may not be fully tested.

**Impact:** Integration tests should verify mixed versions work correctly.

---

## 📝 7. Test Data Requirements

### 7.1. Event Classes

**Required Event Classes:**
- `Events::OrderPaid` - V1 event (no version suffix)
- `Events::OrderPaidV2` - V2 event (version suffix)
- `Events::OrderPaidV3` - V3 event (version suffix)

**Location:** `spec/dummy/app/events/events/`

### 7.2. Test Payloads

**Required Payloads:**
- V1 payload: `{ order_id: "123", amount: 99.99 }`
- V2 payload: `{ order_id: "456", amount: 199.99, currency: "USD" }`
- V3 payload: `{ order_id: "789", amount: 299.99, currency: "EUR", tax: 10.0 }`

### 7.3. Test Trace IDs

**Required Trace IDs:**
- Same trace: `"trace-123"` (for mixed versions scenario)
- Different traces: `"trace-456"`, `"trace-789"`

---

## ✅ 8. Definition of Done

**Integration tests are complete when:**
1. ✅ All 7 scenarios implemented and passing
2. ✅ V1→V2 upgrade tested (both versions coexist)
3. ✅ V2→V1 downgrade tested (both versions coexist)
4. ✅ Transform tested (if implemented, or current state verified)
5. ✅ Mixed versions tested (multiple versions in same trace)
6. ✅ Schema registry tested (if implemented, or current state verified)
7. ✅ Version normalization tested (event_name normalized correctly)
8. ✅ Version field tested (`v:` field added correctly)
9. ✅ All tests pass in CI

---

## 📚 9. References

- **UC-020:** `docs/use_cases/UC-020-event-versioning.md`
- **ADR-012:** `docs/ADR-012-event-evolution.md`
- **ADR-015:** `docs/ADR-015-middleware-order.md` (Section 3: Versioning Middleware LAST)
- **Versioning Middleware:** `lib/e11y/middleware/versioning.rb`
- **Event Base:** `lib/e11y/event/base.rb` (version DSL)

---

**Analysis Complete:** 2026-01-26  
**Next Step:** UC-020 Phase 2: Planning Complete

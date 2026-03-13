# ADR-012 Event Evolution: Integration Test Analysis

**Task:** FEAT-5425 - ADR-012 Phase 1: Analysis Complete  
**Date:** 2026-01-26  
**Status:** Analysis Complete

---

## 📋 Executive Summary

**Current State:**
- ✅ **Implemented:** Versioning Middleware (`E11y::Middleware::Versioning`) - Extracts version from class name, normalizes event_name, adds `v:` field
- ✅ **Implemented:** Parallel Versions - V1 and V2 classes can coexist
- ✅ **Implemented:** Version DSL (`version`) - Event classes can declare version explicitly
- ✅ **Implemented:** Event Name Normalization - Normalizes event_name (removes version suffix)
- ✅ **Implemented:** Version Field (`v:`) - Adds `v:` field only if version > 1
- ⚠️ **PARTIAL:** Transform/Upgrade/Downgrade - May not be fully implemented (user responsibility per C15 Resolution)
- ⚠️ **PARTIAL:** Schema Migrations - May not be fully implemented (user responsibility per C15 Resolution)
- ⚠️ **PARTIAL:** Backward Compatibility - Parallel versions support backward compatibility, but migrations may not be automatic

**Unit Test Coverage:** Good (comprehensive tests for Versioning middleware, version extraction, event name normalization)

**Integration Test Coverage:** ❌ **NONE** - No integration tests exist for event evolution

**Gap Analysis:** Integration tests needed for:
1. Backward compatibility maintained (V1 and V2 events coexist)
2. Migrations work (if implemented, or verify current state)
3. No breaking changes (parallel versions prevent breaking changes)
4. Version coexistence (multiple versions in same system)
5. Schema evolution (adding/removing fields, renaming fields)
6. Version normalization (event_name normalized correctly)
7. Version field (v: field added correctly)

---

## 🔍 1. Current Implementation Analysis

### 1.1. Code Structure

**Location:** `lib/e11y/middleware/versioning.rb`, `lib/e11y/event/base.rb` (version DSL)

**Key Components:**
- `E11y::Middleware::Versioning` - Extracts version, normalizes event_name, adds `v:` field
- `Event::Base.version` - Version DSL for event classes
- Version extraction regex (`VERSION_REGEX = /V(\d+)$/`) - Matches V2, V3, etc. at end of class name

**Event Evolution Flow:**
1. V1 event tracked → `Events::OrderPaid.track(...)` (no version suffix)
2. V2 event tracked → `Events::OrderPaidV2.track(...)` (version suffix)
3. Versioning middleware → Extracts version from class name (V2 → 2)
4. Versioning middleware → Normalizes event_name (removes version suffix)
5. Versioning middleware → Adds `v:` field if version > 1
6. Storage → Both V1 and V2 events stored with normalized event_name

**Backward Compatibility:**
- V1 events continue to work (no changes needed)
- V2 events coexist with V1 events
- Both versions share same normalized event_name
- Query by event_name matches all versions

### 1.2. Current Features

| Feature | Status | Implementation |
|---------|--------|----------------|
| Parallel Versions | ✅ Implemented | V1 and V2 classes coexist |
| Version Extraction | ✅ Implemented | Extracts version from class name suffix |
| Event Name Normalization | ✅ Implemented | Normalizes event_name (removes version suffix) |
| Version Field (`v:`) | ✅ Implemented | Adds `v:` field only if version > 1 |
| Version DSL | ✅ Implemented | Event classes can declare `version` explicitly |
| Transform/Upgrade | ⚠️ PARTIAL | May not be fully implemented (user responsibility) |
| Schema Migrations | ⚠️ PARTIAL | May not be fully implemented (user responsibility) |
| Backward Compatibility | ✅ Implemented | Parallel versions support backward compatibility |

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
- Versioning middleware enabled
- Memory adapter for event capture

**Test Structure:**
```ruby
RSpec.describe "ADR-012 Event Evolution Integration", :integration do
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
  
  describe "Scenario 1: Backward compatibility maintained" do
    # Test implementation
  end
  
  # ... other scenarios
end
```

### 3.2. Assertion Strategy

**Backward Compatibility Assertions:**
- ✅ V1 events work: V1 events continue to work after V2 introduced
- ✅ V2 events work: V2 events work correctly
- ✅ Coexistence: Both versions coexist correctly

**Migration Assertions:**
- ✅ Migrations work: If implemented, migrations work correctly
- ✅ No breaking changes: Parallel versions prevent breaking changes

**Version Assertions:**
- ✅ Version extraction: Version extracted correctly from class name
- ✅ Event name normalization: Event name normalized correctly
- ✅ Version field: `v:` field added correctly

---

## 📋 4. Integration Test Scenarios

### Scenario 1: Backward Compatibility Maintained

**Objective:** Verify backward compatibility maintained (V1 events continue to work after V2 introduced).

**Setup:**
- V1 event class (`Events::OrderPaid`)
- V2 event class (`Events::OrderPaidV2`)
- Versioning middleware enabled

**Test Steps:**
1. Track V1 event: Track V1 event before V2 introduced
2. Introduce V2: Define V2 event class
3. Track V1 event: Track V1 event after V2 introduced
4. Verify: V1 events continue to work correctly

**Assertions:**
- V1 works: `expect(v1_event[:v]).to be_nil`
- V2 works: `expect(v2_event[:v]).to eq(2)`
- Coexistence: Both versions work correctly

---

### Scenario 2: Migrations Work

**Objective:** Verify migrations work correctly (if implemented).

**Setup:**
- V1 and V2 event classes
- Migration logic (if implemented)

**Test Steps:**
1. Track V1 event: Track V1 event
2. Migrate: Migrate V1 event to V2 format (if implemented)
3. Verify: Migrated event has V2 schema

**Assertions:**
- Migrations work: If implemented, migrations work correctly
- Schema: Migrated event validates against V2 schema

**Note:** Migrations may not be fully implemented (user responsibility per C15 Resolution). Tests should verify current state or note limitation.

---

### Scenario 3: No Breaking Changes

**Objective:** Verify parallel versions prevent breaking changes.

**Setup:**
- V1 event class (original schema)
- V2 event class (new schema with breaking change)

**Test Steps:**
1. Track V1 event: Track V1 event with original schema
2. Track V2 event: Track V2 event with new schema
3. Verify: Both versions work without breaking changes

**Assertions:**
- No breaking changes: Both versions work correctly
- Parallel versions: Parallel versions prevent breaking changes

---

### Scenario 4: Version Coexistence

**Objective:** Verify multiple versions coexist in same system.

**Setup:**
- V1, V2, V3 event classes
- Versioning middleware enabled

**Test Steps:**
1. Track V1: Track V1 event
2. Track V2: Track V2 event
3. Track V3: Track V3 event
4. Verify: All versions coexist correctly

**Assertions:**
- Coexistence: All versions coexist correctly
- Normalized name: All versions have same normalized event_name

---

### Scenario 5: Schema Evolution

**Objective:** Verify schema evolution works correctly (adding/removing fields, renaming fields).

**Setup:**
- V1 event class (original schema)
- V2 event class (evolved schema)

**Test Steps:**
1. Track V1: Track V1 event with original schema
2. Track V2: Track V2 event with evolved schema
3. Verify: Both schemas work correctly

**Assertions:**
- Adding fields: V2 can add required fields
- Removing fields: V2 can remove fields
- Renaming fields: V2 can rename fields (if supported)

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
1. Event tracked → Versioning middleware processes event
2. Version extraction → Extracts version from class name
3. Event name normalization → Normalizes event_name
4. Version field → Adds `v:` field if version > 1

**Test Requirements:**
- Versioning middleware configured
- Event classes with version suffixes
- Version extraction verified
- Event name normalization verified

### 5.2. Event Class Integration

**Integration Point:** `E11y::Event::Base`

**Flow:**
1. Event class defined → `class Events::OrderPaidV2`
2. Version extracted → Versioning middleware extracts version
3. Event tracked → Event tracked with version metadata

**Test Requirements:**
- Multiple event versions defined
- Version DSL used correctly
- Schema differences between versions

### 5.3. Storage Integration

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

### 6.2. Schema Migrations

**Status:** ⚠️ **PARTIAL** (user responsibility per C15 Resolution)

**Gap:** Schema migrations may not be fully implemented. User responsible for migration logic.

**Impact:** Integration tests should verify current state or note limitation.

### 6.3. Automatic Migration

**Status:** ❌ **NOT IMPLEMENTED** (per ADR-012)

**Gap:** No automatic migration (parallel versions pattern).

**Impact:** Integration tests should verify parallel versions work correctly.

---

## 📝 7. Test Data Requirements

### 7.1. Event Classes

**Required Event Classes:**
- `Events::OrderPaid` - V1 event (no version suffix)
- `Events::OrderPaidV2` - V2 event (version suffix, new required field)
- `Events::OrderPaidV3` - V3 event (version suffix, renamed field)

**Location:** `spec/dummy/app/events/events/`

### 7.2. Test Payloads

**Required Payloads:**
- V1 payload: `{ order_id: "123", amount: 99.99 }`
- V2 payload: `{ order_id: "456", amount: 199.99, currency: "USD" }`
- V3 payload: `{ order_id: "789", amount: 299.99, currency: "EUR", customer_id: "789" }` (renamed from user_id)

---

## ✅ 8. Definition of Done

**Integration tests are complete when:**
1. ✅ All 7 scenarios implemented and passing
2. ✅ Backward compatibility maintained (V1 events continue to work)
3. ✅ Migrations work (if implemented, or current state verified)
4. ✅ No breaking changes (parallel versions prevent breaking changes)
5. ✅ Version coexistence tested (multiple versions coexist)
6. ✅ Schema evolution tested (adding/removing/renaming fields)
7. ✅ Version normalization tested (event_name normalized correctly)
8. ✅ Version field tested (`v:` field added correctly)
9. ✅ All tests pass in CI

---

## 📚 9. References

- **ADR-012:** `docs/ADR-012-event-evolution.md`
- **UC-020:** `docs/use_cases/UC-020-event-versioning.md`
- **Versioning Middleware:** `lib/e11y/middleware/versioning.rb`
- **Event Base:** `lib/e11y/event/base.rb` (version DSL)

---

**Analysis Complete:** 2026-01-26  
**Note:** Transform/upgrade/downgrade and schema migrations may not be fully implemented (user responsibility per C15 Resolution). Integration tests should verify current state (parallel versions work) or note limitations.

**Next Step:** ADR-012 Phase 2: Planning Complete

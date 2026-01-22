# AUDIT-019: UC-019 Tiered Storage - Lifecycle & Retention Tests

**Audit ID:** AUDIT-019  
**Task:** FEAT-4981  
**Auditor:** AI Assistant (Claude Sonnet 4.5)  
**Date:** 2026-01-21  
**UC Reference:** UC-019 Retention-Based Event Routing (Phase 5)  
**Related:** AUDIT-019 FEAT-4980 (Routing & Policies), ADR-004 §14, UC-019  
**Industry Reference:** AWS S3 Lifecycle Tests, Google Cloud Storage Lifecycle

---

## 📋 Executive Summary

**Audit Objective:** Test data lifecycle and retention enforcement including lifecycle transitions (hot→warm after 7 days, warm→cold after 30 days), automatic deletion after retention period, and lifecycle metrics.

**Scope:**
- Lifecycle transitions: hot → warm → cold based on age
- Retention enforcement: automatic deletion after retention_until
- Monitoring: lifecycle metrics (events per tier)
- Time-travel testing: Timecop for age simulation

**Overall Status:** ❌ **NOT_IMPLEMENTED** (5%)

**Key Findings:**
- ✅ **PASS**: Routing tests exist (retention-based routing)
- ❌ **NOT_IMPLEMENTED**: Lifecycle transition tests (no hot→warm→cold)
- ❌ **NOT_IMPLEMENTED**: Retention enforcement tests (no deletion tests)
- ❌ **NOT_IMPLEMENTED**: Lifecycle metrics tests
- ❌ **NOT_IMPLEMENTED**: Time-travel tests (no Timecop usage)

**Critical Gaps:**
1. **NOT_IMPLEMENTED**: No lifecycle transition tests (hot→warm→cold)
2. **NOT_IMPLEMENTED**: No retention enforcement tests (deletion after retention_until)
3. **NOT_IMPLEMENTED**: No lifecycle metrics tests
4. **NOT_IMPLEMENTED**: No time-travel tests (Timecop)

**Severity Assessment:**
- **Test Coverage Risk**: CRITICAL (core lifecycle features untested)
- **Compliance Risk**: CRITICAL (retention enforcement untested, GDPR/CCPA risk)
- **Production Readiness**: **NOT PRODUCTION-READY** (Phase 5 feature, no tests)
- **Recommendation**: Tests cannot exist without implementation (Phase 5 roadmap)

---

## 📊 Definition of Done (DoD) Verification

| DoD Requirement | Status | Evidence | Severity |
|----------------|--------|----------|----------|
| **(1a) Lifecycle: hot → warm after 7 days** | ❌ NOT_IMPLEMENTED | No transition tests | CRITICAL |
| **(1b) Lifecycle: warm → cold after 30 days** | ❌ NOT_IMPLEMENTED | No transition tests | CRITICAL |
| **(2a) Deletion: after retention period** | ❌ NOT_IMPLEMENTED | No deletion tests | CRITICAL |
| **(2b) Deletion: no manual intervention** | ❌ NOT_IMPLEMENTED | No automation tests | CRITICAL |
| **(3a) Monitoring: events per tier** | ❌ NOT_IMPLEMENTED | No metrics tests | HIGH |
| **(4a) Time-travel: Timecop tests** | ❌ NOT_IMPLEMENTED | No Timecop usage | HIGH |

**DoD Compliance:** 0/6 requirements met (0%)

---

## 🔍 AUDIT AREA 1: Existing Test Coverage

### F-325: Routing Tests Exist (PASS)

**Finding:** E11y has comprehensive routing tests in `spec/e11y/middleware/routing_spec.rb`.

**Evidence:**

```ruby
# spec/e11y/middleware/routing_spec.rb:338-411

describe "UC-019 compliance (Retention-Based Routing)" do
  it "routes short retention events to hot storage" do
    E11y.configuration.routing_rules = [
      lambda { |event|
        days = (Time.parse(event[:retention_until]) - Time.now) / 86_400
        days <= 30 ? :loki : :s3_glacier
      }
    ]

    event_data = {
      event_name: "debug.log",
      retention_until: (Time.now + 7.days).iso8601
    }

    middleware.call(event_data)

    expect(loki_adapter).to have_received(:write)
    expect(s3_glacier_adapter).not_to have_received(:write)
  end

  it "routes long retention events to cold storage" do
    E11y.configuration.routing_rules = [
      lambda { |event|
        days = (Time.parse(event[:retention_until]) - Time.now) / 86_400
        days > 90 ? :s3_glacier : :loki
      }
    ]

    event_data = {
      event_name: "audit.user_deleted",
      retention_until: (Time.now + 365.days).iso8601
    }

    middleware.call(event_data)

    expect(s3_glacier_adapter).to have_received(:write)
    expect(loki_adapter).not_to have_received(:write)
  end

  it "routes audit events to encrypted storage (+ other matching rules)" do
    E11y.configuration.routing_rules = [
      ->(event) { :audit_encrypted if event[:audit_event] }
    ]

    event_data = {
      event_name: "user.deleted",
      audit_event: true,
      retention_until: (Time.now + 7.years).iso8601
    }

    middleware.call(event_data)

    expect(audit_adapter).to have_received(:write)
  end
end
```

**Test Coverage:**
- ✅ Retention-based routing (short → hot, long → cold)
- ✅ Audit event routing (audit_event → encrypted storage)
- ✅ Error routing (errors → Sentry + storage)
- ✅ Explicit adapters (bypass routing)
- ✅ Fallback adapters (no rule matches)
- ✅ Rule evaluation errors (graceful degradation)
- ✅ Adapter write errors (continue to other adapters)

**Analysis:**
- **Routing tests are EXCELLENT** (comprehensive, edge cases covered)
- Tests verify routing DECISIONS, not lifecycle TRANSITIONS
- No tests for hot→warm→cold migration (because no implementation exists)

**Status:** ✅ **PASS** (routing tests comprehensive)

---

### F-326: Tiered Storage Simulation Test (PARTIAL)

**Finding:** One test simulates tiered storage routing (hot/warm/cold tiers).

**Evidence:**

```ruby
# spec/e11y/middleware/routing_spec.rb:511-550

it "handles tiered storage routing (hot/warm/cold)" do
  E11y.configuration.routing_rules = [
    lambda { |event|
      days = (Time.parse(event[:retention_until]) - Time.now) / 86_400
      case days
      when 0..7    then :stdout       # Very short
      when 8..30   then :loki         # Short
      when 31..90  then :s3           # Medium (simulating S3 Standard)
      else              :s3_glacier   # Long (cold storage)
      end
    }
  ]

  # Test hot tier
  hot_event = {
    event_name: "debug.log",
    retention_until: (Time.now + 5.days).iso8601
  }

  middleware.call(hot_event)
  expect(stdout_adapter).to have_received(:write).with(hot_event)

  # Test warm tier
  warm_event = {
    event_name: "business.event",
    retention_until: (Time.now + 15.days).iso8601
  }

  middleware.call(warm_event)
  expect(loki_adapter).to have_received(:write).with(warm_event)

  # Test cold tier
  cold_event = {
    event_name: "audit.log",
    retention_until: (Time.now + 100.days).iso8601
  }

  middleware.call(cold_event)
  expect(s3_glacier_adapter).to have_received(:write).with(cold_event)
end
```

**Analysis:**
- ✅ Tests routing to different tiers based on retention
- ❌ Does NOT test lifecycle transitions (hot→warm→cold)
- ❌ Does NOT test time-based migration
- ❌ Uses mock adapters (not real tiered storage adapters)

**Status:** ⚠️ **PARTIAL** (routing simulation, not lifecycle transitions)

---

## 🔍 AUDIT AREA 2: Lifecycle Transition Tests (NOT_IMPLEMENTED)

### F-327: Hot → Warm Transition Tests (NOT_IMPLEMENTED)

**Finding:** No tests for automatic hot → warm transition after 7 days.

**Expected Test:**

```ruby
# spec/e11y/lifecycle/transitions_spec.rb (NOT EXISTS)

RSpec.describe E11y::Lifecycle::Transitions do
  describe ".migrate_hot_to_warm" do
    it "migrates events from hot to warm after 7 days" do
      # Setup: Create event in hot tier
      event_data = {
        event_name: "debug.log",
        retention_until: (Time.now + 30.days).iso8601,
        tier: :hot,
        tier_expires_at: (Time.now + 7.days).iso8601
      }
      
      hot_adapter = E11y.configuration.adapters[:hot]
      hot_adapter.write(event_data)
      
      # Time travel: 8 days later
      Timecop.travel(Time.now + 8.days) do
        # Run migration
        E11y::Lifecycle::Transitions.migrate_hot_to_warm
        
        # Verify: Event moved to warm tier
        warm_adapter = E11y.configuration.adapters[:warm]
        warm_events = warm_adapter.query(event_name: "debug.log")
        
        expect(warm_events.size).to eq(1)
        expect(warm_events.first[:tier]).to eq(:warm)
        expect(warm_events.first[:migrated_at]).to be_within(1).of(Time.now)
        
        # Verify: Event removed from hot tier
        hot_events = hot_adapter.query(event_name: "debug.log")
        expect(hot_events).to be_empty
      end
    end
    
    it "does not migrate events younger than 7 days" do
      # Setup: Create event in hot tier (6 days ago)
      event_data = {
        event_name: "recent.log",
        retention_until: (Time.now + 30.days).iso8601,
        tier: :hot,
        tier_expires_at: (Time.now + 7.days).iso8601
      }
      
      hot_adapter = E11y.configuration.adapters[:hot]
      hot_adapter.write(event_data)
      
      # Time travel: 6 days later (not yet 7)
      Timecop.travel(Time.now + 6.days) do
        E11y::Lifecycle::Transitions.migrate_hot_to_warm
        
        # Verify: Event still in hot tier
        hot_events = hot_adapter.query(event_name: "recent.log")
        expect(hot_events.size).to eq(1)
        expect(hot_events.first[:tier]).to eq(:hot)
      end
    end
    
    it "logs migration for audit trail" do
      event_data = {
        event_name: "debug.log",
        retention_until: (Time.now + 30.days).iso8601,
        tier: :hot,
        tier_expires_at: (Time.now + 7.days).iso8601
      }
      
      hot_adapter = E11y.configuration.adapters[:hot]
      hot_adapter.write(event_data)
      
      Timecop.travel(Time.now + 8.days) do
        expect(E11y::AuditTrail).to receive(:log).with(
          event_name: "event.migrated",
          original_event: "debug.log",
          migrated_from: :hot,
          migrated_to: :warm,
          migrated_at: be_within(1).of(Time.now)
        )
        
        E11y::Lifecycle::Transitions.migrate_hot_to_warm
      end
    end
  end
end
```

**Evidence of Non-Existence:**

```bash
$ find spec/ -name "*lifecycle*" -o -name "*transition*"
# No results
```

**Status:** ❌ **NOT_IMPLEMENTED** (no lifecycle transition tests)

**Impact:** CRITICAL
- Cannot verify hot→warm migration works
- No regression detection if migration breaks
- No confidence in lifecycle automation

---

### F-328: Warm → Cold Transition Tests (NOT_IMPLEMENTED)

**Finding:** No tests for automatic warm → cold transition after 30 days.

**Expected Test:**

```ruby
# spec/e11y/lifecycle/transitions_spec.rb (NOT EXISTS)

describe ".migrate_warm_to_cold" do
  it "migrates events from warm to cold after 30 days" do
    # Setup: Create event in warm tier
    event_data = {
      event_name: "business.log",
      retention_until: (Time.now + 365.days).iso8601,
      tier: :warm,
      tier_expires_at: (Time.now + 30.days).iso8601
    }
    
    warm_adapter = E11y.configuration.adapters[:warm]
    warm_adapter.write(event_data)
    
    # Time travel: 31 days later
    Timecop.travel(Time.now + 31.days) do
      E11y::Lifecycle::Transitions.migrate_warm_to_cold
      
      # Verify: Event moved to cold tier
      cold_adapter = E11y.configuration.adapters[:cold]
      cold_events = cold_adapter.query(event_name: "business.log")
      
      expect(cold_events.size).to eq(1)
      expect(cold_events.first[:tier]).to eq(:cold)
      
      # Verify: Event removed from warm tier
      warm_events = warm_adapter.query(event_name: "business.log")
      expect(warm_events).to be_empty
    end
  end
  
  it "handles migration errors gracefully" do
    # Setup: Cold tier adapter fails
    cold_adapter = E11y.configuration.adapters[:cold]
    allow(cold_adapter).to receive(:write).and_raise("S3 Glacier error")
    
    event_data = {
      event_name: "business.log",
      retention_until: (Time.now + 365.days).iso8601,
      tier: :warm,
      tier_expires_at: (Time.now + 30.days).iso8601
    }
    
    warm_adapter = E11y.configuration.adapters[:warm]
    warm_adapter.write(event_data)
    
    Timecop.travel(Time.now + 31.days) do
      expect do
        E11y::Lifecycle::Transitions.migrate_warm_to_cold
      end.not_to raise_error
      
      # Verify: Event still in warm tier (migration failed)
      warm_events = warm_adapter.query(event_name: "business.log")
      expect(warm_events.size).to eq(1)
    end
  end
end
```

**Status:** ❌ **NOT_IMPLEMENTED** (no warm→cold transition tests)

**Impact:** CRITICAL
- Cannot verify warm→cold migration works
- No error handling verification
- No confidence in long-term storage automation

---

## 🔍 AUDIT AREA 3: Retention Enforcement Tests (NOT_IMPLEMENTED)

### F-329: Automatic Deletion Tests (NOT_IMPLEMENTED)

**Finding:** No tests for automatic deletion after retention_until expires.

**Expected Test:**

```ruby
# spec/e11y/lifecycle/retention_spec.rb (NOT EXISTS)

RSpec.describe E11y::Lifecycle::Retention do
  describe ".delete_expired_events" do
    it "deletes events past retention_until" do
      # Setup: Create event with 7-day retention
      event_data = {
        event_name: "debug.log",
        retention_until: (Time.now + 7.days).iso8601,
        tier: :hot
      }
      
      hot_adapter = E11y.configuration.adapters[:hot]
      hot_adapter.write(event_data)
      
      # Time travel: 8 days later (past retention)
      Timecop.travel(Time.now + 8.days) do
        E11y::Lifecycle::Retention.delete_expired_events
        
        # Verify: Event deleted
        hot_events = hot_adapter.query(event_name: "debug.log")
        expect(hot_events).to be_empty
      end
    end
    
    it "does not delete events within retention period" do
      # Setup: Create event with 30-day retention
      event_data = {
        event_name: "business.log",
        retention_until: (Time.now + 30.days).iso8601,
        tier: :warm
      }
      
      warm_adapter = E11y.configuration.adapters[:warm]
      warm_adapter.write(event_data)
      
      # Time travel: 20 days later (still within retention)
      Timecop.travel(Time.now + 20.days) do
        E11y::Lifecycle::Retention.delete_expired_events
        
        # Verify: Event NOT deleted
        warm_events = warm_adapter.query(event_name: "business.log")
        expect(warm_events.size).to eq(1)
      end
    end
    
    it "logs deletion for compliance audit (GDPR/CCPA)" do
      event_data = {
        event_name: "user.data",
        retention_until: (Time.now + 7.days).iso8601,
        tier: :hot
      }
      
      hot_adapter = E11y.configuration.adapters[:hot]
      hot_adapter.write(event_data)
      
      Timecop.travel(Time.now + 8.days) do
        expect(E11y::AuditTrail).to receive(:log).with(
          event_name: "event.deleted",
          reason: "retention_expired",
          original_event: "user.data",
          retention_until: (Time.now - 1.day).iso8601,
          deleted_at: be_within(1).of(Time.now)
        )
        
        E11y::Lifecycle::Retention.delete_expired_events
      end
    end
    
    it "deletes from all tiers (hot, warm, cold)" do
      # Setup: Create expired events in all tiers
      hot_event = {
        event_name: "hot.expired",
        retention_until: (Time.now + 1.day).iso8601,
        tier: :hot
      }
      
      warm_event = {
        event_name: "warm.expired",
        retention_until: (Time.now + 1.day).iso8601,
        tier: :warm
      }
      
      cold_event = {
        event_name: "cold.expired",
        retention_until: (Time.now + 1.day).iso8601,
        tier: :cold
      }
      
      E11y.configuration.adapters[:hot].write(hot_event)
      E11y.configuration.adapters[:warm].write(warm_event)
      E11y.configuration.adapters[:cold].write(cold_event)
      
      # Time travel: 2 days later
      Timecop.travel(Time.now + 2.days) do
        E11y::Lifecycle::Retention.delete_expired_events
        
        # Verify: All expired events deleted
        expect(E11y.configuration.adapters[:hot].query(event_name: "hot.expired")).to be_empty
        expect(E11y.configuration.adapters[:warm].query(event_name: "warm.expired")).to be_empty
        expect(E11y.configuration.adapters[:cold].query(event_name: "cold.expired")).to be_empty
      end
    end
  end
end
```

**Status:** ❌ **NOT_IMPLEMENTED** (no retention enforcement tests)

**Impact:** CRITICAL
- **Compliance risk** (GDPR/CCPA require deletion verification)
- Cannot verify retention policies are enforced
- No audit trail for deletions

---

## 🔍 AUDIT AREA 4: Lifecycle Metrics Tests (NOT_IMPLEMENTED)

### F-330: Events Per Tier Metrics (NOT_IMPLEMENTED)

**Finding:** No tests for lifecycle metrics (events per tier).

**Expected Test:**

```ruby
# spec/e11y/lifecycle/metrics_spec.rb (NOT EXISTS)

RSpec.describe "Lifecycle Metrics" do
  describe "events per tier" do
    it "exposes e11y_tier_events_total metric" do
      # Setup: Create events in different tiers
      hot_adapter = E11y.configuration.adapters[:hot]
      warm_adapter = E11y.configuration.adapters[:warm]
      cold_adapter = E11y.configuration.adapters[:cold]
      
      hot_adapter.write({ event_name: "hot.1", tier: :hot })
      hot_adapter.write({ event_name: "hot.2", tier: :hot })
      warm_adapter.write({ event_name: "warm.1", tier: :warm })
      cold_adapter.write({ event_name: "cold.1", tier: :cold })
      
      # Verify: Metrics exposed
      expect(Yabeda.e11y.tier_events_total.values).to eq({
        { tier: :hot } => 2,
        { tier: :warm } => 1,
        { tier: :cold } => 1
      })
    end
    
    it "updates metrics after migration" do
      # Setup: Event in hot tier
      hot_adapter = E11y.configuration.adapters[:hot]
      hot_adapter.write({
        event_name: "debug.log",
        retention_until: (Time.now + 30.days).iso8601,
        tier: :hot,
        tier_expires_at: (Time.now + 7.days).iso8601
      })
      
      # Initial metrics
      expect(Yabeda.e11y.tier_events_total.values[{ tier: :hot }]).to eq(1)
      expect(Yabeda.e11y.tier_events_total.values[{ tier: :warm }]).to eq(0)
      
      # Time travel: 8 days later
      Timecop.travel(Time.now + 8.days) do
        E11y::Lifecycle::Transitions.migrate_hot_to_warm
        
        # Verify: Metrics updated
        expect(Yabeda.e11y.tier_events_total.values[{ tier: :hot }]).to eq(0)
        expect(Yabeda.e11y.tier_events_total.values[{ tier: :warm }]).to eq(1)
      end
    end
    
    it "exposes e11y_tier_storage_bytes metric" do
      # Setup: Create events with known sizes
      hot_adapter = E11y.configuration.adapters[:hot]
      hot_adapter.write({
        event_name: "large.event",
        payload: { data: "x" * 1000 },  # ~1KB
        tier: :hot
      })
      
      # Verify: Storage metrics exposed
      expect(Yabeda.e11y.tier_storage_bytes.values[{ tier: :hot }]).to be > 1000
    end
  end
  
  describe "migration metrics" do
    it "exposes e11y_tier_migrations_total counter" do
      # Setup: Event in hot tier
      hot_adapter = E11y.configuration.adapters[:hot]
      hot_adapter.write({
        event_name: "debug.log",
        tier: :hot,
        tier_expires_at: (Time.now + 7.days).iso8601
      })
      
      Timecop.travel(Time.now + 8.days) do
        E11y::Lifecycle::Transitions.migrate_hot_to_warm
        
        # Verify: Migration counter incremented
        expect(Yabeda.e11y.tier_migrations_total.values).to include(
          { from_tier: :hot, to_tier: :warm } => 1
        )
      end
    end
  end
end
```

**Status:** ❌ **NOT_IMPLEMENTED** (no lifecycle metrics tests)

**Impact:** HIGH
- Cannot monitor tier distribution
- No visibility into lifecycle automation
- Cannot detect migration issues in production

---

## 🔍 AUDIT AREA 5: Time-Travel Tests (NOT_IMPLEMENTED)

### F-331: Timecop Usage (NOT_IMPLEMENTED)

**Finding:** No Timecop usage in E11y tests for time-based scenarios.

**Evidence:**

```bash
$ grep -r "Timecop" spec/
# No results

$ grep -r "time_travel\|travel_to" spec/
# No results
```

**Expected Usage:**

```ruby
# Gemfile (add Timecop)
group :test do
  gem "timecop"
end

# spec/spec_helper.rb (configure Timecop)
require "timecop"

RSpec.configure do |config|
  config.after(:each) do
    Timecop.return  # Reset time after each test
  end
end

# spec/e11y/lifecycle/transitions_spec.rb (use Timecop)
it "migrates events after 7 days" do
  # Create event
  event_data = { ... }
  adapter.write(event_data)
  
  # Time travel: 8 days later
  Timecop.travel(Time.now + 8.days) do
    E11y::Lifecycle::Transitions.migrate_hot_to_warm
    
    # Verify migration
    expect(warm_adapter.query(...)).not_to be_empty
  end
end
```

**Status:** ❌ **NOT_IMPLEMENTED** (no Timecop usage)

**Impact:** HIGH
- Cannot test time-based lifecycle transitions
- Cannot test retention enforcement (deletion after retention_until)
- Cannot simulate production scenarios (7 days, 30 days, 1 year)

---

## 📊 Summary of Findings

| Finding ID | Area | Status | Severity |
|-----------|------|--------|----------|
| F-325 | Routing tests | ✅ PASS | ✅ |
| F-326 | Tiered storage simulation | ⚠️ PARTIAL | INFO |
| F-327 | Hot→warm transition tests | ❌ NOT_IMPLEMENTED | CRITICAL |
| F-328 | Warm→cold transition tests | ❌ NOT_IMPLEMENTED | CRITICAL |
| F-329 | Retention enforcement tests | ❌ NOT_IMPLEMENTED | CRITICAL |
| F-330 | Lifecycle metrics tests | ❌ NOT_IMPLEMENTED | HIGH |
| F-331 | Timecop usage | ❌ NOT_IMPLEMENTED | HIGH |

**Metrics:**
- **PASS:** 1/7 findings (14%)
- **PARTIAL:** 1/7 findings (14%)
- **NOT_IMPLEMENTED:** 5/7 findings (71%)
- **DoD Compliance:** 0/6 requirements (0%)

---

## 🚨 Critical Gaps Analysis

### Gap 1: No Lifecycle Transition Tests (CRITICAL)

**Issue:** No tests for hot→warm→cold transitions.

**Evidence:**
- No `spec/e11y/lifecycle/transitions_spec.rb`
- No Timecop usage for time-travel
- Routing tests verify routing DECISIONS, not lifecycle TRANSITIONS

**Impact:**
- Cannot verify lifecycle automation works
- No regression detection if migration breaks
- No confidence in production lifecycle behavior

**Root Cause:** Phase 5 feature, no implementation to test

**Recommendation:** R-093: Add lifecycle transition tests (Phase 5, after R-091)

---

### Gap 2: No Retention Enforcement Tests (CRITICAL)

**Issue:** No tests for automatic deletion after retention_until.

**Evidence:**
- No `spec/e11y/lifecycle/retention_spec.rb`
- No deletion tests
- No audit trail tests for deletions

**Impact:**
- **Compliance risk** (GDPR/CCPA require deletion verification)
- Cannot verify retention policies enforced
- No proof of deletion for compliance audits

**Root Cause:** Phase 5 feature, no implementation to test

**Recommendation:** R-094: Add retention enforcement tests (Phase 5, after R-092)

---

### Gap 3: No Lifecycle Metrics Tests (HIGH)

**Issue:** No tests for lifecycle metrics (events per tier, migrations).

**Evidence:**
- No metrics tests for tiered storage
- No `e11y_tier_events_total` metric tests
- No `e11y_tier_migrations_total` metric tests

**Impact:**
- Cannot monitor tier distribution in production
- No visibility into lifecycle automation health
- Cannot detect migration issues

**Root Cause:** Phase 5 feature, no metrics implementation

**Recommendation:** R-095: Add lifecycle metrics tests (Phase 5)

---

## 🏗️ Implementation Plan (Phase 5 Roadmap)

### R-093: Add Lifecycle Transition Tests (HIGH, Phase 5)

**Priority:** HIGH (after R-091 lifecycle implementation)  
**Effort:** MEDIUM (3 test files + Timecop setup)  
**Dependencies:** R-091 (lifecycle transitions implementation)

**Implementation:**

1. Add Timecop gem:

```ruby
# Gemfile
group :test do
  gem "timecop"
end
```

2. Create transition tests:

```ruby
# spec/e11y/lifecycle/transitions_spec.rb

RSpec.describe E11y::Lifecycle::Transitions do
  describe ".migrate_hot_to_warm" do
    it "migrates events from hot to warm after 7 days" do
      # ... (see F-327 for full test)
    end
    
    it "does not migrate events younger than 7 days" do
      # ... (see F-327)
    end
    
    it "logs migration for audit trail" do
      # ... (see F-327)
    end
  end
  
  describe ".migrate_warm_to_cold" do
    it "migrates events from warm to cold after 30 days" do
      # ... (see F-328)
    end
    
    it "handles migration errors gracefully" do
      # ... (see F-328)
    end
  end
end
```

3. Add integration tests:

```ruby
# spec/integration/lifecycle_spec.rb

RSpec.describe "Lifecycle Integration" do
  it "handles full lifecycle: hot → warm → cold → delete" do
    # Create event in hot tier
    event_data = {
      event_name: "debug.log",
      retention_until: (Time.now + 40.days).iso8601,
      tier: :hot
    }
    
    hot_adapter.write(event_data)
    
    # Day 8: hot → warm
    Timecop.travel(Time.now + 8.days) do
      E11y::Lifecycle::Transitions.migrate_hot_to_warm
      expect(warm_adapter.query(event_name: "debug.log")).not_to be_empty
    end
    
    # Day 38: warm → cold
    Timecop.travel(Time.now + 38.days) do
      E11y::Lifecycle::Transitions.migrate_warm_to_cold
      expect(cold_adapter.query(event_name: "debug.log")).not_to be_empty
    end
    
    # Day 41: delete (past retention_until)
    Timecop.travel(Time.now + 41.days) do
      E11y::Lifecycle::Retention.delete_expired_events
      expect(cold_adapter.query(event_name: "debug.log")).to be_empty
    end
  end
end
```

---

### R-094: Add Retention Enforcement Tests (CRITICAL, Phase 5)

**Priority:** CRITICAL (compliance requirement)  
**Effort:** MEDIUM (1 test file + audit trail tests)  
**Dependencies:** R-092 (retention enforcement implementation)

**Implementation:**

```ruby
# spec/e11y/lifecycle/retention_spec.rb

RSpec.describe E11y::Lifecycle::Retention do
  describe ".delete_expired_events" do
    it "deletes events past retention_until" do
      # ... (see F-329)
    end
    
    it "does not delete events within retention period" do
      # ... (see F-329)
    end
    
    it "logs deletion for compliance audit (GDPR/CCPA)" do
      # ... (see F-329)
    end
    
    it "deletes from all tiers (hot, warm, cold)" do
      # ... (see F-329)
    end
  end
end
```

---

### R-095: Add Lifecycle Metrics Tests (MEDIUM, Phase 5)

**Priority:** MEDIUM (observability)  
**Effort:** LOW (1 test file)  
**Dependencies:** R-090 (tiered storage adapters), R-091 (lifecycle transitions)

**Implementation:**

```ruby
# spec/e11y/lifecycle/metrics_spec.rb

RSpec.describe "Lifecycle Metrics" do
  describe "events per tier" do
    it "exposes e11y_tier_events_total metric" do
      # ... (see F-330)
    end
    
    it "updates metrics after migration" do
      # ... (see F-330)
    end
    
    it "exposes e11y_tier_storage_bytes metric" do
      # ... (see F-330)
    end
  end
  
  describe "migration metrics" do
    it "exposes e11y_tier_migrations_total counter" do
      # ... (see F-330)
    end
  end
end
```

---

## 🔬 What Can Be Tested Today (Despite NOT_IMPLEMENTED)

### Routing Tests (Already Comprehensive)

**E11y's routing tests are PRODUCTION-READY:**

```ruby
# spec/e11y/middleware/routing_spec.rb (EXISTS)

describe "UC-019 compliance (Retention-Based Routing)" do
  it "routes short retention events to hot storage" do
    # ✅ WORKS TODAY (routing decision)
  end
  
  it "routes long retention events to cold storage" do
    # ✅ WORKS TODAY (routing decision)
  end
  
  it "routes audit events to encrypted storage" do
    # ✅ WORKS TODAY (routing decision)
  end
end
```

**What's Missing:**
- Lifecycle transition tests (hot→warm→cold)
- Retention enforcement tests (deletion)
- Lifecycle metrics tests
- Time-travel tests (Timecop)

---

## 📈 UC-019 Test Coverage Status

| UC-019 Feature | Test Coverage | Status |
|---------------|---------------|--------|
| Routing (initial write) | ✅ EXCELLENT | 100% (comprehensive tests) |
| Lifecycle transitions (hot→warm→cold) | ❌ NONE | 0% (no implementation) |
| Retention enforcement (deletion) | ❌ NONE | 0% (no implementation) |
| Lifecycle metrics | ❌ NONE | 0% (no implementation) |

**Overall Test Coverage:** 25% (routing only)

---

## 📊 Conclusion

### Overall Status: ❌ **NOT_IMPLEMENTED** (5%)

**What's Tested:**
- ✅ Routing decisions (retention-based, audit, errors)
- ✅ Explicit adapters (bypass routing)
- ✅ Fallback adapters
- ✅ Error handling (rule errors, adapter errors)

**What's NOT Tested:**
- ❌ Lifecycle transitions (hot→warm→cold)
- ❌ Retention enforcement (deletion)
- ❌ Lifecycle metrics
- ❌ Time-travel scenarios (Timecop)

### Production Readiness: **NOT PRODUCTION-READY**

**Rationale:**
- UC-019 is a **Phase 5 feature** (no implementation exists)
- Routing tests are EXCELLENT (can be used TODAY for simple multi-adapter routing)
- Lifecycle tests CANNOT exist without lifecycle implementation
- Tests will be added in Phase 5 (after R-091, R-092 implementation)

**Recommendations:**

1. **R-093**: Add lifecycle transition tests (HIGH, Phase 5 after R-091)
2. **R-094**: Add retention enforcement tests (CRITICAL, Phase 5 after R-092)
3. **R-095**: Add lifecycle metrics tests (MEDIUM, Phase 5)

**Compliance Impact:**
- **CRITICAL**: No retention enforcement tests (GDPR/CCPA require deletion verification)
- Cannot prove retention policies are enforced
- No audit trail for deletions

### Severity Assessment

| Risk Category | Severity | Mitigation |
|--------------|----------|------------|
| Test Coverage | CRITICAL | Tests cannot exist without implementation |
| Compliance | CRITICAL | No deletion tests (GDPR/CCPA risk) |
| Regression Detection | HIGH | No lifecycle tests (cannot detect breaks) |
| Production Readiness | NOT READY | Phase 5 feature, tests pending implementation |

**Final Verdict:** Lifecycle and retention tests NOT IMPLEMENTED (Phase 5 future work), routing tests are EXCELLENT and production-ready TODAY.

---

**Audit completed:** 2026-01-21  
**Next audit:** FEAT-4982 (Validate storage cost impact and query performance)

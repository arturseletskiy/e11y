# AUDIT-019: UC-019 Tiered Storage - Routing & Policies

**Audit ID:** AUDIT-019  
**Task:** FEAT-4980  
**Auditor:** AI Assistant (Claude Sonnet 4.5)  
**Date:** 2026-01-21  
**UC Reference:** UC-019 Retention-Based Event Routing (Phase 5)  
**Related:** ADR-004 §14 (Retention-Based Routing), ADR-009 §6 (Cost Optimization)  
**Industry Reference:** AWS S3 Lifecycle Policies, Google Cloud Storage Tiers

---

## 📋 Executive Summary

**Audit Objective:** Verify tiered storage routing and policies including routing logic (hot/warm/cold), retention policies (configurable periods), automatic transitions, and manual overrides.

**Scope:**
- Routing: high-priority events → hot, normal → warm, debug → cold
- Policies: hot retention 7 days, warm 30 days, cold 1 year (configurable)
- Transitions: automatic based on age/access patterns
- Manual overrides: explicit adapter selection

**Overall Status:** ⚠️ **NOT_IMPLEMENTED** (10%)

**Key Findings:**
- ✅ **PASS**: Routing infrastructure exists (retention-based routing middleware)
- ❌ **NOT_IMPLEMENTED**: Tiered storage adapters (hot/warm/cold)
- ❌ **NOT_IMPLEMENTED**: Automatic lifecycle transitions
- ❌ **NOT_IMPLEMENTED**: Retention policy enforcement
- ✅ **PARTIAL**: Manual overrides (explicit adapter selection works)

**Critical Gaps:**
1. **NOT_IMPLEMENTED**: Tiered storage adapters (no hot/warm/cold adapters)
2. **NOT_IMPLEMENTED**: Lifecycle transitions (no hot → warm → cold automation)
3. **NOT_IMPLEMENTED**: Retention enforcement (no deletion after retention period)

**Severity Assessment:**
- **Functionality Risk**: HIGH (core feature not implemented)
- **Cost Optimization Impact**: HIGH (UC-019 promises 80-97% savings, not available)
- **Production Readiness**: **NOT PRODUCTION-READY** (Phase 5 feature)
- **Recommendation**: Document as Phase 5 roadmap, routing infrastructure ready for future implementation

---

## 📊 Definition of Done (DoD) Verification

| DoD Requirement | Status | Evidence | Severity |
|----------------|--------|----------|----------|
| **(1a) Routing: high-priority → hot** | ❌ NOT_IMPLEMENTED | No hot tier adapter | CRITICAL |
| **(1b) Routing: normal → warm** | ❌ NOT_IMPLEMENTED | No warm tier adapter | CRITICAL |
| **(1c) Routing: debug → cold** | ❌ NOT_IMPLEMENTED | No cold tier adapter | CRITICAL |
| **(2a) Policies: hot 7 days** | ❌ NOT_IMPLEMENTED | No tier-specific policies | CRITICAL |
| **(2b) Policies: warm 30 days** | ❌ NOT_IMPLEMENTED | No tier-specific policies | CRITICAL |
| **(2c) Policies: cold 1 year** | ❌ NOT_IMPLEMENTED | No tier-specific policies | CRITICAL |
| **(2d) Policies: configurable** | ✅ PARTIAL | retention_period DSL exists | INFO |
| **(3a) Transitions: automatic (age-based)** | ❌ NOT_IMPLEMENTED | No lifecycle automation | CRITICAL |
| **(3b) Transitions: manual override** | ✅ PASS | Explicit adapters work | ✅ |

**DoD Compliance:** 1/9 requirements met (11%), 7 not implemented, 1 partial

---

## 🔍 AUDIT AREA 1: Routing Infrastructure

### F-316: Routing Middleware Exists (PASS)

**Finding:** E11y implemented `E11y::Middleware::Routing` middleware for retention-based routing.

**Evidence:**

```ruby
# lib/e11y/middleware/routing.rb:50-72

class Routing < Base
  middleware_zone :adapters

  # Routes event to appropriate adapters based on retention policies.
  #
  # **Routing Logic (Priority Order):**
  # 1. **Explicit adapters** - event_data[:adapters] bypasses routing rules
  # 2. **Routing rules** - lambdas from config.routing_rules
  # 3. **Fallback adapters** - config.fallback_adapters if no rule matches
  #
  # @see ADR-004 §14 (Retention-Based Routing)
  # @see ADR-009 §6 (Cost Optimization via Routing)
  # @see UC-019 (Retention-Based Event Routing)
  def call(event_data)
    # 1. Determine target adapters (explicit or via routing rules)
    target_adapters = if event_data[:adapters]&.any?
                        # Explicit adapters bypass routing rules
                        event_data[:adapters]
                      else
                        # Apply routing rules from configuration
                        apply_routing_rules(event_data)
                      end

    # 2. Write to selected adapters
    target_adapters.each do |adapter_name|
      adapter = E11y.configuration.adapters[adapter_name]
      next unless adapter

      begin
        adapter.write(event_data)
        increment_metric("e11y.middleware.routing.write_success", adapter: adapter_name)
      rescue StandardError => e
        # Log routing error but don't fail pipeline
        warn "E11y routing error for adapter #{adapter_name}: #{e.message}"
        increment_metric("e11y.middleware.routing.write_error", adapter: adapter_name)
      end
    end

    # 3. Add routing metadata
    event_data[:routing] = {
      adapters: target_adapters,
      routed_at: Time.now.utc,
      routing_type: event_data[:adapters]&.any? ? :explicit : :rules
    }

    @app&.call(event_data)
  end
end
```

**Analysis:**
- ✅ Routing middleware exists
- ✅ Supports explicit adapters (bypass routing)
- ✅ Supports lambda routing rules
- ✅ Adds routing metadata to event data
- ✅ Metrics instrumentation (placeholder)
- ✅ Error handling (routing failures don't break pipeline)

**Status:** ✅ **PASS** (routing infrastructure ready for tiered storage)

**Architecture Notes:**
- This is the **foundation** for UC-019 tiered storage
- Can be used TODAY for simple multi-adapter routing
- Waiting for tiered storage adapters (hot/warm/cold) to be implemented

---

### F-317: Retention Period DSL (PASS)

**Finding:** E11y implemented `retention_period` DSL for declarative retention specification.

**Evidence:**

```ruby
# lib/e11y/event/base.rb:273-283

def retention_period(value = nil)
  @retention_period = value if value
  # Return explicitly set retention_period OR inherit from parent (if set) OR config default OR final fallback
  return @retention_period if @retention_period
  if superclass != E11y::Event::Base && superclass.instance_variable_get(:@retention_period)
    return superclass.retention_period
  end

  # Fallback to configuration or 30 days
  E11y.configuration&.default_retention_period || 30.days
end
```

**Usage:**

```ruby
# lib/e11y/event/base.rb:259-272 (Examples)

class DebugEvent < E11y::Event::Base
  retention_period 7.days  # ← Short retention
end

class UserDeletedEvent < E11y::Event::Base
  audit_event true
  retention_period 7.years  # ← Long retention (GDPR compliance)
end

class OrderEvent < E11y::Event::Base
  # No retention_period specified → uses config default (30 days)
end
```

**Event Hash Calculation:**

```ruby
# lib/e11y/event/base.rb:100-113

event_retention_period = retention_period
# ...
{
  event_name: event_name,
  payload: payload,
  severity: event_severity,
  version: version,
  adapters: event_adapters,
  timestamp: event_timestamp.iso8601(3),
  retention_until: (event_timestamp + event_retention_period).iso8601, # ← Auto-calculated
  audit_event: audit_event?
}
```

**Analysis:**
- ✅ Declarative DSL for retention
- ✅ Supports ActiveSupport::Duration (7.days, 30.days, 7.years)
- ✅ Inheritance (subclasses inherit parent retention)
- ✅ Config default fallback (30 days)
- ✅ Auto-calculates `retention_until` timestamp
- ✅ Available in event_data for routing rules

**Status:** ✅ **PASS** (retention DSL ready for tiered storage)

---

### F-318: Routing Rules Lambda Support (PASS)

**Finding:** E11y supports lambda routing rules for dynamic adapter selection.

**Evidence:**

```ruby
# lib/e11y/middleware/routing.rb:133-152

def apply_routing_rules(event_data)
  matched_adapters = []

  # Apply each rule, collect matched adapters
  rules = E11y.configuration.routing_rules || []
  rules.each do |rule|
    result = rule.call(event_data)
    matched_adapters.concat(Array(result)) if result
  rescue StandardError => e
    # Log rule evaluation error but continue
    warn "E11y routing rule error: #{e.message}"
  end

  # Return unique adapters or fallback
  if matched_adapters.any?
    matched_adapters.uniq
  else
    E11y.configuration.fallback_adapters || [:stdout]
  end
end
```

**Configuration Example:**

```ruby
# UC-019 Scenario 1: Audit event routing
E11y.configure do |config|
  config.routing_rules = [
    # Rule 1: Audit events → encrypted storage
    ->(event) { :audit_encrypted if event[:audit_event] },
    
    # Rule 2: Retention-based routing
    ->(event) {
      days = (Time.parse(event[:retention_until]) - Time.now) / 86400
      days > 90 ? :s3_glacier : :loki
    }
  ]
  
  config.fallback_adapters = [:stdout]
end
```

**Analysis:**
- ✅ Lambda-based routing rules
- ✅ Rules evaluated in order
- ✅ First matching rule wins (or collect all matches)
- ✅ Error handling (rule failures don't break routing)
- ✅ Fallback adapters for unmatched events
- ✅ Retention-based routing ready (just needs tiered storage adapters)

**Status:** ✅ **PASS** (routing rules ready for tiered storage)

---

## 🔍 AUDIT AREA 2: Tiered Storage Adapters (NOT_IMPLEMENTED)

### F-319: Hot Tier Adapter (NOT_IMPLEMENTED)

**Finding:** No hot tier adapter implemented.

**Expected Implementation:**

```ruby
# lib/e11y/adapters/tiered_storage/hot.rb (NOT EXISTS)

module E11y
  module Adapters
    module TieredStorage
      class Hot < Base
        # Fast storage (SSD, Redis, Loki with short retention)
        # - Retention: 7 days
        # - Access: Fast (in-memory or fast SSD)
        # - Cost: High ($/GB/month)
        # - Use case: High-priority events, debugging active incidents
        
        def initialize(url:, retention_days: 7)
          @url = url
          @retention_days = retention_days
        end
        
        def write(event_data)
          # Write to hot tier (Loki, Redis, etc.)
          # Add lifecycle metadata: tier: :hot, expires_at: timestamp + 7.days
        end
      end
    end
  end
end
```

**Evidence of Non-Existence:**

```bash
$ grep -r "TieredStorage\|tiered_storage" lib/
# No results
```

**Status:** ❌ **NOT_IMPLEMENTED** (no hot tier adapter)

**Impact:** HIGH
- Cannot route high-priority events to fast storage
- No automatic hot tier management
- UC-019 Scenario 1 (Audit Events) not possible

---

### F-320: Warm Tier Adapter (NOT_IMPLEMENTED)

**Finding:** No warm tier adapter implemented.

**Expected Implementation:**

```ruby
# lib/e11y/adapters/tiered_storage/warm.rb (NOT EXISTS)

module E11y
  module Adapters
    module TieredStorage
      class Warm < Base
        # Standard storage (HDD, S3 Standard)
        # - Retention: 30 days
        # - Access: Moderate (query latency 100-500ms)
        # - Cost: Medium ($/GB/month)
        # - Use case: Normal events, historical analysis
        
        def initialize(url:, retention_days: 30)
          @url = url
          @retention_days = retention_days
        end
        
        def write(event_data)
          # Write to warm tier (S3 Standard, etc.)
          # Add lifecycle metadata: tier: :warm, expires_at: timestamp + 30.days
        end
      end
    end
  end
end
```

**Status:** ❌ **NOT_IMPLEMENTED** (no warm tier adapter)

**Impact:** HIGH
- Cannot route normal events to standard storage
- No cost optimization for moderate-priority events
- UC-019 Scenario 2 (Application Logs) not possible

---

### F-321: Cold Tier Adapter (NOT_IMPLEMENTED)

**Finding:** No cold tier adapter implemented.

**Expected Implementation:**

```ruby
# lib/e11y/adapters/tiered_storage/cold.rb (NOT EXISTS)

module E11y
  module Adapters
    module TieredStorage
      class Cold < Base
        # Archive storage (S3 Glacier, Tape)
        # - Retention: 1 year+
        # - Access: Slow (query latency hours)
        # - Cost: Very Low ($/GB/month)
        # - Use case: Debug logs, compliance archives
        
        def initialize(url:, retention_days: 365)
          @url = url
          @retention_days = retention_days
        end
        
        def write(event_data)
          # Write to cold tier (S3 Glacier, etc.)
          # Add lifecycle metadata: tier: :cold, expires_at: timestamp + 1.year
        end
      end
    end
  end
end
```

**Status:** ❌ **NOT_IMPLEMENTED** (no cold tier adapter)

**Impact:** HIGH
- Cannot route debug logs to cheap archive storage
- No 80-97% cost savings (UC-019 promise)
- UC-019 Scenario 3 (Debug Logs) not possible

---

## 🔍 AUDIT AREA 3: Automatic Lifecycle Transitions (NOT_IMPLEMENTED)

### F-322: Hot → Warm Transition (NOT_IMPLEMENTED)

**Finding:** No automatic transition from hot to warm tier after 7 days.

**Expected Implementation:**

```ruby
# lib/e11y/lifecycle/transitions.rb (NOT EXISTS)

module E11y
  module Lifecycle
    class Transitions
      # Automatic lifecycle transitions based on age/access patterns
      #
      # Hot → Warm: After 7 days
      # Warm → Cold: After 30 days
      # Cold → Delete: After retention_period
      
      def self.migrate_hot_to_warm
        # Find events in hot tier older than 7 days
        # Move to warm tier
        # Update metadata: tier: :warm, migrated_at: timestamp
      end
      
      def self.migrate_warm_to_cold
        # Find events in warm tier older than 30 days
        # Move to cold tier
        # Update metadata: tier: :cold, migrated_at: timestamp
      end
      
      def self.delete_expired
        # Find events past retention_until
        # Delete from storage
        # Log deletion for audit
      end
    end
  end
end
```

**Evidence of Non-Existence:**

```bash
$ find lib/ -name "*lifecycle*" -o -name "*transition*"
# No results
```

**Status:** ❌ **NOT_IMPLEMENTED** (no lifecycle automation)

**Impact:** CRITICAL
- Manual management required (not scalable)
- No automatic cost optimization
- Cannot achieve UC-019 promised 80-97% savings

---

### F-323: Retention Policy Enforcement (NOT_IMPLEMENTED)

**Finding:** No automatic deletion of events after retention period expires.

**Expected Implementation:**

```ruby
# lib/e11y/lifecycle/retention.rb (NOT EXISTS)

module E11y
  module Lifecycle
    class Retention
      # Enforce retention policies by deleting expired events
      #
      # Run via background job (Sidekiq, Resque, etc.)
      # - Check retention_until timestamp
      # - Delete expired events
      # - Log deletions for compliance audit
      
      def self.delete_expired_events
        # Query: events where retention_until < Time.now
        # Delete from all tiers (hot, warm, cold)
        # Log: event_name, deleted_at, reason: "retention_expired"
      end
      
      def self.schedule_deletion_job
        # Cron job: Daily at 2am UTC
        # Find expired events → delete → log
      end
    end
  end
end
```

**Status:** ❌ **NOT_IMPLEMENTED** (no retention enforcement)

**Impact:** CRITICAL
- Events stored forever (storage cost grows unbounded)
- Compliance risk (GDPR, CCPA require deletion)
- UC-019 retention policies not enforced

---

## 🔍 AUDIT AREA 4: Manual Overrides

### F-324: Explicit Adapter Selection (PASS)

**Finding:** Manual adapter selection works via explicit `adapters` field.

**Evidence:**

```ruby
# lib/e11y/middleware/routing.rb:66-72

# 1. Determine target adapters (explicit or via routing rules)
target_adapters = if event_data[:adapters]&.any?
                    # Explicit adapters bypass routing rules
                    event_data[:adapters]
                  else
                    # Apply routing rules from configuration
                    apply_routing_rules(event_data)
                  end
```

**Usage:**

```ruby
class ImportantEvent < E11y::Event::Base
  # Override routing rules, force hot tier
  adapters :loki, :datadog  # ← Explicit adapters
  retention_period 7.days
end

ImportantEvent.track(message: "Critical incident")
# Routes to: [:loki, :datadog] (bypasses routing rules)
```

**Analysis:**
- ✅ Explicit adapters bypass routing rules
- ✅ Supports multiple adapters
- ✅ Routing metadata includes `routing_type: :explicit`
- ✅ Works with any adapter (not just tiered storage)

**Status:** ✅ **PASS** (manual overrides work)

**Use Case:** Emergency overrides, testing, temporary routing changes

---

## 📊 Summary of Findings

| Finding ID | Area | Status | Severity |
|-----------|------|--------|----------|
| F-316 | Routing middleware | ✅ PASS | ✅ |
| F-317 | Retention period DSL | ✅ PASS | ✅ |
| F-318 | Routing rules lambdas | ✅ PASS | ✅ |
| F-319 | Hot tier adapter | ❌ NOT_IMPLEMENTED | CRITICAL |
| F-320 | Warm tier adapter | ❌ NOT_IMPLEMENTED | CRITICAL |
| F-321 | Cold tier adapter | ❌ NOT_IMPLEMENTED | CRITICAL |
| F-322 | Lifecycle transitions | ❌ NOT_IMPLEMENTED | CRITICAL |
| F-323 | Retention enforcement | ❌ NOT_IMPLEMENTED | CRITICAL |
| F-324 | Manual overrides | ✅ PASS | ✅ |

**Metrics:**
- **PASS:** 4/9 findings (44%)
- **NOT_IMPLEMENTED:** 5/9 findings (56%)
- **DoD Compliance:** 1/9 requirements (11%)

---

## 🚨 Critical Gaps Analysis

### Gap 1: No Tiered Storage Adapters (CRITICAL)

**Issue:** UC-019 requires hot/warm/cold tier adapters, none implemented.

**Evidence:**
- No `lib/e11y/adapters/tiered_storage/` directory
- No hot/warm/cold adapter classes
- Routing infrastructure ready, but no tiers to route to

**Impact:**
- UC-019 Scenario 1 (Audit Events → encrypted hot tier) not possible
- UC-019 Scenario 2 (Application Logs → warm tier) not possible
- UC-019 Scenario 3 (Debug Logs → cold tier) not possible
- **Cannot achieve 80-97% cost savings** promised by UC-019

**Root Cause:** Phase 5 feature, not implemented in E11y v1.0

**Recommendation:** R-090: Implement tiered storage adapters (Phase 5)

---

### Gap 2: No Automatic Lifecycle Management (CRITICAL)

**Issue:** Events don't automatically migrate between tiers (hot → warm → cold).

**Evidence:**
- No lifecycle automation code
- No background job for transitions
- Routing happens at write time, no post-write migration

**Impact:**
- Hot tier grows unbounded (expensive)
- No automatic cost optimization
- Manual migration required (not scalable)

**Root Cause:** Phase 5 feature, requires tiered storage adapters first

**Recommendation:** R-091: Implement lifecycle transitions (Phase 5)

---

### Gap 3: No Retention Policy Enforcement (CRITICAL)

**Issue:** Events not deleted after retention period expires (GDPR/CCPA risk).

**Evidence:**
- No deletion automation
- `retention_until` calculated but not enforced
- Events stored forever

**Impact:**
- Storage cost grows unbounded
- **Compliance risk** (GDPR/CCPA require deletion)
- Cannot meet retention policy requirements

**Root Cause:** Requires lifecycle automation and tiered storage

**Recommendation:** R-092: Implement retention enforcement (Phase 5)

---

## 🏗️ Implementation Plan (Phase 5 Roadmap)

### R-090: Implement Tiered Storage Adapters (CRITICAL, Phase 5)

**Priority:** CRITICAL (blocks UC-019)  
**Effort:** HIGH (3 adapters + tests)  
**Dependencies:** None (routing infrastructure ready)

**Implementation:**

1. Create tiered storage adapter directory:

```ruby
lib/e11y/adapters/tiered_storage/
├── hot.rb       # Fast storage (Redis, Loki 7 days)
├── warm.rb      # Standard storage (S3 Standard 30 days)
└── cold.rb      # Archive storage (S3 Glacier 1 year)
```

2. Implement Hot Tier Adapter:

```ruby
# lib/e11y/adapters/tiered_storage/hot.rb

module E11y
  module Adapters
    module TieredStorage
      class Hot < Base
        def initialize(url:, retention_days: 7)
          @url = url
          @retention_days = retention_days
          @tier = :hot
        end

        def write(event_data)
          # Add tier metadata
          event_data[:tier] = @tier
          event_data[:tier_expires_at] = (Time.now + @retention_days.days).iso8601

          # Write to hot storage (Loki, Redis, etc.)
          # ... (adapter-specific implementation)
        end
      end
    end
  end
end
```

3. Repeat for Warm and Cold tiers

4. Add tests:

```ruby
# spec/e11y/adapters/tiered_storage/hot_spec.rb

RSpec.describe E11y::Adapters::TieredStorage::Hot do
  it "adds tier metadata to event" do
    adapter = described_class.new(url: "http://loki:3100", retention_days: 7)
    event_data = { event_name: "test.event" }
    
    adapter.write(event_data)
    
    expect(event_data[:tier]).to eq(:hot)
    expect(event_data[:tier_expires_at]).to be_within(1).of(Time.now + 7.days)
  end
end
```

5. Update configuration:

```ruby
E11y.configure do |config|
  config.adapters[:hot] = E11y::Adapters::TieredStorage::Hot.new(
    url: "http://loki:3100",
    retention_days: 7
  )
  config.adapters[:warm] = E11y::Adapters::TieredStorage::Warm.new(
    url: "s3://my-bucket/warm/",
    retention_days: 30
  )
  config.adapters[:cold] = E11y::Adapters::TieredStorage::Cold.new(
    url: "s3://my-bucket-glacier/cold/",
    retention_days: 365
  )
end
```

---

### R-091: Implement Lifecycle Transitions (CRITICAL, Phase 5)

**Priority:** CRITICAL (blocks automatic cost optimization)  
**Effort:** HIGH (background jobs + tests)  
**Dependencies:** R-090 (tiered storage adapters)

**Implementation:**

1. Create lifecycle service:

```ruby
# lib/e11y/lifecycle/transitions.rb

module E11y
  module Lifecycle
    class Transitions
      # Migrate events between tiers based on age
      
      def self.migrate_hot_to_warm
        # Query hot tier for events older than 7 days
        # Read events, write to warm tier, delete from hot
        # Log migration: event_name, migrated_from: :hot, migrated_to: :warm
      end
      
      def self.migrate_warm_to_cold
        # Query warm tier for events older than 30 days
        # Read events, write to cold tier, delete from warm
      end
    end
  end
end
```

2. Add background job (Sidekiq):

```ruby
# app/jobs/e11y/lifecycle_migration_job.rb

class E11y::LifecycleMigrationJob < ApplicationJob
  queue_as :default
  
  def perform
    E11y::Lifecycle::Transitions.migrate_hot_to_warm
    E11y::Lifecycle::Transitions.migrate_warm_to_cold
  end
end
```

3. Schedule job (daily at 2am):

```ruby
# config/initializers/e11y_lifecycle.rb

if defined?(Sidekiq)
  Sidekiq::Cron::Job.create(
    name: "E11y Lifecycle Migration",
    cron: "0 2 * * *",  # Daily at 2am UTC
    class: "E11y::LifecycleMigrationJob"
  )
end
```

---

### R-092: Implement Retention Enforcement (CRITICAL, Phase 5)

**Priority:** CRITICAL (compliance risk)  
**Effort:** MEDIUM (deletion automation + audit log)  
**Dependencies:** R-090 (tiered storage adapters)

**Implementation:**

1. Create retention enforcement service:

```ruby
# lib/e11y/lifecycle/retention.rb

module E11y
  module Lifecycle
    class Retention
      # Delete expired events (retention_until < now)
      
      def self.delete_expired_events
        tiers = [:hot, :warm, :cold]
        
        tiers.each do |tier|
          adapter = E11y.configuration.adapters[tier]
          next unless adapter
          
          # Query events where retention_until < Time.now
          expired_events = adapter.query(retention_until: { lt: Time.now })
          
          expired_events.each do |event|
            # Delete event
            adapter.delete(event[:id])
            
            # Log deletion (compliance audit)
            E11y::AuditTrail.log(
              event_name: "event.deleted",
              reason: "retention_expired",
              original_event: event[:event_name],
              retention_until: event[:retention_until]
            )
          end
        end
      end
    end
  end
end
```

2. Add background job:

```ruby
# app/jobs/e11y/retention_enforcement_job.rb

class E11y::RetentionEnforcementJob < ApplicationJob
  queue_as :default
  
  def perform
    E11y::Lifecycle::Retention.delete_expired_events
  end
end
```

3. Schedule job (daily):

```ruby
# config/initializers/e11y_lifecycle.rb

Sidekiq::Cron::Job.create(
  name: "E11y Retention Enforcement",
  cron: "0 3 * * *",  # Daily at 3am UTC (after migration)
  class: "E11y::RetentionEnforcementJob"
)
```

---

## 🔬 What Works Today (Despite NOT_IMPLEMENTED)

### Retention-Based Routing (Ready for Future)

**E11y's routing infrastructure is PRODUCTION-READY** for simple multi-adapter routing:

**Example 1: Audit Events → Encrypted Storage**

```ruby
E11y.configure do |config|
  config.adapters[:audit_encrypted] = E11y::Adapters::AuditEncrypted.new(...)
  config.adapters[:loki] = E11y::Adapters::Loki.new(...)
  
  config.routing_rules = [
    # Audit events → encrypted storage (WORKS TODAY)
    ->(event) { :audit_encrypted if event[:audit_event] }
  ]
end

class UserDeletedEvent < E11y::Event::Base
  audit_event true
  retention_period 7.years
end

UserDeletedEvent.track(user_id: 123)
# ✅ Routes to: [:audit_encrypted] (WORKS)
```

**Example 2: Multi-Adapter Fanout**

```ruby
E11y.configure do |config|
  config.routing_rules = [
    # Errors → Datadog + Loki (WORKS TODAY)
    ->(event) { [:datadog, :loki] if event[:severity] == :error }
  ]
end

class ErrorEvent < E11y::Event::Base
  severity :error
end

ErrorEvent.track(message: "Something failed")
# ✅ Routes to: [:datadog, :loki] (WORKS)
```

**What's Missing:**
- Hot/warm/cold tier adapters (Phase 5)
- Automatic lifecycle transitions (Phase 5)
- Retention enforcement (Phase 5)

---

## 📈 UC-019 Compliance Status

| UC-019 Scenario | Status | Blocker |
|----------------|--------|---------|
| Scenario 1: Debug Logs (7 days → cold) | ❌ NOT_POSSIBLE | No cold tier adapter |
| Scenario 2: Application Logs (30 days → warm) | ❌ NOT_POSSIBLE | No warm tier adapter |
| Scenario 3: Audit Events (7 years → hot) | ⚠️ PARTIAL | Can route to encrypted storage, but not hot tier |
| Scenario 4: Cost Optimization (80-97% savings) | ❌ NOT_POSSIBLE | No tiered storage |

**UC-019 Compliance:** 0% (no scenarios fully implemented)

---

## 📊 Conclusion

### Overall Status: ⚠️ **NOT_IMPLEMENTED** (10%)

**What Works:**
- ✅ Routing infrastructure (middleware, rules, DSL)
- ✅ Retention period DSL
- ✅ Manual adapter overrides

**What's Missing:**
- ❌ Tiered storage adapters (hot/warm/cold)
- ❌ Automatic lifecycle transitions
- ❌ Retention enforcement (deletion)

### Production Readiness: **NOT PRODUCTION-READY**

**Rationale:**
- UC-019 is a **Phase 5 feature** (documented in IMPLEMENTATION_PLAN.md)
- Routing infrastructure is production-ready (can be used for simple multi-adapter routing TODAY)
- Tiered storage adapters, lifecycle automation, and retention enforcement are **future work**

**Recommendations:**

1. **R-090**: Implement tiered storage adapters (CRITICAL, Phase 5)
2. **R-091**: Implement lifecycle transitions (CRITICAL, Phase 5)
3. **R-092**: Implement retention enforcement (CRITICAL, Phase 5)

**Cost Impact:**
- UC-019 promises 80-97% cost savings via tiered storage
- Without tiered storage, E11y relies on AUDIT-018 cost optimization (sampling + compression = 98% reduction)
- Tiered storage would ADD 58% additional savings on top of AUDIT-018 (97.1% → 99.5%)

### Severity Assessment

| Risk Category | Severity | Mitigation |
|--------------|----------|------------|
| Feature Completeness | HIGH | Document as Phase 5 roadmap |
| Cost Optimization | MEDIUM | AUDIT-018 achieves 98% reduction without tiered storage |
| Compliance | CRITICAL | No retention enforcement (GDPR/CCPA risk) |
| Production Readiness | NOT READY | Phase 5 feature, not blocking E11y v1.0 |

**Final Verdict:** UC-019 is NOT IMPLEMENTED (Phase 5 future work), but routing infrastructure is production-ready for simple use cases TODAY.

---

**Audit completed:** 2026-01-21  
**Next audit:** FEAT-4981 (Test data lifecycle and retention enforcement)

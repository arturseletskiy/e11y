# TRIZ Contradiction #1: Configuration Complexity

**Created:** 2026-01-15  
**Priority:** 🔴 CRITICAL (Main User Goal)  
**Domain:** Configuration Simplification

---

## 📋 Technical Contradiction

### Improving Parameter vs. Worsening Parameter

**Want to improve:** Configuration simplicity (reduce from 1400+ lines to <300 lines)  
**But this worsens:** Feature completeness (all 22 UCs must work)

**TRIZ Matrix:**
- **Improving:** #36 - Complexity of device (configuration)
- **Worsening:** #37 - Difficulty of measuring (feature coverage)
- **Suggested Principles:** #1 Segmentation, #17 Moving to new dimension, #34 Rejecting and Regenerating Parts

---

## 🎯 Ideal Final Result (IFR)

**IFR Statement:**
"Configuration defines itself automatically based on event class declarations, providing full functionality with <300 lines of global config, while maintaining explicitness over implicitness."

**IFR Decomposition:**
1. **Event-level configuration** defines most settings (schema, severity, adapters, PII rules)
2. **Global configuration** only defines infrastructure (adapter instances, global limits)
3. **Sensible defaults** eliminate 80% of repetitive config
4. **DSL shortcuts** reduce verbosity (e.g., `masks :email` vs. verbose field block)
5. **Auto-registration** eliminates boilerplate (adapters, middlewares)

---

## 🔍 Available Resources

### 1. Event-Level DSL (Already Exists!)
```ruby
class Events::OrderPaid < E11y::Event::Base
  schema do; required(:order_id).filled(:string); end
  severity :success
  adapters [:loki, :sentry]  # ← Reference by name
  version 1
end
```

**Current state:** Event-level DSL for schema, severity, adapters, version (from UC-002 analysis).

**Unused potential:** Could also define PII rules, rate limits, sampling rates, retention at event level.

### 2. Global Adapter Registry (Already Exists!)
```ruby
E11y.configure do |config|
  config.register_adapter :loki, E11y::Adapters::Loki.new(url: ENV['LOKI_URL'])
end
```

**Current state:** Register once, reference everywhere (DRY).

**Problem:** All events using `:loki` share same config (ADR-004 Contradiction #1).

### 3. Rails-Style DSL Shortcuts (Partially Exists)
```ruby
class Events::UserRegistered < E11y::Event::Base
  masks :email, :password  # ← DSL shortcut
  # vs. verbose:
  # pii_filtering do
  #   field :email do; strategy :mask; end
  # end
end
```

**Current state:** Exists for PII filtering (UC-007).

**Unused potential:** Could extend to rate limits, sampling, adapters.

### 4. Convention Over Configuration (Underutilized!)
```ruby
# Convention: Events with :error severity auto-send to Sentry
# No need to declare adapters [:sentry] explicitly!
class Events::PaymentFailed < E11y::Event::Base
  severity :error  # ← Auto-routes to Sentry (convention!)
end
```

**Current state:** Partially used (default_adapters).

**Unused potential:** More conventions (severity → adapters, event pattern → metrics, etc.).

### 5. Inheritance & Modules (Not Fully Utilized!)
```ruby
module PiiAwareEvent
  extend ActiveSupport::Concern
  included do
    contains_pii true
    pii_filtering do
      masks :email, :phone
      hashes :user_id
    end
  end
end

class Events::UserRegistered < E11y::Event::Base
  include PiiAwareEvent  # ← Inherit common PII config!
end
```

**Current state:** Not described in any ADR or UC.

**Unused potential:** Modules for common patterns (PiiAwareEvent, AuditableEvent, HighValueEvent).

---

## 💡 TRIZ Solutions (5+)

### Solution 1: **Segmentation (TRIZ #1)** - Event-Level Configuration
**Principle:** Divide complex global config into many small event-level configs.

**Implementation:**
```ruby
# BEFORE (1400+ lines global config):
E11y.configure do |config|
  config.rate_limiting do
    per_event 'order.paid', limit: 1000
    per_event 'user.login', limit: 500
    per_event 'payment.failed', limit: 100
  end
  
  config.sampling do
    sample_rate_for 'debug.*', 0.01
    sample_rate_for 'success.*', 0.1
    sample_rate_for 'error.*', 1.0
  end
  
  # ... 1400 more lines
end

# AFTER (<300 lines global + event-level):
# Global (infrastructure only, ~100 lines):
E11y.configure do |config|
  config.register_adapter :loki, Loki.new(url: ENV['LOKI_URL'])
  config.register_adapter :sentry, Sentry.new(dsn: ENV['SENTRY_DSN'])
  config.default_adapters = [:loki]  # Global default
end

# Event-level (distributed across event classes):
class Events::OrderPaid < E11y::Event::Base
  schema do; required(:order_id).filled(:string); end
  severity :success
  
  # Event-specific config (right next to schema!):
  rate_limit 1000, window: 1.second
  sample_rate 0.1  # 10% sampling
  retention 7.years  # Compliance
end

class Events::DebugQuery < E11y::Event::Base
  severity :debug
  rate_limit 100
  sample_rate 0.01  # 1% sampling
  retention 7.days  # Short retention
  adapters [:file]  # Override: local file only (no Loki)
end
```

**Benefits:**
- ✅ Configuration next to schema (locality of behavior)
- ✅ Event-specific tuning (different limits per event)
- ✅ Global config reduced to infrastructure (~100 lines)
- ✅ Easier to find/change (event config in event class, not buried in initializer)

**Trade-offs:**
- ⚠️ Configuration scattered across many files (vs. single place)
- ⚠️ Harder to see global picture (need to read many event classes)

**Evaluation:** ⭐⭐⭐⭐⭐ (5/5) - **RECOMMENDED** - Aligns with user goal "спустить настройки на уровень events"

---

### Solution 2: **Nested Doll (TRIZ #7)** - Preset Configurations
**Principle:** Use presets (nested templates) to reduce repetitive config.

**Implementation:**
```ruby
# Presets for common patterns:
module E11y
  module Presets
    module HighValueEvent
      extend ActiveSupport::Concern
      included do
        rate_limit 10_000  # High limit
        sample_rate 1.0  # Never sample (100%)
        retention 7.years  # Long retention
        adapters [:loki, :sentry, :s3_archive]  # All destinations
      end
    end
    
    module DebugEvent
      extend ActiveSupport::Concern
      included do
        severity :debug
        rate_limit 100  # Low limit
        sample_rate 0.01  # 1% sampling
        retention 7.days  # Short retention
        adapters [:file]  # Local only
      end
    end
    
    module AuditEvent
      extend ActiveSupport::Concern
      included do
        audit_event true  # Trigger audit pipeline
        adapters [:audit_encrypted]  # Encrypted storage
        retention 7.years  # Legal requirement
        rate_limiting false  # No limits for audit
        sampling false  # No sampling for audit
      end
    end
  end
end

# Usage (1 line includes preset!):
class Events::PaymentProcessed < E11y::Event::Base
  include E11y::Presets::HighValueEvent  # ← All config inherited!
  schema do; required(:amount).filled(:decimal); end
end

class Events::DebugSqlQuery < E11y::Event::Base
  include E11y::Presets::DebugEvent  # ← All config inherited!
  schema do; required(:query).filled(:string); end
end
```

**Benefits:**
- ✅ 1-line config for common patterns (preset)
- ✅ DRY (define once, reuse)
- ✅ Override possible (preset + custom)
- ✅ Clear naming (HighValueEvent, DebugEvent, AuditEvent)

**Trade-offs:**
- ⚠️ Need to define presets upfront (initial effort)
- ⚠️ Preset proliferation if too many variations

**Evaluation:** ⭐⭐⭐⭐ (4/5) - **HIGHLY RECOMMENDED** - Complements Solution 1

---

### Solution 3: **Prior Action (TRIZ #10)** - Sensible Defaults
**Principle:** Perform required action in advance (defaults eliminate config).

**Implementation:**
```ruby
# BEFORE (explicit config required):
class Events::OrderPaid < E11y::Event::Base
  severity :success
  adapters [:loki, :sentry]  # Must declare!
  sample_rate 0.1
  rate_limit 1000
end

# AFTER (sensible defaults):
class Events::OrderPaid < E11y::Event::Base
  # Defaults applied automatically:
  # - severity: inferred from event name (.*Paid → :success, .*Failed → :error)
  # - adapters: :error/:fatal → [:sentry], others → [:loki] (convention!)
  # - sample_rate: :success → 0.1, :error → 1.0 (by severity)
  # - rate_limit: 1000 (global default for all events)
  
  schema do; required(:order_id).filled(:string); end
  # ← ONLY SCHEMA REQUIRED! (zero config for standard events)
end

# Override only when needed:
class Events::CriticalError < E11y::Event::Base
  severity :fatal  # ← Explicit (unusual case)
  adapters [:sentry, :pagerduty]  # ← Override (unusual case)
end
```

**Conventions to apply:**
1. **Severity from event name:**
   - `*Failed`, `*Error` → :error
   - `*Paid`, `*Succeeded`, `*Completed` → :success
   - `*Started`, `*Processing` → :info
   - `Debug*` → :debug
2. **Adapters from severity:**
   - :error/:fatal → [:sentry]
   - :success/:info/:warn → [:loki]
   - :debug → [:file] (dev), [:loki] (prod with sampling)
3. **Sample rate from severity:**
   - :error/:fatal → 1.0 (100%)
   - :warn → 0.5 (50%)
   - :success/:info → 0.1 (10%)
   - :debug → 0.01 (1%)
4. **Rate limit:** 1000/sec default (override only for high-volume)
5. **Retention from severity:**
   - :error/:fatal → 90 days
   - :info/:success → 30 days
   - :debug → 7 days

**Benefits:**
- ✅ Zero config for 90% of events (only schema!)
- ✅ Explicit over implicit (conventions clear, not magic)
- ✅ Override when needed (escape hatch)

**Trade-offs:**
- ⚠️ Conventions must be learned (documentation burden)
- ⚠️ May not fit all use cases (edge cases need override)

**Evaluation:** ⭐⭐⭐⭐⭐ (5/5) - **RECOMMENDED** - "Explicit better than implicit" + conventions = best balance

---

### Solution 4: **Dynamism (TRIZ #15)** - Adaptive Configuration
**Principle:** Configuration adapts to environment automatically.

**Implementation:**
```ruby
# BEFORE (explicit per-environment config):
# config/environments/development.rb
E11y.configure do |config|
  config.adapters = [:console]
  config.sampling_rate = 1.0  # 100% in dev
end

# config/environments/production.rb
E11y.configure do |config|
  config.adapters = [:loki, :sentry]
  config.sampling_rate = 0.1  # 10% in prod
end

# AFTER (adaptive):
# config/initializers/e11y.rb (ONE FILE for all environments!)
E11y.configure do |config|
  # Auto-detect environment and adapt:
  config.auto_configure_for_environment!
  # → Development: console adapter, 100% sampling, file storage
  # → Test: memory adapter, 100% sampling, fast flush
  # → Staging: loki adapter, 50% sampling
  # → Production: loki + sentry, 10% sampling, batching, compression
  
  # Override only if needed:
  if Rails.env.production?
    config.register_adapter :pagerduty, PagerDuty.new(key: ENV['PAGERDUTY_KEY'])
  end
end
```

**Benefits:**
- ✅ Single config file (not 4 environment files)
- ✅ Environment-aware defaults (90% cases covered)
- ✅ Override escape hatch (10% custom cases)

**Trade-offs:**
- ⚠️ "Magic" auto-configuration (less explicit)
- ⚠️ May not fit all use cases

**Evaluation:** ⭐⭐⭐ (3/5) - **OPTIONAL** - Helps but conflicts with "explicit > implicit" principle

---

### Solution 5: **Local Quality (TRIZ #3)** - Different Config Modes
**Principle:** Different parts of system have different config requirements.

**Implementation:**
```ruby
# Provide 3 config modes:

# MODE 1: Quick Start (zero config, all defaults)
E11y.quick_start!  # ← 1 line!
# → Registers default adapters (loki in prod, console in dev)
# → Applies sensible defaults
# → 90% use cases covered

# MODE 2: Standard (global config)
E11y.configure do |config|
  config.adapters.register :loki, Loki.new(url: ENV['LOKI_URL'])
  config.default_adapters = [:loki]
end
# + Event-level config (severity, schema)
# → 95% use cases covered, ~100-200 lines

# MODE 3: Advanced (full control)
E11y.configure do |config|
  # Full granular config for power users
  # All 1400+ lines if needed
end
```

**Benefits:**
- ✅ Progressive disclosure (simple → advanced)
- ✅ Quick start for beginners (<1 min setup)
- ✅ Full control for power users (escape to 1400+ lines if needed)

**Trade-offs:**
- ⚠️ 3 modes to document (complexity)
- ⚠️ Users may not know which mode to use

**Evaluation:** ⭐⭐⭐⭐ (4/5) - **RECOMMENDED** - Progressive complexity

---

### Solution 6: **Copying (TRIZ #26)** - Configuration Inheritance
**Principle:** Use inexpensive simplified copy instead of complex original.

**Implementation:**
```ruby
# Base event classes with common config:
module Events
  class BaseAuditEvent < E11y::Event::Base
    # Common audit config:
    audit_event true
    adapters [:audit_encrypted]
    retention 7.years
    contains_pii true  # Most audit events have PII
  end
  
  class BasePaymentEvent < E11y::Event::Base
    # Common payment config:
    severity :success
    rate_limit 1000
    sample_rate 1.0  # Never sample payments (high-value)
    retention 7.years  # Financial records
    adapters [:loki, :sentry, :s3_archive]
    
    pii_filtering do
      hashes :email, :user_id  # Common PII handling
    end
  end
end

# Inherit (1-2 lines per event!):
class Events::PermissionChanged < Events::BaseAuditEvent
  schema do
    required(:user_id).filled(:string)
    required(:old_role).filled(:string)
    required(:new_role).filled(:string)
  end
  # ← Inherits ALL audit config!
end

class Events::PaymentSucceeded < Events::BasePaymentEvent
  schema do
    required(:transaction_id).filled(:string)
    required(:amount).filled(:decimal)
  end
  # ← Inherits ALL payment config!
end
```

**Benefits:**
- ✅ 1-2 lines per event (just schema!)
- ✅ Common patterns shared (DRY)
- ✅ Override possible (inheritance + super)
- ✅ Explicit (base class name shows intent)

**Trade-offs:**
- ⚠️ Need to define base classes (upfront effort)
- ⚠️ Deep inheritance can be confusing

**Evaluation:** ⭐⭐⭐⭐⭐ (5/5) - **HIGHLY RECOMMENDED** - User mentioned "использовать наследование/модули для переопределения"

---

### Solution 7: **Parameter Changes (TRIZ #35)** - Aggregate Physical State
**Principle:** Change configuration from discrete steps to continuous/automatic.

**Implementation:**
```ruby
# BEFORE (discrete per-event config):
E11y.configure do |config|
  config.sampling do
    sample_rate_for 'event1', 0.1
    sample_rate_for 'event2', 0.1
    sample_rate_for 'event3', 0.1
    # ... 100 events with same rate!
  end
end

# AFTER (pattern-based aggregate config):
E11y.configure do |config|
  config.sampling do
    # Pattern-based (aggregate):
    sample_rate_for /^payment\..*/, 1.0  # All payments: 100%
    sample_rate_for /^debug\..*/, 0.01   # All debug: 1%
    sample_rate_for /^user\..*/, 0.1     # All user events: 10%
    
    # Severity-based (aggregate):
    sample_rate_by_severity do
      error: 1.0,  # 100%
      warn: 0.5,   # 50%
      info: 0.1,   # 10%
      debug: 0.01  # 1%
    end
    
    # Default:
    default_sample_rate 0.1  # 10% for everything else
  end
end
```

**Benefits:**
- ✅ 10 lines instead of 100 (pattern-based)
- ✅ Automatic coverage (new events auto-matched)
- ✅ Clear intent (pattern shows business logic)

**Trade-offs:**
- ⚠️ Less granular control (all payments same rate)
- ⚠️ Pattern matching overhead (<0.01ms per event)

**Evaluation:** ⭐⭐⭐⭐ (4/5) - **RECOMMENDED** - Already used for metrics (UC-003), extend to sampling/rate limiting

---

### Solution 8: **Self-Service (TRIZ #25)** - Auto-Registration
**Principle:** Object serves itself (auto-registration).

**Implementation:**
```ruby
# BEFORE (manual middleware registration):
E11y.configure do |config|
  config.pipeline.use E11y::Middleware::TraceContext
  config.pipeline.use E11y::Middleware::Validation
  config.pipeline.use E11y::Middleware::PiiFilter
  config.pipeline.use E11y::Middleware::RateLimit
  config.pipeline.use E11y::Middleware::Sampling
  config.pipeline.use E11y::Middleware::Versioning
  config.pipeline.use E11y::Middleware::Routing
end

# AFTER (auto-registration):
# config/initializers/e11y.rb
E11y.configure do |config|
  # ← NOTHING! Middlewares auto-register in correct order!
  # Use config.pipeline.disable :versioning to exclude (opt-out, not opt-in)
end

# lib/e11y/middleware/trace_context.rb
module E11y
  module Middleware
    class TraceContext < Base
      # Auto-register at position 1:
      register_middleware priority: 1, zone: :pre_processing
      
      def call(event_data)
        # ...
      end
    end
  end
end
```

**Benefits:**
- ✅ Zero middleware config (auto-registered)
- ✅ Correct order guaranteed (priority + zone)
- ✅ Opt-out model (disable if needed)

**Trade-offs:**
- ⚠️ Less explicit (middleware order not visible in config)
- ⚠️ Custom middleware harder to insert (must declare priority)

**Evaluation:** ⭐⭐⭐ (3/5) - **OPTIONAL** - Conflicts with user's "explicit > implicit" preference

---

## 📊 Solution Evaluation Matrix

| Solution | Complexity Reduction | Explicitness | Implementation Effort | User Goal Alignment | Final Score |
|----------|----------------------|--------------|----------------------|---------------------|-------------|
| **#1: Segmentation (Event-Level)** | ⭐⭐⭐⭐⭐ (70% reduction) | ⭐⭐⭐⭐ (explicit) | ⭐⭐⭐ (medium) | ⭐⭐⭐⭐⭐ (perfect) | **5.0/5.0** ✅ |
| **#2: Nested Doll (Presets)** | ⭐⭐⭐⭐ (50% reduction) | ⭐⭐⭐⭐ (explicit) | ⭐⭐⭐⭐ (low) | ⭐⭐⭐⭐ (great) | **4.0/5.0** ✅ |
| **#3: Prior Action (Defaults)** | ⭐⭐⭐⭐⭐ (80% reduction) | ⭐⭐⭐ (some magic) | ⭐⭐⭐⭐⭐ (low) | ⭐⭐⭐⭐ (good) | **4.2/5.0** ✅ |
| **#4: Dynamism (Adaptive)** | ⭐⭐⭐ (30% reduction) | ⭐⭐ (magic) | ⭐⭐⭐ (medium) | ⭐⭐ (conflicts) | **2.5/5.0** ⚠️ |
| **#5: Local Quality (Modes)** | ⭐⭐⭐⭐ (60% reduction) | ⭐⭐⭐⭐ (clear) | ⭐⭐⭐ (medium) | ⭐⭐⭐⭐ (good) | **3.8/5.0** ✅ |
| **#6: Copying (Inheritance)** | ⭐⭐⭐⭐⭐ (80% reduction) | ⭐⭐⭐⭐⭐ (very explicit) | ⭐⭐⭐ (medium) | ⭐⭐⭐⭐⭐ (user mentioned!) | **4.6/5.0** ✅ |
| **#7: Parameter Changes (Patterns)** | ⭐⭐⭐⭐ (50% reduction) | ⭐⭐⭐⭐ (explicit) | ⭐⭐⭐⭐ (low) | ⭐⭐⭐⭐ (good) | **4.0/5.0** ✅ |
| **#8: Self-Service (Auto-Reg)** | ⭐⭐⭐ (30% reduction) | ⭐⭐ (implicit) | ⭐⭐⭐⭐ (low) | ⭐⭐ (conflicts) | **2.8/5.0** ⚠️ |

---

## 🏆 Recommended Solution: **Combination Strategy**

### Primary Approaches (MUST HAVE)
1. **Event-Level Configuration (#1)** - Move config to event classes (schema, severity, adapters, rate limits, sampling)
2. **Inheritance & Modules (#6)** - Base classes for common patterns (BaseAuditEvent, BasePaymentEvent, BaseDebugEvent)
3. **Sensible Defaults (#3)** - 90% of events need ONLY schema (severity/adapters/sampling from conventions)

### Secondary Approaches (SHOULD HAVE)
4. **Preset Modules (#2)** - E11y::Presets::HighValueEvent for 1-line includes
5. **Pattern-Based Config (#7)** - Sampling/rate limiting by pattern (already exists for metrics)

### Optional (COULD HAVE)
6. **Quick Start Mode (#5)** - E11y.quick_start! for zero-config beginners

**Combined Effect:**
- Global config: ~50-100 lines (infrastructure: adapter instances, global defaults)
- Event classes: 5-10 lines each (schema + minimal config, or inherit from base)
- **Total: ~100 global + (22 events × 5 lines) = 210 lines** ✅ **<300 TARGET MET!**

---

## 🎯 Implementation Roadmap

### Phase 1: Event-Level DSL Extensions
- Add `rate_limit`, `sample_rate`, `retention` to Event::Base DSL
- Make all config inheritable (use class_attribute)
- Precedence: event-level > global config

### Phase 2: Sensible Defaults
- Implement severity conventions (.*Failed → :error, .*Paid → :success)
- Implement adapter conventions (:error → [:sentry], others → [:loki])
- Implement sampling conventions (by severity: error: 1.0, success: 0.1, debug: 0.01)

### Phase 3: Inheritance & Presets
- Create base event classes (BaseAuditEvent, BasePaymentEvent, BaseDebugEvent)
- Create preset modules (E11y::Presets::HighValueEvent, AuditEvent, DebugEvent)

### Phase 4: Pattern-Based Config
- Extend pattern matching to sampling (already exists for metrics)
- Extend pattern matching to rate limiting

**Estimated Effort:** 2-3 weeks implementation + testing

---

## 📈 Expected Results

### Before (Current State - from @docs/COMPREHENSIVE-CONFIGURATION.md)
- Global config: 1400+ lines
- Per-event config: 0 lines (all in global)
- **Total: 1400+ lines**
- **Problems:** Hard to navigate, repetitive, error-prone

### After (With TRIZ Solutions)
- Global config: ~50-100 lines (infrastructure only)
- Per-event config: ~5-10 lines each × 22 events = 110-220 lines
- **Total: ~160-320 lines** ✅ **Target <300 met!**
- **Benefits:**
  - ✅ Configuration locality (event config in event class)
  - ✅ Inheritance reduces duplication (base classes)
  - ✅ Defaults eliminate 80% of config (conventions)
  - ✅ Explicit over implicit (sensible defaults clearly documented)

---

**Status:** ✅ TRIZ Analysis Complete  
**Recommended:** Solutions #1, #6, #3 (event-level + inheritance + defaults)  
**Expected Reduction:** 78-82% (1400 → 250 lines average)  
**Next:** Apply similar TRIZ analysis to other contradictions

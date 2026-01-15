# E11y Configuration Hierarchy Design

**Created:** 2026-01-15  
**Based on:** TRIZ Solution #1 (Segmentation) + #6 (Inheritance) + #3 (Defaults)  
**Target:** <300 lines for common case (from 1400+ lines)  
**Expected Reduction:** 78-82%

---

## 📋 3-Level Configuration Hierarchy

### Level 1: Sensible Defaults (Built-In, Zero Config)
**Precedence:** Lowest  
**Purpose:** Cover 90% of common cases with zero configuration  
**Lines:** 0 (built into gem)

```ruby
# NO CONFIG NEEDED! Defaults applied automatically:

class Events::OrderPaid < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:decimal)
  end
  # ← ONLY SCHEMA! Everything else is default:
  # severity: :success (inferred from *Paid naming)
  # adapters: [:loki] (global default)
  # sample_rate: 0.1 (by severity: success → 10%)
  # rate_limit: 1000/sec (global default)
  # retention: 30 days (by severity: success → 30 days)
end
```

**Built-In Conventions:**
1. **Severity from event name:**
   - `*Failed`, `*Error` → :error
   - `*Paid`, `*Succeeded`, `*Completed` → :success
   - `*Started`, `*Processing` → :info
   - `Debug*` → :debug
2. **Adapters from severity:**
   - :error/:fatal → [:sentry] (errors to error tracker)
   - others → [:loki] (standard events to logs)
3. **Sample rate from severity:**
   - :error/:fatal → 1.0 (100%, never sample errors)
   - :warn → 0.5 (50%)
   - :success/:info → 0.1 (10%)
   - :debug → 0.01 (1%)
4. **Retention from severity:**
   - :error/:fatal → 90 days
   - :success/:info/:warn → 30 days
   - :debug → 7 days

---

### Level 2: Global Configuration (Initializer, ~50-100 Lines)
**Precedence:** Medium  
**Purpose:** Infrastructure setup (adapters, global limits, overrides to defaults)  
**Lines:** ~50-100 (one-time setup)

```ruby
# config/initializers/e11y.rb (~80 lines total)

E11y.configure do |config|
  # ===================================================================
  # ADAPTERS (Infrastructure) - ~30 lines
  # ===================================================================
  config.adapters do
    # Register adapters (created once, reused everywhere)
    register :loki, E11y::Adapters::Loki.new(
      url: ENV['LOKI_URL'] || 'http://localhost:3100'
    )
    
    register :sentry, E11y::Adapters::Sentry.new(
      dsn: ENV['SENTRY_DSN']
    )
    
    register :audit_encrypted, E11y::Adapters::AuditEncrypted.new(
      storage_path: Rails.root.join('log', 'audit'),
      encryption_key: ENV['AUDIT_ENCRYPTION_KEY']
    )
    
    # Default for most events (can override per-event)
    default_adapters [:loki]
  end
  
  # ===================================================================
  # GLOBAL LIMITS - ~20 lines
  # ===================================================================
  config.rate_limiting do
    global_limit 10_000  # events/sec (system-wide)
    default_event_limit 1000  # events/sec (per-event default)
    
    redis Redis.current  # Or nil for in-memory (dev)
  end
  
  config.buffering do
    adaptive do
      enabled true
      memory_limit_mb 100  # Hard memory limit
      backpressure_strategy :block  # Block when full (vs. :drop)
    end
  end
  
  # ===================================================================
  # DEFAULTS OVERRIDES (Optional) - ~30 lines
  # ===================================================================
  
  # Override conventions if needed:
  config.defaults do
    # Severity → Adapters mapping (override convention)
    adapters_for_severity do
      error [:sentry, :loki]  # Errors to both (not just Sentry)
      fatal [:sentry, :pagerduty, :loki]  # Fatal to all
    end
    
    # Sample rates (override convention)
    sample_rate_for_severity do
      success 0.05  # 5% instead of 10% (reduce costs)
    end
    
    # Retention (override convention)
    retention_for_severity do
      error 180.days  # 180 days instead of 90 days
    end
  end
end
```

---

### Level 3: Event-Level Configuration (Event Class DSL, ~5-10 Lines per Event)
**Precedence:** Highest (overrides Level 1 & 2)  
**Purpose:** Event-specific tuning when defaults don't fit  
**Lines:** ~5-10 per event × 22 events = 110-220 lines

#### Option A: Explicit Event-Level Config (when defaults don't fit)

```ruby
# app/events/payment_failed.rb
class Events::PaymentFailed < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:decimal)
    required(:error_code).filled(:string)
  end
  
  # Event-specific overrides:
  severity :error  # Explicit (not inferred from name)
  adapters [:sentry, :loki, :slack]  # Override: add Slack
  sample_rate 1.0  # 100% (high-value events, never sample)
  rate_limit 5000  # Higher limit than default 1000
  retention 1.year  # Longer than default 90 days
end
```

**Lines per event:** ~10 lines (schema + 5 overrides)

#### Option B: Inheritance (Base Classes for Common Patterns)

```ruby
# lib/e11y/presets/base_audit_event.rb
module Events
  class BaseAuditEvent < E11y::Event::Base
    # Common audit configuration:
    audit_event true
    adapters [:audit_encrypted]
    retention 7.years
    rate_limiting false  # No limits for audit
    sampling false  # No sampling for audit
    
    contains_pii true  # Most audit events have PII
    pii_filtering do
      # Default: skip filtering for audit (signature on original)
      skip_filtering true
    end
  end
end

# app/events/permission_changed.rb
class Events::PermissionChanged < Events::BaseAuditEvent
  schema do
    required(:user_id).filled(:string)
    required(:old_role).filled(:string)
    required(:new_role).filled(:string)
    required(:changed_by).filled(:string)
  end
  # ← Inherits ALL audit config! (JUST SCHEMA!)
end
```

**Lines per event:** ~5 lines (just schema, config inherited)

#### Option C: Preset Modules (Mix-In Common Patterns)

```ruby
# lib/e11y/presets.rb
module E11y
  module Presets
    module HighValueEvent
      extend ActiveSupport::Concern
      included do
        sample_rate 1.0  # Never sample
        retention 7.years  # Long retention
        adapters [:loki, :sentry, :s3_archive]  # All destinations
      end
    end
    
    module DebugEvent
      extend ActiveSupport::Concern
      included do
        severity :debug
        sample_rate 0.01  # 1% sampling
        retention 7.days  # Short retention
        adapters [:file]  # Local only (no expensive Loki)
      end
    end
  end
end

# app/events/payment_processed.rb
class Events::PaymentProcessed < E11y::Event::Base
  include E11y::Presets::HighValueEvent  # ← 1-line config!
  
  schema do
    required(:transaction_id).filled(:string)
    required(:amount).filled(:decimal)
  end
end
```

**Lines per event:** ~6 lines (include + schema)

---

## 🎯 Precedence Rules (Explicit Order)

**Configuration precedence (highest to lowest):**

```ruby
1. Per-track runtime override (highest)
   Events::OrderPaid.track(order_id: '123', _adapters: [:sentry])
   
2. Event class DSL (explicit event-level config)
   class Events::OrderPaid < E11y::Event::Base
     adapters [:loki, :sentry]  # ← Event-level
   end
   
3. Preset module (if included)
   include E11y::Presets::HighValueEvent
   
4. Base class (if inherited)
   class Events::PaymentFailed < Events::BasePaymentEvent
   
5. Global config (initializer overrides)
   config.defaults.sample_rate_for_severity do
     success 0.05  # Override convention
   end
   
6. Built-in conventions (lowest)
   # Severity from event name: *Paid → :success
```

**Resolution Logic:**
```ruby
# Example: Events::OrderPaid.track(order_id: '123', _adapters: [:sentry])

final_adapters = runtime_override[:_adapters] ||  # 1. Runtime
                 event_class.adapters ||          # 2. Event DSL
                 preset_module.adapters ||        # 3. Preset
                 base_class.adapters ||           # 4. Base class
                 global_config.adapters_for_severity(event.severity) ||  # 5. Global
                 convention_adapters(event.severity)  # 6. Convention
```

---

## 🔧 DSL Syntax Design

### Event Class DSL Methods

```ruby
class E11y::Event::Base
  # Configuration DSL (class methods):
  
  # Basic:
  def self.schema(&block)  # Dry::Schema validation (required!)
  def self.severity(value)  # :debug, :info, :success, :warn, :error, :fatal
  def self.version(value)  # Integer (for schema evolution)
  
  # Adapters:
  def self.adapters(list)  # Array of symbols (reference by name)
  def self.adapters_strategy(strategy)  # :replace (default) or :append (add to defaults)
  
  # Sampling:
  def self.sample_rate(rate)  # 0.0-1.0 (override default)
  def self.always_sample  # Shortcut for sample_rate 1.0
  def self.never_sample  # Shortcut for sample_rate 0.0
  
  # Rate Limiting:
  def self.rate_limit(limit, window: 1.second)  # events/window
  def self.no_rate_limiting  # Shortcut (disable rate limiting)
  
  # Retention:
  def self.retention(duration)  # 7.days, 30.days, 7.years
  
  # PII Filtering:
  def self.contains_pii(boolean)  # Tier 1 (false) or Tier 3 (true)
  def self.pii_filtering(&block)  # Per-field strategies
  def self.masks(*fields)  # DSL shortcut
  def self.hashes(*fields)  # DSL shortcut
  def self.allows(*fields)  # DSL shortcut
  
  # Audit:
  def self.audit_event(boolean)  # Trigger audit pipeline (C01)
  
  # Flags:
  def self.skip_validation  # Disable schema validation
  def self.skip_buffering  # Send immediately (bypass buffer)
end
```

---

## 🏗️ Ruby Implementation Strategy

### Step 1: Class-Level Config Storage

```ruby
module E11y
  class Event
    class Base
      class << self
        # Config storage (inherited, can be overridden)
        class_attribute :_severity, default: nil
        class_attribute :_adapters, default: nil
        class_attribute :_sample_rate, default: nil
        class_attribute :_rate_limit, default: nil
        class_attribute :_retention, default: nil
        class_attribute :_contains_pii, default: nil
        # ... etc.
        
        # DSL methods:
        def severity(value = nil)
          return resolve_severity if value.nil?  # Getter
          self._severity = value  # Setter
        end
        
        def adapters(list = nil)
          return resolve_adapters if list.nil?  # Getter
          self._adapters = list  # Setter
        end
        
        # ... other DSL methods
        
        private
        
        # Resolution with precedence:
        def resolve_severity
          _severity ||                          # 2. Event DSL (explicit)
            resolve_from_preset(:severity) ||   # 3. Preset module
            resolve_from_base_class(:severity) ||  # 4. Base class
            global_config.severity_for_event(self) ||  # 5. Global override
            infer_severity_from_name ||         # 6. Convention
            :info  # Ultimate fallback
        end
        
        def infer_severity_from_name
          case name
          when /Failed$/, /Error$/i then :error
          when /Paid$/, /Succeeded$/, /Completed$/ then :success
          when /Started$/, /Processing$/ then :info
          when /^Debug/ then :debug
          else nil
          end
        end
        
        def resolve_from_preset(attr)
          # Check if any included module defines this attribute
          included_modules.each do |mod|
            if mod.respond_to?("_#{attr}")
              return mod.public_send("_#{attr}")
            end
          end
          nil
        end
      end
    end
  end
end
```

### Step 2: Preset Modules

```ruby
# lib/e11y/presets.rb
module E11y
  module Presets
    module HighValueEvent
      extend ActiveSupport::Concern
      
      included do
        sample_rate 1.0  # Never sample
        retention 7.years
        adapters [:loki, :sentry, :s3_archive]
      end
    end
    
    module AuditEvent
      extend ActiveSupport::Concern
      
      included do
        audit_event true
        adapters [:audit_encrypted]
        retention 7.years
        rate_limiting false
        sampling false
        contains_pii true
      end
    end
    
    module DebugEvent
      extend ActiveSupport::Concern
      
      included do
        severity :debug
        sample_rate 0.01
        retention 7.days
        adapters [:file]
      end
    end
  end
end
```

### Step 3: Base Event Classes (Inheritance)

```ruby
# app/events/base_payment_event.rb
module Events
  class BasePaymentEvent < E11y::Event::Base
    # Common payment config:
    severity :success
    sample_rate 1.0  # Never sample payments (high-value!)
    retention 7.years  # Financial records
    adapters [:loki, :sentry, :s3_archive]
    
    pii_filtering do
      hashes :email, :user_id  # Common PII handling
    end
  end
end

# app/events/payment_succeeded.rb
class Events::PaymentSucceeded < Events::BasePaymentEvent
  schema do
    required(:transaction_id).filled(:string)
    required(:amount).filled(:decimal)
  end
  # ← Inherits ALL payment config! (5 lines total!)
end
```

---

## 📊 Configuration Size Comparison

### Before (Current - from @docs/COMPREHENSIVE-CONFIGURATION.md)

```ruby
# config/initializers/e11y.rb (1400+ lines)

E11y.configure do |config|
  # Adapters: ~100 lines
  # Pipeline: ~50 lines
  # PII Filtering: ~400 lines
  # Rate Limiting: ~300 lines
  # Sampling: ~250 lines
  # Metrics: ~200 lines
  # Audit: ~100 lines
  # ... etc.
end

# app/events/*.rb (0 lines - all config in initializer!)
```

**Total: 1400+ lines global, 0 lines per-event**

---

### After (Simplified - with 3-level hierarchy)

```ruby
# config/initializers/e11y.rb (~80 lines)

E11y.configure do |config|
  # Adapters: ~30 lines
  config.adapters do
    register :loki, Loki.new(url: ENV['LOKI_URL'])
    register :sentry, Sentry.new(dsn: ENV['SENTRY_DSN'])
    default_adapters [:loki]
  end
  
  # Global limits: ~20 lines
  config.rate_limiting do
    global_limit 10_000
    default_event_limit 1000
  end
  
  config.buffering.adaptive do
    enabled true
    memory_limit_mb 100
  end
  
  # Defaults overrides (optional): ~30 lines
  config.defaults.sample_rate_for_severity do
    success 0.05  # 5% instead of 10%
  end
end

# app/events/order_paid.rb (~5 lines - inherits defaults!)
class Events::OrderPaid < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:decimal)
  end
  # ← severity: :success (inferred from name)
  # ← adapters: [:loki] (global default)
  # ← sample_rate: 0.05 (global override)
  # ... ALL other config from defaults!
end

# app/events/payment_failed.rb (~7 lines - preset)
class Events::PaymentFailed < E11y::Event::Base
  include E11y::Presets::HighValueEvent  # ← 1-line config!
  
  schema do
    required(:order_id).filled(:string)
    required(:error_code).filled(:string)
  end
end

# app/events/permission_changed.rb (~5 lines - inheritance)
class Events::PermissionChanged < Events::BaseAuditEvent
  schema do
    required(:user_id).filled(:string)
    required(:old_role).filled(:string)
    required(:new_role).filled(:string)
  end
  # ← Inherits audit config!
end
```

**Total: ~80 global + (22 events × 6 lines avg) = 212 lines** ✅ **<300 TARGET MET!**

**Reduction: 85% (1400 → 212 lines)**

---

## 🔄 Override Mechanism (Runtime)

**Per-track overrides (when needed):**

```ruby
# Override adapters at track time:
Events::OrderPaid.track(
  order_id: '123',
  amount: 99.99,
  _adapters: [:sentry]  # ← Runtime override (highest precedence)
)

# Override severity:
Events::OrderPaid.track(
  order_id: '123',
  _severity: :error  # ← Runtime override (e.g., unexpected condition)
)
```

**Reserved keys:** `_adapters`, `_severity`, `_sample_rate` (prefixed with underscore, not in payload).

---

## 📝 Migration Guide (from Current to Simplified)

### Step 1: Extract Event-Level Config from Global

**Before:**
```ruby
# config/initializers/e11y.rb
config.rate_limiting do
  per_event 'order.paid', limit: 5000
  per_event 'user.login', limit: 500
end
```

**After:**
```ruby
# app/events/order_paid.rb
class Events::OrderPaid < E11y::Event::Base
  rate_limit 5000  # ← Move to event class!
end

# app/events/user_login.rb
class Events::UserLogin < E11y::Event::Base
  rate_limit 500  # ← Event-specific config
end
```

### Step 2: Create Base Classes for Common Patterns

**Identify repetition:**
```ruby
# 10 payment events with same config → BasePaymentEvent
# 5 audit events with same config → BaseAuditEvent
# 7 debug events with same config → include Presets::DebugEvent
```

### Step 3: Remove Redundant Config (Use Defaults)

**Before:**
```ruby
class Events::OrderPaid < E11y::Event::Base
  severity :success  # ← Redundant! (inferred from *Paid)
  adapters [:loki]  # ← Redundant! (global default)
  sample_rate 0.1  # ← Redundant! (default for :success)
end
```

**After:**
```ruby
class Events::OrderPaid < E11y::Event::Base
  schema do; ...; end
  # ← ALL config from defaults!
end
```

---

## ✅ Expected Outcome

- **Global config:** ~80 lines (infrastructure)
- **Event classes:** ~5-10 lines each (schema + overrides if needed)
- **Total for 22 events:** ~200-300 lines
- **Reduction:** 78-85% (from 1400+ lines)
- **Maintainability:** Config next to schema (locality of behavior)
- **Explicitness:** Sensible defaults clearly documented, easy to override

---

**Status:** ✅ Design Complete  
**Next:** Refactored configuration examples  
**Last Updated:** 2026-01-15

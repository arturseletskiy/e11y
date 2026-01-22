# AUDIT-004: ADR-001 Architecture - Convention over Configuration

**Document:** ADR-001-architecture.md  
**Task:** FEAT-4919 - Test convention over configuration philosophy  
**Auditor:** Agent  
**Date:** 2026-01-21  
**Status:** ✅ **AUDIT COMPLETE**

---

## Executive Summary

**Compliance Status:** ⚠️ **PARTIAL COMPLIANCE** (1 critical documentation issue)

**DoD Verification:**
- ⚠️ **DoD #1: Default config works** - PARTIAL (defaults exist, but adapters empty, many features opt-in)
- ❌ **DoD #2: 5-min setup** - **FAIL** (documentation mentions non-existent generator)
- ✅ **DoD #3: Override paths clear** - PASS (all settings overridable, hierarchy documented)

**Key Findings:**
- 🔴 **F-006 CRITICAL**: QUICK-START.md references `rails g e11y:install` generator that doesn't exist
- 🟡 **F-007 MEDIUM**: Default adapters configuration empty, relies on fallback to stdout
- 🟡 **F-008 MEDIUM**: Many features disabled by default (opt-in), contradicts "zero-config" claim

**Recommendation:** ⚠️ **GO WITH FIXES** - Core philosophy implemented, but documentation needs correction

---

## DoD Verification Matrix

| # | DoD Requirement | Status | Evidence |
|---|----------------|--------|----------|
| 1 | Default config: works without configuration, sensible defaults for adapters/buffers/middleware | ⚠️ **PARTIAL** | Middleware auto-configured (6 middleware), Railtie sets environment/service_name. BUT: adapters empty, many features opt-in (see F-007, F-008) |
| 2 | 5-min setup: fresh Rails app to first event in <5min, documentation accurate | ❌ **FAIL** | QUICK-START mentions `rails g e11y:install` generator that doesn't exist (see F-006) |
| 3 | Override paths: all defaults overridable, configuration hierarchy clear | ✅ **PASS** | All settings have `attr_accessor`, pipeline modifiable, adapter mapping overridable, hierarchy: defaults → Railtie → user config → event-level |

---

## Critical Findings

### Finding F-006: Non-existent generator in documentation (DoD violation)
**Severity:** 🔴 **CRITICAL**  
**Type:** Documentation error  
**Status:** Requires fix

**Issue:**  
QUICK-START.md (line 14) references Rails generator that doesn't exist in codebase.

**Evidence:**

1. **QUICK-START.md (lines 8-15):**
   ```ruby
   # Gemfile
   gem 'e11y', '~> 1.0'

   bundle install
   rails g e11y:install  # ← GENERATOR MENTIONED
   ```

2. **Codebase search:**
   ```bash
   # Glob: **/generators/**/*.rb
   Result: 0 files found
   ```

3. **Impact:**
   - **DoD #2 BLOCKED**: "5-min setup" instructions are incorrect
   - **New users broken**: Following docs leads to error `Could not find generator 'e11y:install'`
   - **Trust issue**: Documentation accuracy questioned

**Solutions:**

**Option A: Remove generator reference (Quick fix)**
```ruby
# Gemfile
gem 'e11y', '~> 1.0'

bundle install
# No generator needed! E11y auto-configures via Railtie
```
**Pros:** Aligns with "zero-config" philosophy, quick fix  
**Cons:** May need manual config for non-default setups  
**Time:** 5 minutes (update docs)

**Option B: Create generator (Complete fix)**
Create `lib/generators/e11y/install_generator.rb`:
```ruby
module E11y
  module Generators
    class InstallGenerator < Rails::Generators::Base
      def create_initializer
        create_file "config/initializers/e11y.rb", <<~RUBY
          E11y.configure do |config|
            # Optional: Custom adapter configuration
            # config.adapters[:loki] = E11y::Adapters::Loki.new(url: ENV['LOKI_URL'])
            
            # Optional: Enable features
            # config.rails_instrumentation.enabled = true
            # config.slo_tracking.enabled = true
          end
        RUBY
      end
    end
  end
end
```
**Pros:** Matches documentation, provides template  
**Cons:** Requires code implementation  
**Time:** 30-60 minutes (implement + test + docs)

**Recommendation:** **Option A** (remove generator reference). E11y Railtie already auto-configures, generator is redundant for "convention over configuration" philosophy. Update QUICK-START to emphasize zero-config approach.

**Priority:** P0 (blocks DoD #2, confuses new users)

---

### Finding F-007: Default adapters configuration empty
**Severity:** 🟡 **MEDIUM**  
**Type:** Design decision documentation gap  
**Status:** Acceptable with clarification

**Issue:**  
`@adapters = {}` is empty by default, relies on fallback mechanism.

**Evidence:**

1. **lib/e11y.rb (line 122):**
   ```ruby
   def initialize_basic_config
     @adapters = {} # Hash of adapter_name => adapter_instance
   ```

2. **Fallback mechanism (line 134):**
   ```ruby
   @fallback_adapters = [:stdout] # Fallback if no routing rule matches
   ```

3. **Adapter mapping (lines 167-173):**
   ```ruby
   def default_adapter_mapping
     {
       error: %i[logs errors_tracker],  # References :logs, :errors_tracker
       fatal: %i[logs errors_tracker],
       default: [:logs]                 # References :logs
     }
   end
   ```

**Problem:**
- Mapping references `:logs` and `:errors_tracker` adapters
- But `@adapters` hash is empty - these adapters don't exist!
- Fallback to `:stdout` happens, but this isn't documented

**Impact:**
- **Positive:** Gem works out-of-box (stdout adapter works)
- **Negative:** Unclear behavior ("Where do events go?")
- **Confusion:** Mapping mentions `:logs` but it doesn't exist by default

**Recommendation:**
1. Document fallback behavior clearly in code comments
2. Update README/QUICK-START to explain: "Events go to stdout by default"
3. Show example of registering :logs adapter:
   ```ruby
   E11y.configure do |config|
     config.adapters[:logs] = E11y::Adapters::Loki.new(...)
   end
   ```

**Priority:** P1 (documentation improvement, not blocking)

---

### Finding F-008: Many features disabled by default (opt-in)
**Severity:** 🟡 **MEDIUM**  
**Type:** Design vs documentation mismatch  
**Status:** Acceptable, needs documentation clarity

**Issue:**  
README claims "zero-config" but many features require explicit enablement.

**Evidence:**

**README.md (lines 35-47) claims:**
- "📐 **Convention over Configuration** - Smart defaults from event names"
- "📊 Pattern-Based Metrics (Prometheus/Yabeda)" ← Implied auto-enabled

**But implementation shows opt-in:**

1. **Rails instrumentation (lib/e11y.rb line 209):**
   ```ruby
   def initialize
     @enabled = false # Disabled by default, enabled by Railtie
   ```

2. **Request buffer (line 245):**
   ```ruby
   def initialize
     @enabled = false # Disabled by default
   end
   ```

3. **Rate limiting (line 274):**
   ```ruby
   def initialize
     @enabled = false # Opt-in (enable explicitly)
   ```

4. **SLO tracking (line 295):**
   ```ruby
   def initialize
     @enabled = false # Opt-in (enable explicitly)
   end
   ```

**What IS enabled by default:**
- ✅ Middleware pipeline (6 middleware auto-registered)
- ✅ Environment/service_name (from Railtie)
- ✅ Fallback to stdout adapter

**What requires opt-in:**
- ❌ Rails instrumentation (ActiveSupport::Notifications)
- ❌ Request-scoped debug buffer
- ❌ Rate limiting
- ❌ SLO tracking
- ❌ Logger bridge
- ❌ Sidekiq/ActiveJob integration

**Impact:**
- **Positive:** Minimal overhead by default (only what you use)
- **Negative:** "Zero-config" is misleading - basic tracking works, advanced features need config

**Recommendation:**
1. Clarify in docs: "**Zero-config for basic event tracking**. Advanced features (SLO, rate limiting, etc.) require explicit enablement."
2. Add "Feature Matrix" table to README:
   ```markdown
   | Feature | Default | Config Required |
   |---------|---------|-----------------|
   | Event tracking | ✅ Enabled | No |
   | Middleware pipeline | ✅ Auto-configured | Optional |
   | Rails instrumentation | ❌ Disabled | `config.rails_instrumentation.enabled = true` |
   | SLO tracking | ❌ Disabled | `config.slo_tracking.enabled = true` |
   ```

**Priority:** P2 (documentation clarity, not blocking)

---

## Verification Results (Detailed)

### 1. Default Configuration ⚠️

**What Works Out-of-Box:**

✅ **Railtie Auto-Configuration** (railtie.rb lines 34-41):
```ruby
config.before_initialize do
  E11y.configure do |config|
    config.environment = Rails.env.to_s
    config.service_name = derive_service_name  # From Rails app name
    config.enabled = !Rails.env.test?         # Auto-disabled in tests
  end
end
```
- Environment: Auto-set from `Rails.env`
- Service name: Derived from Rails application class name
- Test environment: Auto-disabled (no overhead in test suite)

✅ **Middleware Pipeline** (lib/e11y.rb lines 187-201):
```ruby
def configure_default_pipeline
  # Zone: :pre_processing
  @pipeline.use E11y::Middleware::TraceContext
  @pipeline.use E11y::Middleware::Validation

  # Zone: :security
  @pipeline.use E11y::Middleware::PIIFilter
  @pipeline.use E11y::Middleware::AuditSigning

  # Zone: :routing
  @pipeline.use E11y::Middleware::Sampling

  # Zone: :adapters
  @pipeline.use E11y::Middleware::Routing
end
```
- **6 middleware auto-registered**
- Pipeline zones: pre_processing → security → routing → adapters
- Documented in ADR-015 (per code comment line 177)

✅ **Basic Defaults** (lines 121-135):
- `@log_level = :info`
- `@enabled = true`
- `@default_retention_period = 30.days`
- `@fallback_adapters = [:stdout]`

⚠️ **Empty Adapters** (line 122):
- `@adapters = {}` - User must register adapters OR use fallback

**Verdict:** ⚠️ **PARTIAL** - Core infrastructure auto-configured, but user likely needs some config for production (adapter registration, feature enablement).

---

### 2. 5-Minute Setup ❌

**Documentation Claims (QUICK-START.md):**
```ruby
# Gemfile
gem 'e11y', '~> 1.0'

bundle install
rails g e11y:install  # ← PROBLEM: Generator doesn't exist!
```

**Actual Setup Process:**
1. ✅ Add gem to Gemfile: `gem 'e11y'`
2. ✅ Run `bundle install`
3. ❌ **FAILS**: `rails g e11y:install` → `Could not find generator 'e11y:install'`
4. ⚠️ User must manually create `config/initializers/e11y.rb` (if needed)

**What SHOULD happen (corrected docs):**
```ruby
# Gemfile
gem 'e11y'

bundle install
# E11y auto-configures via Railtie - no generator needed!

# Optional: Create initializer for custom config
# config/initializers/e11y.rb
E11y.configure do |config|
  config.adapters[:loki] = E11y::Adapters::Loki.new(url: ENV['LOKI_URL'])
  config.slo_tracking.enabled = true
end
```

**Time Estimate (corrected):**
- Gem install: 1-2 minutes
- Auto-configuration: 0 minutes (Railtie)
- Optional custom config: 2-3 minutes
- **Total: 3-5 minutes** ✅ (matches DoD if docs corrected)

**Verdict:** ❌ **FAIL** - Documentation incorrect (references non-existent generator). Corrected process WOULD meet 5-minute target.

---

### 3. Override Paths ✅

**Configuration Hierarchy (verified):**

1. **Hard-coded defaults** (in `Configuration#initialize` methods)
   - Example: `@log_level = :info`, `@enabled = true`
   
2. **Railtie auto-config** (runs `before_initialize`)
   - Sets: `environment`, `service_name`, `enabled`
   - Source: Rails application context

3. **User initializer** (`config/initializers/e11y.rb`)
   - Runs during Rails initialization
   - Can override ALL settings via `E11y.configure { |config| ... }`

4. **Event-level overrides** (Event::Base class methods)
   - Example: `severity :error`, `adapters :loki, :sentry`
   - Highest priority (most specific)

**All Settings Overridable:**

✅ **Via `attr_accessor`** (lines 107-108):
```ruby
attr_accessor :adapters, :log_level, :enabled, :environment, :service_name,
              :default_retention_period, :routing_rules, :fallback_adapters
```

✅ **Middleware pipeline** (line 124):
```ruby
@pipeline = E11y::Pipeline::Builder.new
# User can: config.pipeline.use MyMiddleware
```

✅ **Adapter mapping** (lines 154-156):
```ruby
def adapters_for_severity(severity)
  @adapter_mapping[severity] || @adapter_mapping[:default] || []
end
# User can set: config.adapter_mapping[:error] = [:my_custom_adapter]
```

✅ **Feature configs** (lines 137-146):
```ruby
@rails_instrumentation = RailsInstrumentationConfig.new
@logger_bridge = LoggerBridgeConfig.new
@request_buffer = RequestBufferConfig.new
# Each has own attr_accessor for fine-grained control
```

**Example: Complete Override**
```ruby
E11y.configure do |config|
  # Override basic config
  config.log_level = :debug
  config.enabled = false  # Disable entirely
  
  # Override adapters
  config.adapters.clear
  config.adapters[:custom] = MyAdapter.new
  
  # Override middleware pipeline
  config.pipeline.clear
  config.pipeline.use MyCustomMiddleware
  
  # Override adapter mapping
  config.adapter_mapping.clear
  config.adapter_mapping[:error] = [:custom]
  
  # Enable features
  config.slo_tracking.enabled = true
  config.rate_limiting.enabled = true
end
```

**Documentation:**
- ✅ Configuration hierarchy mentioned in Railtie comments (line 18-29)
- ✅ Override examples in code comments (lines 88-105)
- ⚠️ Could be more prominent in README/QUICK-START

**Verdict:** ✅ **PASS** - All settings overridable, hierarchy clear, flexibility excellent.

---

## Configuration Defaults Summary

| Setting | Default Value | Source | Override Method |
|---------|--------------|--------|-----------------|
| **Basic Config** ||||
| `adapters` | `{}` (empty) | Hard-coded | `config.adapters[:name] = adapter` |
| `log_level` | `:info` | Hard-coded | `config.log_level = :debug` |
| `enabled` | `true` (dev/prod), `false` (test) | Railtie | `config.enabled = false` |
| `environment` | From `Rails.env` | Railtie | `config.environment = 'staging'` |
| `service_name` | From Rails app name | Railtie | `config.service_name = 'my-app'` |
| `default_retention_period` | `30.days` | Hard-coded | `config.default_retention_period = 90.days` |
| `fallback_adapters` | `[:stdout]` | Hard-coded | `config.fallback_adapters = [:file]` |
| **Middleware Pipeline** ||||
| Pipeline | 6 middleware (TraceContext, Validation, PIIFilter, AuditSigning, Sampling, Routing) | Auto-configured | `config.pipeline.use MyMiddleware` |
| **Adapter Mapping** ||||
| `error`/`fatal` | `[:logs, :errors_tracker]` | Hard-coded | `config.adapter_mapping[:error] = [:custom]` |
| `default` | `[:logs]` | Hard-coded | `config.adapter_mapping[:default] = [:stdout]` |
| **Features (Opt-In)** ||||
| Rails instrumentation | `false` | Hard-coded | `config.rails_instrumentation.enabled = true` |
| Request buffer | `false` | Hard-coded | `config.request_buffer.enabled = true` |
| Rate limiting | `false` | Hard-coded | `config.rate_limiting.enabled = true` |
| SLO tracking | `false` | Hard-coded | `config.slo_tracking.enabled = true` |
| Logger bridge | `false` | Hard-coded | `config.logger_bridge.enabled = true` |

---

## Production Readiness Assessment

### Functionality ⚠️
- [x] Convention over configuration philosophy implemented
- [x] Railtie auto-configuration works (environment, service_name)
- [x] Middleware pipeline auto-registered (6 middleware)
- [ ] **BLOCKER**: Generator mentioned in docs doesn't exist (F-006)
- [ ] **GAP**: Many features opt-in (contradicts "zero-config" claim) (F-008)

### Documentation 🔴
- [x] ADR-001 documents architecture
- [x] README shows quick start example
- [x] Code comments explain configuration
- [ ] **CRITICAL**: QUICK-START references non-existent generator (F-006)
- [ ] **MEDIUM**: Feature opt-in/opt-out not clearly documented (F-008)
- [ ] **MEDIUM**: Adapter fallback behavior not documented (F-007)

### Testing ❓
- ❓ **UNKNOWN**: No tests reviewed for this task (DoD focused on docs/config)
- **Note**: Tests likely exist for Configuration class, Railtie, etc.

**Overall Status:** ⚠️ **MOSTLY PRODUCTION READY** (with doc fixes)

---

## Recommendations

### Immediate Actions (P0 - Blocks DoD Completion)

**1. Fix QUICK-START generator reference (F-006):**

**Remove generator reference**, update QUICK-START.md lines 8-15:
```markdown
## 🚀 Installation (2 minutes)

```ruby
# Gemfile
gem 'e11y'
```

```bash
bundle install
```

**That's it!** E11y auto-configures via Railtie:
- Service name: derived from your Rails app name
- Environment: matches `Rails.env`
- Events route to stdout by default

**Optional: Custom Configuration**

Create `config/initializers/e11y.rb` only if you need custom adapters:

```ruby
E11y.configure do |config|
  config.adapters[:loki] = E11y::Adapters::Loki.new(url: ENV['LOKI_URL'])
end
```
```

**Time:** 5 minutes  
**Impact:** Unblocks DoD #2, prevents user confusion

---

### High Priority (P1 - Documentation Clarity)

**2. Document adapter fallback behavior (F-007):**

Add to Configuration class comment (lib/e11y.rb line 84):
```ruby
# Configuration class for E11y
#
# **Adapter Defaults:**
# - Adapters hash starts empty (`@adapters = {}`)
# - Fallback to `[:stdout]` if no adapter registered
# - Users should register at least one adapter for production:
#   config.adapters[:loki] = E11y::Adapters::Loki.new(url: ...)
#
# Adapters are referenced by name (e.g., :logs, :errors_tracker).
# The actual implementation (Loki, Sentry, etc.) is configured separately.
```

**Time:** 10 minutes

---

**3. Add "Feature Matrix" to README (F-008):**

Add after "Features" section (README.md line 48):
```markdown
## 📊 Feature Matrix

| Feature | Default State | Config Required? |
|---------|---------------|------------------|
| **Core** |||
| Event tracking | ✅ Enabled | No - works out-of-box |
| Middleware pipeline | ✅ Auto-configured | Optional overrides |
| Railtie integration | ✅ Auto-enabled | `config.enabled = false` to disable |
| **Advanced** |||
| Rails instrumentation | ❌ Disabled | `config.rails_instrumentation.enabled = true` |
| Request-scoped buffer | ❌ Disabled | `config.request_buffer.enabled = true` |
| SLO tracking | ❌ Disabled | `config.slo_tracking.enabled = true` |
| Rate limiting | ❌ Disabled | `config.rate_limiting.enabled = true` |
| Logger bridge | ❌ Disabled | `config.logger_bridge.enabled = true` |
| **Adapters** |||
| Default adapter | `:stdout` | Register custom: `config.adapters[:loki] = ...` |
```

**Time:** 15 minutes

---

### Medium Priority (P2 - Nice-to-Have)

**4. Create optional generator (if desired):**

If team decides generator is valuable, implement:
- `lib/generators/e11y/install_generator.rb`
- Creates `config/initializers/e11y.rb` template
- Documents common configuration options

**Time:** 30-60 minutes  
**Note:** Not strictly necessary given Railtie auto-config

---

## Appendix A: Code Locations

### Configuration
- `lib/e11y.rb` (305 lines)
  - Configuration class: lines 106-202
  - Default adapter mapping: lines 167-173
  - Default pipeline: lines 187-201
  - Feature configs: lines 204-297

### Railtie
- `lib/e11y/railtie.rb` (139 lines)
  - Auto-configuration: lines 34-41
  - Middleware insertion: lines 54-64
  - Feature setup: lines 47-51

### Documentation
- `README.md` (218 lines)
  - Quick start: lines 12-31
  - Features: lines 33-48
- `docs/QUICK-START.md` (935+ lines)
  - Installation: lines 7-15 ← **CONTAINS BUG (F-006)**
- `docs/ADR-001-architecture.md` (2618+ lines)
  - Architecture goals: lines 50-88

---

## Decision Log

**Decision: Remove generator reference from QUICK-START**
- **Date:** 2026-01-21
- **Rationale:** Generator doesn't exist, contradicts "zero-config" philosophy. Railtie already auto-configures everything needed.
- **Alternative considered:** Create generator (rejected - adds complexity, not aligned with convention over configuration)

---

**END OF AUDIT REPORT**

**Status:** ✅ AUDIT COMPLETE

**Summary:**
- ✅ Convention over configuration philosophy **implemented**
- ✅ Sensible defaults present (middleware, railtie auto-config)
- ✅ Override paths clear and flexible
- ❌ **Documentation issue**: Non-existent generator blocks DoD #2
- ⚠️ **Clarification needed**: Many features opt-in (not strictly "zero-config")

**Action Required:** Fix QUICK-START.md (remove generator reference)

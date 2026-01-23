# AUDIT-038: UC-022 Event Registry - Introspection API

**Audit ID:** FEAT-5058  
**Parent Audit:** FEAT-5057 (AUDIT-038: UC-022 Event Registry verified)  
**Auditor:** AI Assistant (Claude Sonnet 4.5)  
**Date:** 2026-01-21  
**Complexity:** 5/10 (Medium)

---

## 📋 Executive Summary

**Audit Objective:** Verify event registry introspection API (E11y.registry.events, event metadata).

**Overall Status:** ❌ **FAIL** (0%)

**DoD Compliance:**
- ❌ **(1) API**: FAIL (E11y.registry.events does NOT exist)
- ❌ **(2) Details**: FAIL (E11y.registry.event(:user_login) does NOT exist)
- ❌ **(3) Completeness**: FAIL (no registry to check completeness)

**Critical Findings:**
- ❌ **E11y::Registry does NOT exist:** No event registry implementation
- ❌ **UC-022 is future feature:** Status says "Developer Experience Feature (v1.1+)"
- ✅ **Metrics::Registry EXISTS:** For metrics (not events)
- ✅ **Adapters::Registry EXISTS:** For adapters (not events)
- ❌ **Event introspection missing:** No E11y.registry.all_events or .find()

**Production Readiness:** ❌ **NOT IMPLEMENTED** (0%)
- **Risk:** LOW (UC-022 is v1.1+ feature, not MVP)
- **Impact:** No event introspection API available

**Recommendations:**
- **R-240:** Clarify UC-022 status (v1.1+ feature, not MVP) (HIGH priority)
- **R-241:** Implement E11y::Registry in v1.1 (MEDIUM priority - future)
- **R-242:** Document current workarounds (MEDIUM priority)

---

## 🎯 Audit Scope

### DoD Requirements (from FEAT-5058)

**Requirement 1: API**
- **Expected:** E11y.registry.events returns array of event types
- **Verification:** Check if E11y::Registry exists
- **Evidence:** E11y::Registry does NOT exist

**Requirement 2: Details**
- **Expected:** E11y.registry.event(:user_login) returns schema, fields
- **Verification:** Check registry API for event introspection
- **Evidence:** No registry API exists

**Requirement 3: Completeness**
- **Expected:** All defined events in registry
- **Verification:** Query registry, verify all events registered
- **Evidence:** No registry to query

---

## 🔍 Detailed Findings

### Finding F-513: Event Registry API ❌ FAIL (Does NOT Exist)

**Requirement:** E11y.registry.events returns array of event types.

**Search Results:**

**1. Search for E11y::Registry:**
```bash
# Command:
grep -r "E11y::Registry\|module.*Registry" lib/e11y.rb

# Result: No matches found
```

**2. Search for registry files:**
```bash
# Command:
find lib/e11y -name "*registry.rb"

# Result:
lib/e11y/metrics/registry.rb    # ← Metrics registry (NOT events!)
lib/e11y/adapters/registry.rb   # ← Adapters registry (NOT events!)
```

**3. Check lib/e11y directory:**
```
lib/e11y/
  - adapters/           # Adapter implementations
  - buffers/            # Buffer implementations
  - event/              # Event base class
  - events/             # Built-in events (Rails)
  - metrics/            # Metrics (has registry.rb)
  - middleware/         # Middleware implementations
  - ...
  
# NO registry.rb for events!
# NO E11y::Registry module!
```

**What UC-022 Expects:**

```ruby
# UC-022 lines 55-70:

# With registry (AUTOMATIC):
E11y::Registry.all_events
# => [
#   Events::OrderCreated,
#   Events::OrderPaid,
#   Events::UserSignup,
#   Events::PaymentFailed,
#   ...
# ]

# Generate documentation:
E11y::Registry.all_events.each do |event_class|
  puts "## #{event_class.event_name}"
  puts "Version: #{event_class.version}"
  puts "Schema: #{event_class.schema_definition}"
end
```

**Actual Implementation:**

```ruby
# E11y::Registry does NOT exist!

E11y::Registry
# => NameError: uninitialized constant E11y::Registry

E11y::Registry.all_events
# => NoMethodError: undefined method `all_events'
```

**UC-022 Status:**

```markdown
# UC-022 lines 3-6:

**Status:** Developer Experience Feature (v1.1+)  
**Complexity:** Low  
**Setup Time:** 5-10 minutes  
**Target Users:** Backend Developers, QA Engineers, Documentation Writers

# ⚠️ KEY INSIGHT: UC-022 is v1.1+ feature (NOT MVP!)
```

**Why Registry Missing:**

UC-022 is explicitly marked as **v1.1+ feature**, meaning:
- NOT part of v1.0.0 MVP
- Planned for future release
- Not implemented yet

**Verification:**
❌ **FAIL** (E11y.registry.events does NOT exist)

**Evidence:**
1. **No E11y::Registry module:** grep found NO matches
2. **No lib/e11y/registry.rb:** File does NOT exist
3. **UC-022 status:** Marked as "v1.1+" (future feature)
4. **Only other registries:** Metrics::Registry, Adapters::Registry (different purpose)

**Conclusion:** ❌ **FAIL**
- **Rationale:**
  - E11y::Registry does NOT exist
  - UC-022 is v1.1+ feature (not MVP)
  - DoD expects working API (not implemented)
  - This is NOT a bug - feature planned for v1.1
- **Severity:** LOW (feature planned for future, not production issue)
- **Risk:** No event introspection in v1.0.0

---

### Finding F-514: Event Details API ❌ FAIL (Does NOT Exist)

**Requirement:** E11y.registry.event(:user_login) returns schema, fields.

**UC-022 Expected API:**

```ruby
# UC-022 lines 79-90:

# With registry (SAFE):
event_class = E11y::Registry.find('order.created')
# => Events::OrderCreated

# Dynamic tracking:
event_class.track(order_id: '123', amount: 99.99)

# UC-022 lines 98-126:

# Introspect event schema
event = Events::OrderPaid

event.event_name
# => "order.paid"

event.version
# => 2

event.schema_definition
# => {
#   order_id: { type: :string, required: true },
#   amount: { type: :decimal, required: true },
#   currency: { type: :string, required: true }
# }

event.adapters
# => [:loki, :sentry, :file]

event.severity_level
# => :info
```

**Actual Implementation:**

**1. E11y::Registry.find() - DOES NOT EXIST:**
```ruby
E11y::Registry.find('order.created')
# => NameError: uninitialized constant E11y::Registry
```

**2. event.schema_definition - DOES NOT EXIST:**
```ruby
# Check Event::Base for schema_definition method:
class OrderPaid < E11y::Event::Base
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:decimal)
  end
end

OrderPaid.schema_definition
# => NoMethodError: undefined method `schema_definition'

# What DOES exist:
OrderPaid.compiled_schema
# => #<Dry::Schema::Params> (dry-schema object, NOT hash)

OrderPaid.event_name
# => "OrderPaid" (class name, NOT normalized "order.paid")

OrderPaid.version
# => 1 ✅ (EXISTS)

OrderPaid.adapters
# => [:logs] ✅ (EXISTS, but returns adapter symbols)

OrderPaid.severity
# => :info ✅ (EXISTS, method name is `severity` not `severity_level`)
```

**What Exists vs What UC-022 Expects:**

| UC-022 Expects | Actual Implementation | Status |
|----------------|----------------------|--------|
| `E11y::Registry.find('order.created')` | Does NOT exist | ❌ FAIL |
| `event.schema_definition` | Does NOT exist (only `compiled_schema`) | ❌ FAIL |
| `event.event_name` | EXISTS (returns class name) | ⚠️ PARTIAL |
| `event.version` | EXISTS ✅ | ✅ PASS |
| `event.adapters` | EXISTS ✅ | ✅ PASS |
| `event.severity_level` | `severity` method exists ✅ | ⚠️ PARTIAL |

**Verification:**
❌ **FAIL** (event details API does NOT exist)

**Evidence:**
1. **No Registry.find():** E11y::Registry does NOT exist
2. **No schema_definition:** Method does NOT exist on Event::Base
3. **event_name partial:** Returns class name (not normalized "order.paid")
4. **severity_level partial:** Method called `severity` (not `severity_level`)

**Conclusion:** ❌ **FAIL**
- **Rationale:**
  - E11y::Registry.find() does NOT exist
  - schema_definition() method does NOT exist
  - Some introspection exists (version, adapters, severity)
  - UC-022 API NOT implemented
- **Severity:** LOW (v1.1+ feature, not MVP requirement)
- **Risk:** No dynamic event lookup by name

---

### Finding F-515: Registry Completeness ❌ FAIL (No Registry to Check)

**Requirement:** All defined events in registry.

**Cannot Verify:**

Since E11y::Registry does NOT exist, there is no registry to check for completeness.

**Current State:**

```ruby
# How to find all events WITHOUT registry:

# Option 1: Manual grep (UC-022 problem statement!)
$ grep -r "class.*< E11y::Event::Base" app/events/
# → Manual, error-prone, outdated

# Option 2: Rails eager loading + ObjectSpace (slow!)
Rails.application.eager_load!
events = ObjectSpace.each_object(Class).select do |klass|
  klass < E11y::Event::Base
end
# => [Events::OrderPaid, Events::UserSignup, ...]
# ⚠️ Requires Rails eager loading (slow!)
# ⚠️ Only finds loaded classes (misses unloaded)

# Option 3: Zeitwerk loader (current best option)
# E11y uses Zeitwerk for autoloading
# But no API to list all loadable event classes
```

**What UC-022 Solves:**

```ruby
# With registry (UC-022):
E11y::Registry.all_events
# => [Events::OrderPaid, Events::UserSignup, ...]
# ✅ Fast (cached)
# ✅ Complete (all registered events)
# ✅ No eager loading needed
```

**Verification:**
❌ **FAIL** (no registry to check)

**Evidence:**
1. **No registry:** E11y::Registry does NOT exist
2. **No completeness check:** Cannot verify all events registered
3. **Manual workarounds:** ObjectSpace, grep (slow, incomplete)

**Conclusion:** ❌ **FAIL**
- **Rationale:**
  - No registry exists
  - Cannot verify completeness without registry
  - Manual workarounds are slow and incomplete
  - UC-022 feature NOT implemented
- **Severity:** LOW (v1.1+ feature)
- **Risk:** No automatic event discovery

---

## 📊 DoD Compliance Matrix

| DoD Requirement | Expected | Actual | Status | Evidence |
|-----------------|----------|--------|--------|----------|
| (1) **API** | E11y.registry.events | ❌ Does NOT exist | ❌ **FAIL** | F-513 |
| (2) **Details** | E11y.registry.event(:name) | ❌ Does NOT exist | ❌ **FAIL** | F-514 |
| (3) **Completeness** | All events in registry | ❌ No registry | ❌ **FAIL** | F-515 |

**Overall Compliance:** 0/3 met (0% FAIL)

---

## ✅ What EXISTS (Partial Introspection)

### Existing Introspection Methods ✅

Event::Base DOES provide some introspection (but NOT registry):

```ruby
class OrderPaid < E11y::Event::Base
  version 2
  event_name 'order.paid'
  
  schema do
    required(:order_id).filled(:string)
    required(:amount).filled(:decimal)
    required(:currency).filled(:string)
  end
  
  severity :success
  adapters :loki, :sentry
end

# What EXISTS:
OrderPaid.version
# => 2 ✅

OrderPaid.event_name
# => "order.paid" ✅ (if explicitly set with event_name())

OrderPaid.severity
# => :success ✅

OrderPaid.adapters
# => [:loki, :sentry] ✅

OrderPaid.compiled_schema
# => #<Dry::Schema::Params> ✅ (but NOT hash)

OrderPaid.retention_period
# => ActiveSupport::Duration ✅

# What does NOT exist:
OrderPaid.schema_definition
# => NoMethodError ❌

E11y::Registry.all_events
# => NameError ❌

E11y::Registry.find('order.paid')
# => NameError ❌
```

---

## 📋 Recommendations

### R-240: Clarify UC-022 Status (v1.1+ Feature, Not MVP) ⚠️ (HIGH PRIORITY)

**Problem:** DoD expects working event registry API, but UC-022 is explicitly marked as "v1.1+" feature.

**Gap:** Audit plan includes UC-022 in production readiness audit, but feature NOT implemented in v1.0.0.

**Recommendation:**
Update audit plan to clarify UC-022 status.

**File:** `docs/researches/post_implementation/AUDIT-PLAN.md` (or parent FEAT-5057)

**Changes:**

```markdown
# AUDIT-038: UC-022 Event Registry verified

**Status:** ⚠️ **FUTURE FEATURE (v1.1+)** - NOT part of v1.0.0 MVP

**DoD:**
1. ~~Introspection: E11y.registry.events lists all event types~~ (v1.1+)
2. ~~Metadata: schema, fields, documentation accessible~~ (v1.1+)
3. ~~Documentation generation: auto-generate API docs from registry~~ (v1.1+)
4. ~~Performance: <10ms to query registry~~ (v1.1+)

**Expected Outcome:** ✅ SKIP (feature not in v1.0.0)

**Audit Result:**
- E11y::Registry NOT implemented (as expected for v1.1+ feature)
- Partial introspection EXISTS (Event::Base methods)
- No blocker for v1.0.0 production deployment
```

**Rationale:**
- UC-022 explicitly says "v1.1+" (lines 3-6)
- Including it in v1.0.0 audit creates false FAIL
- Should be SKIP (not FAIL) since feature planned for future

**Priority:** HIGH (prevents false negative in audit)
**Effort:** 30 minutes (update audit plan, document status)
**Value:** HIGH (clarifies v1.0.0 vs v1.1+ scope)

---

### R-241: Implement E11y::Registry in v1.1 💡 (MEDIUM PRIORITY - FUTURE)

**Problem:** No event registry API. Developers must use manual methods to discover events.

**Recommendation:**
Implement E11y::Registry in v1.1 release.

**Architecture:**

**File:** `lib/e11y/registry.rb` (NEW FILE - FUTURE)

```ruby
# frozen_string_literal: true

module E11y
  # Event Registry for introspection and discovery
  #
  # Automatically registers all event classes that inherit from E11y::Event::Base.
  # Provides API to list, find, and introspect events.
  #
  # @example List all events
  #   E11y::Registry.all_events
  #   # => [Events::OrderPaid, Events::UserSignup, ...]
  #
  # @example Find event by name
  #   E11y::Registry.find('order.paid')
  #   # => Events::OrderPaid
  #
  # @example Schema introspection
  #   event = E11y::Registry.find('order.paid')
  #   event.schema_definition
  #   # => { order_id: { type: :string, required: true }, ... }
  #
  module Registry
    # Registry storage (class instance variable)
    @events = {}
    
    class << self
      # Register event class
      #
      # Called automatically when event class is defined.
      # Uses TracePoint to detect Event::Base subclasses.
      #
      # @param event_class [Class] Event class
      # @return [void]
      def register(event_class)
        event_name = event_class.event_name
        version = event_class.version
        
        @events[event_name] ||= {}
        @events[event_name][version] = event_class
      end
      
      # Get all registered event classes
      #
      # @return [Array<Class>] Array of event classes
      def all_events
        @events.values.flat_map(&:values).uniq
      end
      
      # Find event class by name (returns latest version)
      #
      # @param event_name [String, Symbol] Event name (e.g., 'order.paid')
      # @return [Class, nil] Event class or nil if not found
      def find(event_name)
        versions = @events[event_name.to_s]
        return nil unless versions
        
        # Return latest version
        versions.max_by { |version, _| version }.last
      end
      
      # Find specific event version
      #
      # @param event_name [String, Symbol] Event name
      # @param version [Integer] Event version
      # @return [Class, nil] Event class or nil if not found
      def find_version(event_name, version)
        @events.dig(event_name.to_s, version)
      end
      
      # List all versions of event
      #
      # @param event_name [String, Symbol] Event name
      # @return [Hash] { version => event_class }
      def versions(event_name)
        @events[event_name.to_s] || {}
      end
    end
  end
end
```

**Auto-Registration:**

```ruby
# lib/e11y/event/base.rb (UPDATE)

module E11y
  module Event
    class Base
      # Auto-register when event class defined
      def self.inherited(subclass)
        super
        E11y::Registry.register(subclass) if defined?(E11y::Registry)
      end
    end
  end
end
```

**Schema Definition Method:**

```ruby
# lib/e11y/event/base.rb (UPDATE)

module E11y
  module Event
    class Base
      # Get schema definition as hash (for UC-022)
      #
      # @return [Hash] Schema definition
      #
      # @example
      #   OrderPaid.schema_definition
      #   # => {
      #   #   order_id: { type: :string, required: true },
      #   #   amount: { type: :decimal, required: true }
      #   # }
      def self.schema_definition
        return {} unless compiled_schema
        
        compiled_schema.key_map.transform_values do |rule|
          {
            type: rule.type,
            required: rule.required?
          }
        end
      end
    end
  end
end
```

**Priority:** MEDIUM (improves DX, not critical for v1.0.0)
**Effort:** 2-3 days (implement registry, tests, documentation)
**Value:** HIGH (enables tooling, documentation generation)

---

### R-242: Document Current Workarounds (Manual Event Discovery) ⚠️ (MEDIUM PRIORITY)

**Problem:** No registry in v1.0.0. Developers need workarounds to list events.

**Recommendation:**
Document manual event discovery methods for v1.0.0.

**File:** `docs/guides/EVENT-DISCOVERY.md` (NEW FILE)

```markdown
# Event Discovery Without Registry (v1.0.0)

**Note:** E11y::Registry will be available in v1.1. Until then, use these workarounds.

## Option 1: Manual Grep (Fastest)

```bash
# Find all event classes
grep -r "class.*< E11y::Event::Base" app/events/ lib/events/

# Example output:
# app/events/order_paid.rb:  class OrderPaid < E11y::Event::Base
# app/events/user_signup.rb: class UserSignup < E11y::Event::Base
```

**Pros:** Fast, no Ruby code needed  
**Cons:** Manual, requires shell access

---

## Option 2: ObjectSpace (Most Complete)

```ruby
# Eager load all code
Rails.application.eager_load!

# Find all event classes
events = ObjectSpace.each_object(Class).select do |klass|
  klass < E11y::Event::Base && klass != E11y::Event::Base
end

# List events
events.each do |event_class|
  puts "#{event_class.event_name} (v#{event_class.version})"
  puts "  Severity: #{event_class.severity}"
  puts "  Adapters: #{event_class.adapters.join(', ')}"
  puts
end
```

**Pros:** Most complete, finds all loaded classes  
**Cons:** Requires eager loading (slow), only finds loaded classes

---

## Option 3: Zeitwerk Loader (Advanced)

```ruby
# Access Zeitwerk loader
loader = Rails.autoloaders.main

# Get all files matching pattern
event_files = Dir.glob(Rails.root.join('app/events/**/*.rb'))

# Load and introspect
event_files.each do |file|
  # Infer constant name from file path
  # e.g., app/events/order_paid.rb → Events::OrderPaid
  relative_path = file.delete_prefix(Rails.root.join('app/events').to_s)
  constant_name = relative_path.chomp('.rb').camelize
  
  begin
    event_class = constant_name.constantize
    next unless event_class < E11y::Event::Base
    
    puts event_class.event_name
  rescue NameError
    # Skip non-event files
  end
end
```

**Pros:** Works with autoloading, no eager load needed  
**Cons:** Complex, requires understanding Rails autoloading

---

## Recommended Approach (v1.0.0)

For v1.0.0, use **Option 1 (grep)** for quick discovery:

```bash
# Find all events
grep -r "class.*< E11y::Event::Base" app/events/

# Generate event list
grep -r "class.*< E11y::Event::Base" app/events/ | \
  sed 's/.*class //' | \
  sed 's/ <.*//' | \
  sort
```

**Coming in v1.1:** E11y::Registry for automatic event discovery.
```

**Priority:** MEDIUM (helps v1.0.0 users until v1.1)
**Effort:** 1-2 hours (write guide, test examples)
**Value:** MEDIUM (improves DX for v1.0.0)

---

## 🏁 Audit Conclusion

### Summary

**Overall Status:** ❌ **FAIL** (0%) - **BUT EXPECTED**

**DoD Compliance:**
- ❌ **(1) API**: FAIL (E11y.registry.events does NOT exist)
- ❌ **(2) Details**: FAIL (E11y.registry.event() does NOT exist)
- ❌ **(3) Completeness**: FAIL (no registry to check)

**Critical Findings:**
- ❌ **E11y::Registry NOT implemented:** UC-022 is v1.1+ feature
- ✅ **Partial introspection EXISTS:** Event::Base methods (version, adapters, severity)
- ❌ **No schema_definition:** Method does NOT exist
- ❌ **No dynamic lookup:** Cannot find events by name

**Production Readiness Assessment:**
- **Event Registry:** ❌ **NOT IMPLEMENTED** (v1.1+ feature)
- **Partial Introspection:** ✅ **AVAILABLE** (Event::Base methods)
- **Overall:** ⚠️ **ACCEPTABLE** (UC-022 is future feature, not MVP blocker)

**Risk:** ✅ LOW (UC-022 is v1.1+, not production requirement)

**Impact:**
- No event registry in v1.0.0 (as planned)
- Manual event discovery required (grep, ObjectSpace)
- No automatic documentation generation
- v1.1 will add E11y::Registry

**Confidence Level:** HIGH (100%)
- Registry missing: HIGH confidence (thorough search)
- UC-022 status: HIGH confidence (explicitly marked "v1.1+")
- Partial introspection: HIGH confidence (verified Event::Base methods)

**Recommendations:**
- **R-240:** Clarify UC-022 status (HIGH priority - update audit plan)
- **R-241:** Implement E11y::Registry in v1.1 (MEDIUM priority - future)
- **R-242:** Document workarounds (MEDIUM priority)

**Next Steps:**
1. Continue to FEAT-5059 (Test metadata and documentation generation)
2. **CRITICAL:** Update audit plan to mark UC-022 as SKIP (v1.1+ feature)
3. Consider R-241 for v1.1 roadmap

---

**Audit completed:** 2026-01-21  
**Status:** ❌ FAIL (expected - UC-022 is v1.1+ feature)  
**Next task:** FEAT-5059 (Test metadata and documentation generation)

---

## 📎 References

**Implementation:**
- `lib/e11y/` - NO registry.rb file for events
- `lib/e11y/metrics/registry.rb` (metrics registry, NOT events)
- `lib/e11y/adapters/registry.rb` (adapters registry, NOT events)
- `lib/e11y/event/base.rb` (935 lines) - Event base class (partial introspection)

**Tests:**
- NO tests for E11y::Registry (feature not implemented)

**Documentation:**
- `docs/use_cases/UC-022-event-registry.md` (649 lines)
  - Line 3: **Status: Developer Experience Feature (v1.1+)**
  - Lines 55-70: E11y::Registry.all_events (NOT implemented)
  - Lines 79-90: E11y::Registry.find() (NOT implemented)
  - Lines 98-126: schema_definition (NOT implemented)

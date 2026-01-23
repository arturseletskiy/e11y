# AUDIT-008: ADR-015 Middleware Execution Order - Override Behavior

**Audit ID:** AUDIT-008  
**Task:** FEAT-4935  
**Auditor:** AI Assistant (Claude Sonnet 4.5)  
**Date:** 2026-01-21  
**ADR Reference:** ADR-015 Middleware Execution Order  
**Related:** AUDIT-008 FEAT-4934 (Middleware Ordering Guarantees)

---

## 📋 Executive Summary

**Audit Objective:** Verify middleware override behavior including config overrides, silent reordering prevention, and middleware removal.

**Scope:**
- Config overrides: `E11y.configure { pipeline.use X }` respects declaration order
- Silent reordering: Config conflicts raise clear errors
- Middleware removal: `pipeline.remove(X)` functionality

**Overall Status:** ⚠️ **PARTIAL** (40%)

**Key Findings:**
- ✅ **PASS**: Config overrides respect order (sequential `use` calls)
- ✅ **PASS**: Zone violations raise clear errors (boot-time validation)
- ⚠️ **PARTIAL**: Clear middleware via `clear()` method (not `remove()`)
- ❌ **NOT_IMPLEMENTED**: No `remove(middleware_class)` API
- ❌ **NOT_TESTED**: No override scenario tests

---

## 📊 Definition of Done (DoD) Verification

| DoD Requirement | Status | Evidence | Severity |
|----------------|--------|----------|----------|
| **(1) Config overrides: E11y.configure { pipeline.use X } respects order** | ✅ PASS | Default pipeline + user config | ✅ |
| **(2a) No silent reordering: zone conflicts raise error** | ✅ PASS | ZoneValidator boot-time check | ✅ |
| **(2b) No silent reordering: clear error messages** | ✅ PASS | ZoneOrderError with details | ✅ |
| **(3a) Remove middleware: pipeline.remove(X) works** | ❌ FAIL | No remove() method found | MEDIUM |
| **(3b) Remove middleware: doesn't break chain** | ❌ N/A | No remove() to test | MEDIUM |
| **(3c) Override tests: verify override scenarios** | ❌ FAIL | No override tests found | MEDIUM |

**DoD Compliance:** 3/6 requirements met (50%)

---

## 🔍 AUDIT AREA 1: Config Override Behavior

### 1.1. Default Pipeline Configuration

**File:** `lib/e11y.rb:187-200`

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

**Finding:**
```
F-098: Default Pipeline Setup (PASS) ✅
────────────────────────────────────────
Component: lib/e11y.rb#configure_default_pipeline
Requirement: Default middleware pipeline configured
Status: PASS ✅

Evidence:
- Default pipeline in Configuration#initialize (line 116)
- 6 default middlewares (TraceContext, Validation, PIIFilter, AuditSigning, Sampling, Routing)
- Follows zone order (ADR-015 compliance)

Default Order:
1. TraceContext (:pre_processing)
2. Validation (:pre_processing)
3. PIIFilter (:security)
4. AuditSigning (:security)
5. Sampling (:routing)
6. Routing (:adapters)

Verdict: PASS ✅ (default pipeline correctly configured)
```

### 1.2. User Override Mechanism

**Configuration API:**
```ruby
# User configuration:
E11y.configure do |config|
  config.pipeline.use MyCustomMiddleware  # ← Appends to default pipeline
end
```

**Behavior:**
```ruby
# Default: [TraceContext, Validation, PIIFilter, AuditSigning, Sampling, Routing]
# User adds: config.pipeline.use MyCustomMiddleware
# Result: [TraceContext, ..., Routing, MyCustomMiddleware]  # ← Appended
```

**Finding:**
```
F-099: User Configuration Appends to Default (PASS) ✅
──────────────────────────────────────────────────────
Component: E11y.configure + Pipeline::Builder#use
Requirement: User config respects declaration order
Status: PASS ✅

Evidence:
- User config calls config.pipeline.use
- Pipeline::Builder#use appends to @middlewares array
- Order preserved: defaults → user additions

Mechanism:
1. Configuration#initialize calls configure_default_pipeline
2. Default middlewares added: [M1, M2, M3, M4, M5, M6]
3. User calls E11y.configure { pipeline.use M7 }
4. M7 appended: [M1, M2, M3, M4, M5, M6, M7]

Declaration Order Respected:
✅ Default middlewares run first (in declared order)
✅ User middlewares run after (in declared order)
✅ No silent reordering
✅ Sequential .use() calls → sequential execution

Example:
```ruby
E11y.configure do |config|
  config.pipeline.use CustomMetrics    # ← Runs 7th
  config.pipeline.use CustomLogging    # ← Runs 8th
end

# Execution order:
# 1. TraceContext (default)
# 2. Validation (default)
# 3. PIIFilter (default)
# 4. AuditSigning (default)
# 5. Sampling (default)
# 6. Routing (default)
# 7. CustomMetrics (user)
# 8. CustomLogging (user)
```

Verdict: PASS ✅ (respects declaration order)
```

### 1.3. Override vs Append Behavior

**Analysis:**
E11y does NOT support **replacing** default middlewares.
It only supports **appending** user middlewares.

**Comparison:**

| Approach | Rails Middleware | E11y Pipeline |
|----------|------------------|---------------|
| **Replace** | ✅ `use NewMiddleware` replaces if exists | ❌ Not supported |
| **Append** | ✅ `use NewMiddleware` | ✅ Supported |
| **Insert before** | ✅ `insert_before(Target, NewMiddleware)` | ❌ Not supported |
| **Insert after** | ✅ `insert_after(Target, NewMiddleware)` | ❌ Not supported |
| **Remove** | ✅ `delete(MiddlewareClass)` | ⚠️ clear() only |

**Finding:**
```
F-100: No Replace/Override Mechanism (INFO) ℹ️
───────────────────────────────────────────────
Component: Pipeline::Builder API
Requirement: Override default middlewares
Status: NOT_SUPPORTED (by design) ⚠️

Issue:
DoD uses term "override" but E11y only supports "append".

Cannot override default middlewares:
```ruby
# CANNOT do:
E11y.configure do |config|
  # Replace default PIIFilter with custom implementation:
  config.pipeline.replace(PIIFilter, MyCustomPIIFilter)  # ❌ Not available
end
```

Current Approach (append-only):
```ruby
E11y.configure do |config|
  # Can only add new middlewares:
  config.pipeline.use MyCustomMiddleware  # ← Appends to end
end
```

Workaround (clear + rebuild):
```ruby
E11y.configure do |config|
  config.pipeline.clear  # ← Remove ALL middlewares
  
  # Rebuild from scratch:
  config.pipeline.use E11y::Middleware::TraceContext
  config.pipeline.use MyCustomPIIFilter  # ← Custom implementation
  config.pipeline.use E11y::Middleware::Routing
end
```

Trade-off:
❌ Less flexible (cannot swap specific middleware)
✅ Safer (prevents accidental removal of critical middlewares)
✅ Simpler API (use + clear, no complex override logic)

Interpretation of DoD:
DoD says "config overrides respect order" → TRUE (append respects order)
DoD doesn't explicitly require "replace" functionality

Verdict: PARTIAL ⚠️ (append works, replace not available)
```

---

## 🔍 AUDIT AREA 2: Silent Reordering Prevention

### 2.1. Zone Validation at Boot Time

**File:** `lib/e11y/pipeline/zone_validator.rb:47-72`

```ruby
def validate_boot_time!
  return if @middlewares.empty?

  previous_zone_index = -1

  @middlewares.each_with_index do |entry, index|
    middleware_zone = entry.middleware_class.middleware_zone
    next unless middleware_zone

    current_zone_index = zone_index(middleware_zone)

    # Validate zone progression (must be non-decreasing)
    if current_zone_index < previous_zone_index
      # ← Zone violation! Raises ZoneOrderError
      raise ZoneOrderError, build_zone_order_error(...)
    end

    previous_zone_index = current_zone_index
  end
end
```

**Finding:**
```
F-101: Zone Violation Detection (PASS) ✅
──────────────────────────────────────────
Component: lib/e11y/pipeline/zone_validator.rb
Requirement: No silent reordering, raise clear error
Status: PASS ✅

Evidence:
- Boot-time validation via validate_boot_time!
- Detects backward zone progression
- Raises ZoneOrderError (not silent)
- Validation called in Builder#validate_zones!

Scenario - User Violates Zone Order:
```ruby
E11y.configure do |config|
  config.pipeline.use CustomSecurityMiddleware  # zone: :security
end

# Default pipeline already has:
# - Routing (zone: :adapters) at position 6

# Result after user config:
# [TraceContext, ..., Routing (:adapters), CustomSecurityMiddleware (:security)]
#                                                   ↑ Zone violation!
# :security (zone 2) cannot follow :adapters (zone 5)

# On boot:
Rails.application.config.after_initialize do
  E11y.configuration.pipeline.validate_zones!
  # → Raises ZoneOrderError!
end
```

Error Message Quality:
✅ Clear error class (ZoneOrderError)
✅ Detailed message (see build_zone_order_error)
✅ Shows offending middlewares
✅ Shows valid zone order
✅ Explains security risk

Verdict: PASS ✅ (no silent reordering, errors caught at boot)
```

### 2.2. Error Message Quality

**File:** `lib/e11y/pipeline/zone_validator.rb:91-107`

```ruby
def build_zone_order_error(current_middleware, current_zone,
                           previous_middleware, previous_zone)
  <<~ERROR
    Invalid middleware zone order detected:

    #{current_middleware.name} (zone: #{current_zone})
    cannot follow
    #{previous_middleware.name} (zone: #{previous_zone})

    Valid zone order: #{ZONE_ORDER.join(' → ')}

    This violation prevents proper middleware execution and may
    create security risks (e.g., PII bypass).

    See ADR-015 §3.4 for middleware zone guidelines.
  ERROR
end
```

**Finding:**
```
F-102: Clear Error Messages (PASS) ✅
──────────────────────────────────────
Component: lib/e11y/pipeline/zone_validator.rb
Requirement: Clear error messages for zone violations
Status: PASS ✅

Evidence:
- Dedicated build_zone_order_error method
- Multi-line formatted error message
- Includes: offending middlewares, zones, valid order, documentation link

Error Message Content:
✅ Shows which middlewares conflict
✅ Shows zone names (not just indices)
✅ Shows valid zone order: pre_processing → security → routing → post_processing → adapters
✅ Explains security risk
✅ Links to ADR-015 documentation

Example Error:
```
Invalid middleware zone order detected:

CustomSecurityMiddleware (zone: security)
cannot follow
E11y::Middleware::Routing (zone: adapters)

Valid zone order: pre_processing → security → routing → post_processing → adapters

This violation prevents proper middleware execution and may
create security risks (e.g., PII bypass).

See ADR-015 §3.4 for middleware zone guidelines.
```

Quality Assessment:
✅ Developer-friendly (clear, actionable)
✅ No jargon (zone names are self-explanatory)
✅ Context-rich (explains "why" not just "what")
✅ Links to documentation

Verdict: EXCELLENT ✅ (clear, actionable error messages)
```

---

## 🔍 AUDIT AREA 3: Middleware Removal

### 3.1. Clear Method

**File:** `lib/e11y/pipeline/builder.rb:137-142`

```ruby
# Clear all registered middlewares.
#
# @return [void]
def clear
  @middlewares.clear
end
```

**Test Coverage:**
**File:** `spec/e11y/pipeline/builder_spec.rb:316-325`

```ruby
describe "#clear" do
  it "removes all middlewares" do
    builder.use pre_processing_middleware
    builder.use security_middleware

    builder.clear

    expect(builder.middlewares).to be_empty
  end
end
```

**Finding:**
```
F-103: Clear Method Exists (PARTIAL) ⚠️
────────────────────────────────────────
Component: lib/e11y/pipeline/builder.rb#clear
Requirement: Remove middleware functionality
Status: PARTIAL ⚠️

Evidence:
- clear() method exists (line 140)
- Removes ALL middlewares (@middlewares.clear)
- Test coverage exists (builder_spec.rb:316-325)

Behavior:
```ruby
builder.use Middleware1
builder.use Middleware2
builder.use Middleware3

builder.clear  # ← Removes all

builder.middlewares  # → []
```

Limitation:
❌ Removes ALL middlewares (nuclear option)
❌ Cannot remove specific middleware

DoD Expectation:
"pipeline.remove(X) works"
→ Implies selective removal, not clear all

Gap:
DoD expects: remove(MiddlewareClass)
E11y provides: clear() (removes all)

Use Case - Selective Removal (NOT SUPPORTED):
```ruby
# Cannot do:
config.pipeline.use Middleware1
config.pipeline.use Middleware2
config.pipeline.use Middleware3

config.pipeline.remove(Middleware2)  # ❌ Not available!
# Expected: [Middleware1, Middleware3]
# Actual: No remove() method
```

Workaround (clear + rebuild):
```ruby
config.pipeline.clear
config.pipeline.use Middleware1
config.pipeline.use Middleware3  # ← Skip Middleware2
```

Verdict: PARTIAL ⚠️ (clear() works, but not selective remove())
```

### 3.2. Remove Method Search

**Search Results:**
```bash
$ grep -r "remove" lib/e11y/pipeline/builder.rb
# 0 matches found ❌

$ grep -r "def remove" lib/e11y/pipeline/
# 0 matches found ❌
```

**Finding:**
```
F-104: No remove(middleware) Method (FAIL) ❌
──────────────────────────────────────────────
Component: lib/e11y/pipeline/builder.rb
Requirement: pipeline.remove(X) works
Status: NOT_IMPLEMENTED ❌

Issue:
DoD requires remove(middleware_class) method,
but no such method exists.

Expected API:
```ruby
class Pipeline::Builder
  def remove(middleware_class)
    @middlewares.reject! { |entry| entry.middleware_class == middleware_class }
    self
  end
end

# Usage:
builder.use Middleware1
builder.use Middleware2
builder.use Middleware3

builder.remove(Middleware2)  # ← Should remove Middleware2

builder.middlewares
# → [Middleware1, Middleware3]
```

Actual API:
Only clear() exists (removes ALL middlewares).

Impact:
❌ Cannot selectively remove middlewares
❌ Must clear + rebuild to exclude specific middleware
❌ No fine-grained control

Verdict: NOT_IMPLEMENTED ❌ (DoD requirement not met)
```

### 3.3. Chain Integrity After Removal

**Analysis:**
Since `remove(middleware)` doesn't exist, cannot test chain integrity after removal.

**Theoretical Test:**
```ruby
it "doesn't break chain after removal" do
  builder.use middleware1
  builder.use middleware2
  builder.use middleware3
  
  builder.remove(middleware2)  # ← Method doesn't exist
  
  pipeline = builder.build(final_app)
  result = pipeline.call({})
  
  # Should execute: middleware1 → middleware3 → final_app
  expect(result[:middleware1]).to be true
  expect(result[:middleware2]).to be_nil  # ← Removed
  expect(result[:middleware3]).to be true
  expect(result[:final]).to be true
end
```

**Finding:**
```
F-105: Chain Integrity After Removal (N/A) ⚠️
───────────────────────────────────────────────
Component: Pipeline chain building
Requirement: Removal doesn't break chain
Status: N/A ⚠️

Issue:
Cannot test because remove() doesn't exist.

Expected Behavior (if remove() implemented):
```ruby
# Before removal:
# Chain: M1 → M2 → M3 → app

# After removal of M2:
# Chain: M1 → M3 → app  # ← Chain intact, M2 skipped
```

Implementation Requirement:
If remove() implemented, must ensure:
1. Remaining middlewares still linked
2. No gaps in chain (M1.@app should point to M3, not M2)
3. build() handles removed entries correctly

Current Workaround (clear + rebuild):
```ruby
config.pipeline.clear
config.pipeline.use M1
config.pipeline.use M3  # ← M2 skipped
# Chain: M1 → M3 → app  # ← Works
```

Verdict: N/A ⚠️ (cannot test non-existent functionality)
```

---

## 🔍 AUDIT AREA 4: Test Coverage

### 4.1. Override Scenario Tests

**Search Results:**
```bash
$ grep -ri "override\|replace\|swap" spec/e11y/pipeline/
# 0 matches found ❌

$ grep -r "E11y.configure.*pipeline.use" spec/
# Found 36 matches (Railtie tests, SLO tests, etc.)
# BUT: No dedicated override scenario tests
```

**Finding:**
```
F-106: No Override Scenario Tests (FAIL) ❌
────────────────────────────────────────────
Component: spec/ directory
Requirement: Verify override scenarios with tests
Status: NOT_TESTED ❌

Issue:
DoD requires tests for override scenarios,
but no dedicated override tests found.

Expected Tests:
```ruby
# spec/e11y/pipeline/override_spec.rb
RSpec.describe "Pipeline Override Scenarios" do
  it "user config appends to default pipeline" do
    E11y.configure do |config|
      config.pipeline.use CustomMiddleware
    end
    
    # Verify default + custom middlewares
    expect(E11y.config.pipeline.middlewares.size).to eq(7)  # 6 default + 1 custom
  end
  
  it "clear + rebuild replaces default pipeline" do
    E11y.configure do |config|
      config.pipeline.clear
      config.pipeline.use CustomMiddleware
    end
    
    # Verify only custom middleware
    expect(E11y.config.pipeline.middlewares.size).to eq(1)
  end
  
  it "zone violation raises error on boot" do
    E11y.configure do |config|
      config.pipeline.use SecurityMiddleware  # zone: :security after :adapters
    end
    
    expect { E11y.config.pipeline.validate_zones! }
      .to raise_error(E11y::Pipeline::ZoneValidator::ZoneOrderError)
  end
end
```

Actual Tests:
- builder_spec.rb tests Builder methods (use, clear, build, validate_zones)
- railtie tests use E11y.configure but don't test override scenarios

Gap:
❌ No integration tests for config override behavior
❌ No tests for default + user pipeline combination
❌ No tests for clear + rebuild scenario

Verdict: NOT_TESTED ❌ (missing override scenario tests)
```

---

## 🎯 Findings Summary

### Implemented Features

```
F-098: Default Pipeline Setup (PASS) ✅
F-099: User Configuration Appends to Default (PASS) ✅
F-101: Zone Violation Detection (PASS) ✅
F-102: Clear Error Messages (PASS) ✅
F-103: Clear Method Exists (PARTIAL) ⚠️
```
**Status:** Core override behavior works

### Not Implemented

```
F-104: No remove(middleware) Method (FAIL) ❌
F-106: No Override Scenario Tests (FAIL) ❌
```
**Status:** 2 DoD requirements not met

### Design Notes

```
F-100: No Replace/Override Mechanism (INFO) ℹ️
F-105: Chain Integrity After Removal (N/A) ⚠️
```
**Status:** Append-only architecture (by design)

---

## 🎯 Conclusion

### Overall Verdict

**Override Behavior Status:** ⚠️ **PARTIAL** (40%)

**What Works:**
- ✅ User config appends to default pipeline (declaration order respected)
- ✅ Zone violations detected (boot-time validation)
- ✅ Clear error messages (ZoneOrderError with details)
- ✅ Clear() method removes all middlewares

**What's Missing:**
- ❌ No remove(middleware_class) for selective removal
- ❌ No replace/swap functionality
- ❌ No override scenario tests

### Design Philosophy

**E11y's Approach: Append-Only + Clear**

**Rationale:**
- Prioritizes safety (prevent accidental removal of critical middlewares)
- Simpler API (use + clear, no complex override/replace logic)
- Zone-based validation prevents misconfigurations

**Comparison with DoD:**

| DoD Assumption | E11y Implementation | Status |
|----------------|---------------------|--------|
| Config overrides respect order | Append respects order | ✅ PASS |
| No silent reordering | Zone validation raises error | ✅ PASS |
| Remove middleware | Only clear() (removes all) | ⚠️ PARTIAL |
| Override tests | No override tests | ❌ FAIL |

**Trade-off Assessment:**

| Aspect | Replace/Remove API | Append-Only + Clear |
|--------|-------------------|---------------------|
| **Flexibility** | ✅ Fine-grained control | ⚠️ Coarse-grained |
| **Safety** | ⚠️ Can remove critical middlewares | ✅ Cannot accidentally break pipeline |
| **Simplicity** | ⚠️ Complex API | ✅ Simple (use + clear) |
| **Common Use Cases** | ✅ Supports all cases | ✅ Supports most cases |

### Gap Analysis

**DoD Compliance: 3/6 requirements met (50%)**

**Functional Gaps:**

1. **Selective Removal (DoD 3a):**
   - Expected: `remove(middleware_class)`
   - Actual: `clear()` only
   - Impact: Must rebuild entire pipeline to exclude one middleware

2. **Override Tests (DoD 3c):**
   - Expected: Tests for override scenarios
   - Actual: No override tests
   - Impact: Override behavior not explicitly verified

**Workarounds:**

For selective removal:
```ruby
E11y.configure do |config|
  config.pipeline.clear
  # Rebuild without unwanted middleware:
  config.pipeline.use MiddlewareA
  # Skip MiddlewareB
  config.pipeline.use MiddlewareC
end
```

---

## 📋 Recommendations

### Priority: MEDIUM

**R-039: Add remove(middleware_class) Method** (MEDIUM)
- **Urgency:** MEDIUM (enhancement, not blocker)
- **Effort:** 1-2 days
- **Impact:** Improves developer experience
- **Action:** Implement selective middleware removal

**Implementation Template (R-039):**
```ruby
# lib/e11y/pipeline/builder.rb
def remove(middleware_class)
  removed = @middlewares.reject! { |entry| entry.middleware_class == middleware_class }
  
  unless removed
    raise ArgumentError, "Middleware #{middleware_class} not found in pipeline"
  end
  
  self
end
```

**R-040: Add Override Scenario Tests** (MEDIUM)
- **Urgency:** MEDIUM
- **Effort:** 1 day
- **Impact:** Verifies override behavior
- **Action:** Create spec/e11y/pipeline/override_spec.rb

**Test Template (R-040):**
```ruby
# spec/e11y/pipeline/override_spec.rb
RSpec.describe "Pipeline Override Scenarios" do
  before { E11y.reset! }
  
  describe "user config appends to default" do
    it "preserves default middlewares" do
      E11y.configure do |config|
        config.pipeline.use CustomMiddleware
      end
      
      expect(E11y.config.pipeline.middlewares.size).to eq(7)  # 6 default + 1 custom
    end
    
    it "respects declaration order" do
      E11y.configure do |config|
        config.pipeline.use CustomMiddleware1
        config.pipeline.use CustomMiddleware2
      end
      
      middlewares = E11y.config.pipeline.middlewares.map(&:middleware_class)
      expect(middlewares[-2]).to eq(CustomMiddleware1)
      expect(middlewares[-1]).to eq(CustomMiddleware2)
    end
  end
  
  describe "clear + rebuild" do
    it "replaces default pipeline" do
      E11y.configure do |config|
        config.pipeline.clear
        config.pipeline.use CustomMiddleware
      end
      
      expect(E11y.config.pipeline.middlewares.size).to eq(1)
      expect(E11y.config.pipeline.middlewares.first.middleware_class).to eq(CustomMiddleware)
    end
  end
  
  describe "zone violations" do
    it "raises error for backward zone progression" do
      E11y.configure do |config|
        config.pipeline.use SecurityMiddleware  # zone: :security after :adapters
      end
      
      expect { E11y.config.pipeline.validate_zones! }
        .to raise_error(E11y::Pipeline::ZoneValidator::ZoneOrderError, /security.*cannot follow.*adapters/)
    end
  end
end
```

---

## 📚 References

### Internal Documentation
- **ADR-015:** Middleware Execution Order
- **ADR-015 §3.4:** Middleware Zones & Modification Rules
- **Implementation:** lib/e11y/pipeline/builder.rb
- **Validation:** lib/e11y/pipeline/zone_validator.rb
- **Tests:** spec/e11y/pipeline/builder_spec.rb

### Related Audits
- **AUDIT-008 FEAT-4934:** Middleware Ordering Guarantees (F-091 to F-097)

---

**Audit Completed:** 2026-01-21  
**Status:** ⚠️ **PARTIAL** (40% - append works, selective removal not available)

**Critical Assessment:**  
E11y's override behavior is **functional but limited**. User configuration correctly appends to the default pipeline with declaration order preserved, and zone violations are caught with clear error messages. However, the lack of selective middleware removal (`remove(middleware_class)`) and absence of override scenario tests represent moderate gaps. The append-only + clear approach is **safe and simple** but less flexible than a full replace/remove API. For most use cases, the current approach is sufficient, but complex pipeline customization requires rebuilding the entire pipeline.

**Auditor Signature:**  
AI Assistant (Claude Sonnet 4.5)  
Audit ID: AUDIT-008

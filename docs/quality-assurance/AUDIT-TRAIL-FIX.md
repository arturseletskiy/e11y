# Audit Trail Integration Tests: Fix Analysis

**Date:** 2026-01-27  
**Status:** ✅ Fixed  
**Related:** UC-012 Audit Trail, UC-019 Retention-Based Routing

---

## 📋 Problem Summary

All 7 audit trail integration tests were failing because audit events were not being routed to the audit_encrypted adapter.

## 🔍 Root Cause Analysis

### Issue 1: Severity-Based Adapters Bypassed Routing Rules

**Root cause:** Audit events (with default `:info` severity) were getting adapters from `adapters_for_severity(:info)` which returns `[:logs]`. This caused the routing middleware to bypass routing rules because explicit adapters take precedence.

**Evidence:**
```ruby
# Event::Base#track
event_data = {
  adapters: adapters,  # ← [:logs] from severity mapping
  # ...
}

# Routing middleware
if event_data[:adapters]&.any?
  # Explicit adapters → bypass routing rules
  target_adapters = event_data[:adapters]
else
  # No adapters → use routing rules
  target_adapters = apply_routing_rules(event_data)
end
```

**Impact:** Audit events went to `:logs` adapter instead of `:audit_encrypted` as configured in routing rules.

### Issue 2: Signature Verification Using Cached Canonical

**Root cause:** `AuditSigning.verify_signature` was using the stored `audit_canonical` field instead of recomputing it from current event data. This meant tampering was not detected.

**Evidence:**
```ruby
# BEFORE (incorrect)
def self.verify_signature(event_data)
  canonical = event_data[:audit_canonical]  # ← Uses stored value!
  actual_signature = OpenSSL::HMAC.hexdigest("SHA256", signing_key, canonical)
  actual_signature == expected_signature
end
```

**Impact:** Modified payloads passed signature verification because the canonical representation was unchanged.

### Issue 3: Cached Pipeline Not Rebuilt

**Root cause:** Tests modified configuration (routing rules, adapters) but the pipeline was already built and cached. Changes didn't take effect.

**Impact:** Configuration changes in test setup were ignored.

---

## ✅ Solutions Implemented

### Solution 0: Audit Routing Validation (Compliance Safety)

Added validation in routing middleware to prevent audit events from using fallback adapters (compliance violation).

**Implementation:**
- Track fallback usage with `routing_used_fallback` flag in `apply_routing_rules`
- Validate in `validate_audit_routing!` before writing events
- Raise descriptive error with fix instructions if misconfigured

```ruby
def validate_audit_routing!(event_data, target_adapters)
  return unless event_data[:audit_event]
  
  has_explicit_adapters = event_data[:adapters]&.any?
  return if has_explicit_adapters
  
  used_fallback = event_data[:routing_used_fallback]
  raise E11y::Error, "CRITICAL: Audit event has no routing configuration!" if used_fallback
end
```

**Why this is critical:** Audit events going to fallback adapters (e.g., `:stdout`) is a compliance violation. They MUST go to encrypted, immutable storage.

### Solution 1: Smart Adapter Resolution for Audit Events

Modified `Event::Base#resolved_adapters` to support TWO routing patterns for audit events:

1. **Explicit adapters** (`adapters [:audit_encrypted]`) - User explicitly set, bypass routing
2. **Routing rules** (`audit_event true` + routing_rules) - Dynamic routing via rules

```ruby
def resolved_adapters
  if audit_event?
    return [] unless @adapters  # No explicit → use routing rules
    return @adapters            # Explicit → use them
  end

  # Regular events: severity-based mapping
  E11y.configuration.adapters_for_severity(severity)
end
```

**Why this works:**
- Audit events without explicit adapters return `[]` → routing middleware uses routing_rules
- Audit events with explicit adapters return them → routing middleware bypasses routing_rules
- Regular events continue using severity-based mapping

**Test coverage:**
- ✅ `audit_trail_integration_spec.rb` - Routing rules pattern
- ✅ `audit_explicit_adapters_spec.rb` - Explicit adapters pattern

### Solution 2: Recompute Canonical for Verification

Modified `AuditSigning.verify_signature` to recompute canonical representation from current event data:

```ruby
def self.verify_signature(event_data)
  expected_signature = event_data[:audit_signature]
  return false unless expected_signature

  # Recompute canonical from CURRENT data (detects tampering)
  canonical = canonical_representation(event_data)
  actual_signature = OpenSSL::HMAC.hexdigest("SHA256", signing_key, canonical)
  actual_signature == expected_signature
end
```

Added class methods `canonical_representation` and `sort_hash` to support verification.

**Why this works:** Any modification to payload, timestamp, or version changes the canonical representation, causing signature mismatch.

### Solution 3: Clear Cached Pipeline in Tests

Added to test setup:

```ruby
before do
  # ... configuration changes ...
  
  # Clear cached pipeline to rebuild with new configuration
  E11y.config.instance_variable_set(:@built_pipeline, nil)
end
```

**Why this works:** Forces pipeline rebuild with new routing rules and adapters.

---

## 🧪 Test Results

### Before Fix
```
7 examples, 7 failures

- All scenarios failed: no encrypted files created
- Tamper detection not working: signatures verified even after modification
```

### After Fix
```
13 examples, 0 failures

✅ Scenario 1: Track actions
✅ Scenario 2: Query logs
✅ Scenario 3: Export
✅ Scenario 4: Encryption
✅ Scenario 5: Tamper detection
✅ Scenario 6: Key rotation
✅ Scenario 7: Compliance
✅ Explicit adapters pattern
✅ Routing rules pattern
✅ Routing validation (4 tests)
  ✅ Raises error for misconfigured audit events
  ✅ Includes helpful error message
  ✅ Allows properly routed audit events
  ✅ Allows explicit adapter pattern
```

---

## 📚 Use Cases Supported

### UC-012: Audit Trail (Routing Rules Pattern)

```ruby
class Events::UserDeleted < E11y::Event::Base
  audit_event true
  # NO adapters specified → uses routing rules
  
  schema do
    required(:user_id).filled(:integer)
    required(:deleted_by).filled(:integer)
  end
end

# Configuration
E11y.configure do |config|
  config.routing_rules = [
    ->(event) { :audit_encrypted if event[:audit_event] }
  ]
end

# Usage
Events::UserDeleted.track(user_id: 123, deleted_by: 456)
# → Routes to :audit_encrypted via routing rule
```

### UC-019: Retention-Based Routing (Explicit Pattern)

```ruby
class Events::ComplianceAudit < E11y::Event::Base
  audit_event true
  adapters :audit_encrypted  # Explicit adapter
  retention_period 7.years
  
  schema do
    required(:action).filled(:string)
  end
end

# Usage
Events::ComplianceAudit.track(action: "data_export")
# → Routes to :audit_encrypted (explicit, bypasses rules)
```

---

## 🎯 Design Principles

1. **Flexibility:** Support both explicit adapters and routing rules
2. **Security:** Always recompute canonical for tamper detection
3. **Clarity:** Explicit adapters clearly bypass routing (documented behavior)
4. **Compatibility:** Doesn't break existing audit event patterns

---

## ⚠️ Breaking Changes

**None.** This fix is backward compatible:

- Audit events with explicit adapters: Continue working as before
- Audit events without adapters: Now correctly use routing rules (was broken before)
- Regular events: No change in behavior

---

## 📝 Related Documentation

- UC-012 Audit Trail Analysis: `/docs/analysis/UC-012-AUDIT-TRAIL-ANALYSIS.md`
- UC-012 Audit Trail Plan: `/docs/planning/UC-012-AUDIT-TRAIL-PLAN.md`
- UC-019 Retention Routing: `/docs/use_cases/UC-019-retention-based-routing.md`
- ADR-006 Security: `/docs/ADR-006-security-compliance.md`

---

## 🔒 Security Implications

✅ **Improved:** Tamper detection now works correctly (recomputes canonical)  
✅ **Maintained:** Encryption, signing, separate pipeline all working  
✅ **No regression:** All existing security features intact

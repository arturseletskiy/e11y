# ADR-015: Middleware Execution Order

**Status:** Stable  
**Date:** January 13, 2026  
**Covers:** Pipeline execution order, event versioning integration  
**Depends On:** ADR-001 (Architecture), ADR-012 (Event Evolution)

---

## 📋 Table of Contents

1. [Context & Problem](#1-context--problem)
2. [Decision](#2-decision)
3. [Correct Order](#3-correct-order)
   - 3.1. Pipeline Flow
   - 3.2. Why Each Middleware Needs Original Class Name
   - 3.3. Audit Events in Single Pipeline (C01 Resolution) ⚠️ CRITICAL
     - 3.3.1. The Problem: PII Filtering Breaks Audit Trail
     - 3.3.2. Decision: Two Pipeline Configurations
     - 3.3.3. Declaring Audit Events
     - 3.3.4. Pipeline Configuration
     - 3.3.5. Audit Signing Middleware Implementation
     - 3.3.6. Encrypted Audit Adapter (C01 Requirement)
     - 3.3.7. Usage Examples
     - 3.3.8. Trade-offs & Security (C01)
   - 3.4. Middleware Zones & Modification Rules (C19 Resolution) ⚠️ CRITICAL
     - 3.4.1. The Problem: Uncontrolled Middleware Modifications
     - 3.4.2. Decision: Middleware Zones
     - 3.4.3. Zone-Based Configuration
     - 3.4.4. Custom Middleware Constraints
     - 3.4.5. Zone Validation (Runtime Checks)
     - 3.4.6. Warning System for Violations
     - 3.4.7. Examples: Safe vs Unsafe Middleware
     - 3.4.8. Trade-offs & Guidelines (C19)
4. [Wrong Order Example](#4-wrong-order-example)
5. [Real-World Example](#5-real-world-example)
6. [Implementation Checklist](#6-implementation-checklist)
7. [See Also](#7-see-also)

---

## 1. Context & Problem

### 1.1. Problem Statement

**Versioning Middleware normalizes event names for adapters, but when should this happen?**

```ruby
# Events::OrderPaidV2.track(...)
# Should validation use "Events::OrderPaidV2" or "Events::OrderPaid"?
# Should PII filtering use V2 rules or V1 rules?
# When do we normalize the name?
```

**Wrong placement breaks business logic:**
- ❌ Too early → Validation fails (can't find V2 schema)
- ❌ Too early → PII filtering uses wrong rules
- ❌ Too early → Rate limiting uses wrong limits

### 1.2. Key Insight

> **Versioning = Cosmetic normalization for external systems**  
> **All business logic MUST use original class name**

---

## 2. Decision

**Versioning Middleware MUST be LAST (before routing to adapters)**

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  config.middleware.use E11y::Middleware::TraceContext      # 1
  config.middleware.use E11y::Middleware::Validation        # 2
  config.middleware.use E11y::Middleware::PIIFiltering      # 3
  config.middleware.use E11y::Middleware::RateLimiting      # 4
  config.middleware.use E11y::Middleware::Sampling          # 5
  config.middleware.use E11y::Middleware::Versioning        # 6 ← LAST!
  config.middleware.use E11y::Middleware::Routing           # 7
end
```

---

## 3. Correct Order

### 3.1. Pipeline Flow

```
Events::OrderPaidV2.track(order_id: 123, amount: 99.99)
  ↓
1. TraceContext    → Add trace_id, span_id, timestamp
                     event_name = "Events::OrderPaidV2" (original)
  ↓
2. Validation      → Uses Events::OrderPaidV2 schema ✅
                     event_name = "Events::OrderPaidV2" (original)
  ↓
3. PII Filtering   → Uses Events::OrderPaidV2 PII rules ✅
                     event_name = "Events::OrderPaidV2" (original)
  ↓
4. Rate Limiting   → Checks limit for "Events::OrderPaidV2" ✅
                     event_name = "Events::OrderPaidV2" (original)
  ↓
5. Sampling        → Checks sample rate for "Events::OrderPaidV2" ✅
                     event_name = "Events::OrderPaidV2" (original)
  ↓
6. Versioning      → Normalize: "Events::OrderPaid"
   (LAST!)            Add v: 2 to payload
                     event_name = "Events::OrderPaid" (normalized)
  ↓
7. Routing         → Route to buffer
                     event_name = "Events::OrderPaid" (normalized)
  ↓
Adapters           → Receive normalized name
                     event_name = "Events::OrderPaid"
                     payload: { v: 2, order_id: 123, ... }
```

### 3.2. Why Each Middleware Needs Original Class Name

| Middleware | Needs Original? | Why? |
|------------|----------------|------|
| **TraceContext** | No | Just adds trace_id, doesn't care about class |
| **Validation** | ✅ Yes | Schema is attached to specific class (V2 ≠ V1) |
| **PIIFiltering** | ✅ Yes | PII rules may differ between V1 and V2 |
| **RateLimiting** | ✅ Yes | Rate limits may differ between V1 and V2 |
| **Sampling** | ✅ Yes | Sample rates may differ between V1 and V2 |
| **Versioning** | No | Normalizes for adapters (cosmetic change) |
| **Routing** | No | Routes based on severity, not class name |
| **Adapters** | No | Prefer normalized name (easier querying) |

---

## 4. Wrong Order Example

### 4.1. Versioning First (WRONG!)

```ruby
# ❌ WRONG ORDER!
config.middleware.use E11y::Middleware::Versioning        # 1 ← Too early!
config.middleware.use E11y::Middleware::Validation        # 2
config.middleware.use E11y::Middleware::PIIFiltering      # 3
config.middleware.use E11y::Middleware::RateLimiting      # 4
config.middleware.use E11y::Middleware::Sampling          # 5
```

### 4.2. What Breaks

```ruby
Events::OrderPaidV2.track(...)
  ↓
1. Versioning: Normalize "Events::OrderPaidV2" → "Events::OrderPaid"
  ↓
2. Validation: ❌ Can't find schema for "Events::OrderPaid" (was V2!)
  ↓
3. PII Filtering: ❌ Uses V1 rules instead of V2 rules!
  ↓
4. Rate Limiting: ❌ Uses V1 limit instead of V2 limit!
  ↓
5. Sampling: ❌ Uses V1 sample rate instead of V2 rate!
```

---

## 5. Real-World Example

```ruby
# V1: Old version (production)
class Events::OrderPaid < E11y::Event::Base
  schema do
    required(:order_id).filled(:integer)
    required(:amount).filled(:float)
    # No currency field!
  end
  
  pii_filtering do
    masks :email  # V1: masks email
  end
  
  adapters :loki, :sentry
  severity :info
end

# V2: New version (A/B test, 10% traffic)
class Events::OrderPaidV2 < E11y::Event::Base
  schema do
    required(:order_id).filled(:integer)
    required(:amount).filled(:float)
    required(:currency).filled(:string)  # ← NEW FIELD!
  end
  
  pii_filtering do
    hashes :email  # V2: hashes email (different rule!)
  end
  
  adapters :loki, :sentry
  severity :info
end

# Rate limiting config
E11y.configure do |config|
  config.rate_limiting do
    per_event 'Events::OrderPaid', limit: 1000, window: 1.second  # V1: high limit
    per_event 'Events::OrderPaidV2', limit: 100, window: 1.second # V2: low limit (A/B test)
  end
end

# Pipeline execution:
Events::OrderPaidV2.track(order_id: 123, amount: 99.99, currency: 'USD')
  ↓
1. Validation: ✅ Uses V2 schema (checks currency field exists)
2. PII Filtering: ✅ Uses V2 rules (hashes email, not masks)
3. Rate Limiting: ✅ Uses V2 limit (100 req/sec, not 1000)
4. Sampling: ✅ Uses V2 sample rate (if configured differently)
5. Versioning: Normalize to "Events::OrderPaid", add v: 2
6. Routing: Route to main buffer
  ↓
Loki receives:
{
  event_name: "Events::OrderPaid",  ← Normalized!
  v: 2,                              ← Version explicit
  order_id: 123,
  amount: 99.99,
  currency: "USD",
  email: "sha256:abc123..."          ← Hashed (V2 rule)
}

# Easy querying in Loki:
# All versions: {event_name="Events::OrderPaid"}
# Only V2: {event_name="Events::OrderPaid", v="2"}
# Only V1: {event_name="Events::OrderPaid"} |= "" != "v"
```

---

## 6. Implementation Checklist

- [ ] Versioning Middleware is **LAST** (before Routing)
- [ ] All business logic middleware uses **ORIGINAL class name**
- [ ] Adapters receive **NORMALIZED event_name**
- [ ] `v:` field is added **only if version > 1**
- [ ] Rate limits are configured **per original class** (if differ)
- [ ] PII rules are configured **per original class** (if differ)
- [ ] Sampling rules are configured **per original class** (if differ)
- [ ] Metrics track **both** normalized name and version
- [ ] Audit events skip PII filtering via conditional logic (C01 - see §3.3, single pipeline)
- [ ] Audit events stored in encrypted adapter (C01 requirement)

---

## 3.3. Audit Events in Single Pipeline (C01 Resolution)

> **⚠️ CRITICAL: C01 Conflict Resolution - PII Filtering × Audit Trail Signing**  
> **See:** [CONFLICT-ANALYSIS.md C01](researches/CONFLICT-ANALYSIS.md#c01-pii-filtering--audit-trail-signing) for detailed analysis  
> **Problem:** PII filtering before signing breaks non-repudiation (auditors can't verify original event)  
> **Solution:** Single pipeline for all events. Audit events get conditional skip in PIIFilter via `contains_pii false` in AuditEvent preset (:no_pii = pass-through). No separate pipeline — no need.

### 3.3.1. The Problem: PII Filtering Breaks Audit Trail

**Standard pipeline:**
```ruby
Event.track(email: 'user@example.com', ip: '192.168.1.1')
  ↓
PII Filtering → { email: '[FILTERED]', ip: '[FILTERED]' }
  ↓
Audit Signing → HMAC-SHA256('[FILTERED]' data)
  ↓
Storage

# ❌ Problem: Signature is based on FILTERED data!
# Auditor cannot verify original event was not tampered with
# Non-repudiation requirement VIOLATED
```

**Legal Requirements:**
- **Non-repudiation:** Must prove event content hasn't been altered since creation
- **Audit trail:** Must maintain cryptographic chain of custody
- **Forensics:** Must be able to reconstruct exact event that occurred

### 3.3.2. Decision: One Pipeline with Conditional Skip

**All events go through a single pipeline.** Audit events get conditional skip in middleware:

```
1. TraceContext    → Add trace_id, span_id, timestamp
2. Validation      → Schema validation (original class)
3. PIIFiltering    → Audit: skip (contains_pii false → :no_pii). Standard: filter PII ✅
4. RateLimiting    → Audit: can skip (event_data[:audit_event]). Standard: rate limit
5. Sampling        → Audit: sample_rate 1.0 (preset). Standard: adaptive
6. Versioning      → Normalize event_name (LAST)
7. Routing         → Route to buffer / audit buffer
```

**AuditEvent preset:** `contains_pii false` → PIIFilter :no_pii = pass-through, original data preserved for signing.

### 3.3.3. Declaring Audit Events

**Event Class Flag:**
```ruby
# Audit event - conditional skip in pipeline
class Events::PermissionChanged < E11y::Event::Base
  include E11y::Presets::AuditEvent  # audit_event true, contains_pii false
  # Auto-set: retention = E11y.config.audit_retention (configurable!)
  #           rate_limiting = false (LOCKED!)
  #           sampling = false (LOCKED!)
  
  schema do
    required(:user_id).filled(:string)
    required(:admin_email).filled(:string)  # ← PII preserved for audit!
    required(:changed_by).filled(:string)
    required(:old_role).filled(:string)
    required(:new_role).filled(:string)
    required(:timestamp).filled(:time)
  end
  
  # Audit-specific configuration
  adapters :audit_encrypted  # ← MUST use encrypted storage
  severity :warn
  version 1
end

# Standard event - full pipeline
class Events::PageView < E11y::Event::Base
  # audit_event false (default)
  
  schema do
    required(:user_id).filled(:string)
    required(:email).filled(:string)  # ← PII will be filtered
    required(:page_url).filled(:string)
  end
  
  pii_filtering do
    masks :email  # Applied early in pipeline
  end
  
  adapters :loki, :elasticsearch
  severity :info
  version 1
end
```

### 3.3.4. Pipeline Configuration

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  # Single pipeline for all events (audit and standard)
  config.pipeline.use E11y::Middleware::TraceContext      # 1
  config.pipeline.use E11y::Middleware::Validation        # 2
  config.pipeline.use E11y::Middleware::PIIFiltering      # 3  # Audit: skip (contains_pii false)
  config.pipeline.use E11y::Middleware::RateLimiting      # 4
  config.pipeline.use E11y::Middleware::Sampling          # 5
  config.pipeline.use E11y::Middleware::AuditSigning      # 6  # Pass-through for non-audit
  config.pipeline.use E11y::Middleware::Versioning        # 7  # Last before Routing
  config.pipeline.use E11y::Middleware::Routing           # 8
  
  # Audit event configuration
  config.audit_events do
    enabled true
    
    # Signing configuration (HMAC-SHA256)
    signing do
      algorithm :hmac_sha256
      secret_key ENV['E11Y_AUDIT_SECRET_KEY']  # ← Must be set!
      
      # Include all fields in signature
      include_fields :all
      
      # Add signature metadata
      add_signature_metadata true  # timestamp, key_id, algorithm
    end
    
    # Storage requirement (C01)
    storage do
      encrypted true  # ← MANDATORY for audit events with PII
      adapter :audit_encrypted  # Use encrypted storage adapter
    end
  end
end
```

### 3.3.5. Audit Signing Middleware Implementation

```ruby
module E11y
  module Middleware
    class AuditSigning < Base
      def call(event_data)
        # Only sign audit events
        unless event_data[:audit_event]
          return @app.call(event_data)
        end
        
        # Generate signature payload (includes ALL fields, including PII)
        signature_payload = build_signature_payload(event_data)
        
        # Calculate HMAC-SHA256 signature
        secret_key = Config.audit_events.signing.secret_key
        signature = OpenSSL::HMAC.hexdigest(
          'SHA256',
          secret_key,
          signature_payload
        )
        
        # Add signature to event
        event_data[:audit_signature] = {
          value: signature,
          algorithm: 'HMAC-SHA256',
          timestamp: Time.now.utc.iso8601(3),
          key_id: Config.audit_events.signing.key_id || 'default',
          payload_hash: Digest::SHA256.hexdigest(signature_payload)
        }
        
        # Mark as signed
        event_data[:audit_signed] = true
        
        # Metrics
        Metrics.increment('e11y.audit.events_signed')
        
        @app.call(event_data)
      end
      
      private
      
      def build_signature_payload(event_data)
        # Canonical representation for signature
        # (sorted keys, consistent JSON formatting)
        payload_fields = {
          event_name: event_data[:event_name],
          event_version: event_data[:event_version],
          timestamp: event_data[:timestamp].iso8601(3),
          trace_id: event_data[:trace_id],
          payload: event_data[:payload]
        }
        
        # Sort keys for deterministic signature
        JSON.generate(payload_fields.deep_sort_by_key)
      end
    end
  end
end
```

### 3.3.6. Encrypted Audit Adapter (C01 Requirement)

**Why Encryption is Mandatory:**
- Audit events contain **PII** (not filtered)
- Signature is on **original data** (including PII)
- Storage must protect PII at rest (GDPR compliance)

```ruby
# lib/e11y/adapters/audit_encrypted_adapter.rb
module E11y
  module Adapters
    class AuditEncryptedAdapter < Base
      def initialize(storage_path:, encryption_key:)
        @storage_path = storage_path
        @cipher = OpenSSL::Cipher.new('AES-256-GCM')
        @encryption_key = encryption_key
      end
      
      def write_batch(events)
        events.each do |event_data|
          # Verify audit signature
          unless verify_signature(event_data)
            Rails.logger.error "[E11y] Audit signature verification failed: #{event_data[:event_name]}"
            Metrics.increment('e11y.audit.signature_verification_failed')
            next
          end
          
          # Encrypt event (AES-256-GCM)
          encrypted_payload = encrypt(event_data)
          
          # Store encrypted event
          File.open("#{@storage_path}/audit_#{event_data[:trace_id]}.enc", 'wb') do |f|
            f.write(encrypted_payload)
          end
          
          Metrics.increment('e11y.audit.events_stored')
        end
      end
      
      private
      
      def encrypt(event_data)
        @cipher.encrypt
        @cipher.key = @encryption_key
        iv = @cipher.random_iv
        
        encrypted_data = @cipher.update(JSON.generate(event_data)) + @cipher.final
        auth_tag = @cipher.auth_tag
        
        # Prepend IV and auth_tag for decryption
        [iv, auth_tag, encrypted_data].map { |x| [x].pack('m0') }.join("\n")
      end
      
      def verify_signature(event_data)
        signature_data = event_data[:audit_signature]
        return false unless signature_data
        
        # Rebuild signature payload
        payload = build_signature_payload(event_data)
        
        # Verify signature
        expected_sig = OpenSSL::HMAC.hexdigest(
          'SHA256',
          Config.audit_events.signing.secret_key,
          payload
        )
        
        signature_data[:value] == expected_sig
      end
    end
  end
end
```

### 3.3.7. Usage Examples

**Tracking Audit Event:**
```ruby
# Audit event - PII preserved, signature added
Events::PermissionChanged.track(
  user_id: 'user-123',
  admin_email: 'admin@company.com',  # ← PII preserved!
  changed_by: 'admin-456',
  old_role: 'viewer',
  new_role: 'editor',
  resource_type: 'document',
  resource_id: 'doc-789'
)

# Pipeline execution:
# 1. TraceContext → Add trace_id: 'abc-def-123'
# 2. Validation → Schema check ✅
# 3. AuditSigning → Calculate HMAC-SHA256 signature on ORIGINAL data
# 4. Versioning → Normalize event_name
# 5. AuditRouting → Route to audit buffer
# 6. AuditEncryptedAdapter → Encrypt and store

# Stored event (encrypted):
{
  event_name: "permission.changed",
  event_version: 1,
  trace_id: "abc-def-123",
  timestamp: "2026-01-14T10:30:45.123Z",
  payload: {
    user_id: "user-123",
    admin_email: "admin@company.com",  # ← PII in signed payload!
    changed_by: "admin-456",
    old_role: "viewer",
    new_role: "editor"
  },
  audit_signature: {
    value: "a1b2c3d4e5f6...",  # ← Signature on ORIGINAL data
    algorithm: "HMAC-SHA256",
    timestamp: "2026-01-14T10:30:45.123Z",
    key_id: "default",
    payload_hash: "sha256:abc123..."
  }
}
```

**Verifying Audit Trail:**
```ruby
# Forensic verification
audit_event = E11y::AuditLog.find_by(trace_id: 'abc-def-123')

# 1. Decrypt event
decrypted_event = E11y::AuditEncryptedAdapter.decrypt(audit_event.encrypted_payload)

# 2. Verify signature
signature_valid = E11y::AuditSigning.verify(
  decrypted_event,
  secret_key: ENV['E11Y_AUDIT_SECRET_KEY']
)

# 3. Reconstruct payload
if signature_valid
  puts "✅ Audit event verified:"
  puts "   Original email: #{decrypted_event[:payload][:admin_email]}"
  puts "   Signature: VALID"
  puts "   Timestamp: #{decrypted_event[:audit_signature][:timestamp]}"
else
  puts "❌ Audit event signature INVALID - event may have been tampered!"
end
```

### 3.3.8. Trade-offs & Security (C01)

**Trade-offs:**

| Aspect | Pro | Con | Mitigation |
|--------|-----|-----|------------|
| **Non-repudiation** | ✅ Signature on original data | ⚠️ PII in audit events | Use encrypted storage adapter |
| **Legal compliance** | ✅ Meets audit requirements | ⚠️ Conditional logic in middleware | Clear documentation |
| **PII protection** | ✅ Standard events filtered | ⚠️ Audit events not filtered | Restrict access to audit logs |
| **Performance** | ✅ No PII filter overhead | ⚠️ Signing + encryption overhead | Audit events are rare (<1%) |

**Security Requirements (C01):**

1. **Encrypted Storage (Mandatory):**
   - All audit events MUST be stored encrypted (AES-256-GCM)
   - Encryption keys managed via secure key management (AWS KMS, HashiCorp Vault, etc.)
   - Access to audit logs restricted to authorized personnel only

2. **Access Control:**
   - Audit log access requires multi-factor authentication (MFA)
   - All audit log access must be logged (audit the auditors!)
   - Role-based access control (RBAC) for audit log decryption

3. **Key Rotation:**
   - Signing keys rotated quarterly (or per company policy)
   - Old signatures remain valid (use key_id to identify key version)
   - Re-signing not required after key rotation (signatures remain valid)

**Monitoring (Critical for C01):**

```ruby
# Prometheus/Yabeda metrics
Yabeda.configure do
  group :e11y_audit do
    counter :events_signed, comment: 'Audit events signed'
    counter :events_stored, comment: 'Audit events stored (encrypted)'
    counter :signature_verification_failed, comment: 'Signature verification failures'
    counter :encryption_errors, comment: 'Encryption failures'
    
    gauge :audit_log_size_bytes, comment: 'Total size of audit logs'
  end
end

# Alert rules (Grafana)
# Alert: Signature verification failures > 0 (investigate immediately!)
# Alert: Encryption errors > 0 (check key configuration)
# Alert: Audit log size > 10 GB (consider archival)
```

**Related Conflicts:**
- **C07:** DLQ replay with PII filtering (see ADR-013)
- **C19:** Pipeline modification rules (see §3.4 below)

---

## 3.4. Middleware Zones & Modification Rules (C19 Resolution)

> **⚠️ CRITICAL: C19 Conflict Resolution - Custom Middleware × Pipeline Integrity**  
> **See:** [CONFLICT-ANALYSIS.md C19](researches/CONFLICT-ANALYSIS.md#c19-custom-middleware--pipeline-modification) for detailed analysis  
> **Problem:** Custom middleware can bypass PII filtering or undo security modifications  
> **Solution:** Define middleware zones with clear modification constraints

### 3.4.1. The Problem: Uncontrolled Middleware Modifications

**Scenario - Accidental PII Bypass:**
```ruby
# Developer adds custom middleware
config.middleware.insert_after :pii_filtering, CustomEnrichmentMiddleware

class CustomEnrichmentMiddleware
  def call(event_data)
    # Accidentally adds PII AFTER filtering!
    event_data[:payload][:user_email] = Current.user.email  # ← PII leak!
    
    @app.call(event_data)
  end
end

# Pipeline execution:
# 1. PIIFiltering → Removes :email field ✅
# 2. CustomEnrichment → Adds :user_email field ❌ PII bypass!
# 3. Adapters → Receive event with unfiltered PII!
```

**Scenario - Modification Conflicts:**
```ruby
# Multiple middlewares modifying same fields
# 1. PII Filtering → email: '[FILTERED]'
# 2. Trace Context → adds trace_id
# 3. Payload Minimization → abbreviates keys (email → em)
# 4. Custom Middleware → restores original email (?!)

# Result: Cascading modifications break invariants!
```

### 3.4.2. Decision: Middleware Zones

Middlewares are grouped into **zones** with clear **modification rules**:

```
┌─────────────────────────────────────────────────────────┐
│ ZONE 1: PRE-PROCESSING                                  │
│ ├─ Validation        ← Can REJECT event                 │
│ └─ Schema Enrichment ← Can ADD required fields          │
│                                                          │
│ Rules:                                                   │
│ - Can add missing fields (defaults, timestamps)         │
│ - Can reject invalid events (raise error)               │
│ - Cannot modify PII (too early!)                        │
└─────────────────────────────────────────────────────────┘
             ↓
┌─────────────────────────────────────────────────────────┐
│ ZONE 2: SECURITY (CRITICAL!)                            │
│ └─ PII Filtering     ← Can MODIFY sensitive fields      │
│                                                          │
│ Rules:                                                   │
│ - LAST chance to touch PII fields                       │
│ - NO middleware after this can modify/add PII           │
│ - Custom middleware CANNOT run after PII filtering      │
└─────────────────────────────────────────────────────────┘
             ↓
┌─────────────────────────────────────────────────────────┐
│ ZONE 3: ROUTING                                          │
│ ├─ Rate Limiting     ← Can DROP event                   │
│ └─ Sampling          ← Can DROP event                   │
│                                                          │
│ Rules:                                                   │
│ - Can inspect event (read-only)                         │
│ - Can decide to drop event (return early)               │
│ - Cannot modify payload                                 │
└─────────────────────────────────────────────────────────┘
             ↓
┌─────────────────────────────────────────────────────────┐
│ ZONE 4: POST-PROCESSING                                  │
│ ├─ Trace Context     ← Can ADD non-PII tracing fields   │
│ ├─ Versioning        ← Can NORMALIZE event_name         │
│ └─ Minimization      ← Can ABBREVIATE keys (last step!) │
│                                                          │
│ Rules:                                                   │
│ - Can add metadata (trace_id, timestamps)               │
│ - Can transform structure (abbreviate keys)             │
│ - Cannot add PII (already filtered!)                    │
└─────────────────────────────────────────────────────────┘
             ↓
┌─────────────────────────────────────────────────────────┐
│ ZONE 5: ADAPTERS                                         │
│ ├─ Routing           ← Route to buffer                   │
│ └─ Adapters          ← Write to external systems        │
│                                                          │
│ Rules:                                                   │
│ - Read-only access to event                             │
│ - Cannot modify (too late!)                             │
└─────────────────────────────────────────────────────────┘
```

### 3.4.3. Zone-Based Configuration

```ruby
# config/initializers/e11y.rb
E11y.configure do |config|
  # ZONE 1: Pre-processing
  config.pipeline.zone(:pre_processing) do
    use E11y::Middleware::TraceContext         # Add trace_id, timestamp
    use E11y::Middleware::Validation           # Schema validation
  end
  
  # ZONE 2: Security (CRITICAL - PII handled here!)
  config.pipeline.zone(:security) do
    use E11y::Middleware::PIIFiltering         # ← LAST PII touchpoint!
  end
  
  # ZONE 3: Routing (read-only decision making)
  config.pipeline.zone(:routing) do
    use E11y::Middleware::RateLimiting         # Can drop events
    use E11y::Middleware::Sampling             # Can drop events
  end
  
  # ZONE 4: Post-processing (metadata enrichment)
  config.pipeline.zone(:post_processing) do
    use E11y::Middleware::Versioning           # Normalize event_name
    use E11y::Middleware::PayloadMinimization  # Abbreviate keys (last!)
  end
  
  # ZONE 5: Adapters (delivery)
  config.pipeline.zone(:adapters) do
    use E11y::Middleware::Routing              # Buffer routing
  end
end
```

### 3.4.4. Custom Middleware Constraints

**Safe Placement Options:**

```ruby
# ✅ SAFE: Add custom middleware in pre-processing zone
config.pipeline.zone(:pre_processing) do
  use E11y::Middleware::Validation
  use MyCustomEnrichmentMiddleware  # ← Before PII filtering (can add fields)
end

# ✅ SAFE: Add custom middleware in post-processing zone
config.pipeline.zone(:post_processing) do
  use E11y::Middleware::Versioning
  use MyCustomMetadataMiddleware    # ← After PII filtering (metadata only!)
end

# ❌ UNSAFE: Cannot add middleware AFTER PII filtering but BEFORE post-processing
# This would create a PII bypass window!
```

**Custom Middleware Template:**

```ruby
class MyCustomEnrichmentMiddleware < E11y::Middleware
  # Declare which zone this middleware belongs to
  middleware_zone :pre_processing  # or :post_processing
  
  # Declare what modifications this middleware makes
  modifies_fields :custom_metadata, :enrichment_data
  
  def call(event_data)
    # Validate zone constraints
    validate_zone_rules!(event_data)
    
    # Add custom fields (pre-processing zone)
    if middleware_zone == :pre_processing
      event_data[:payload][:custom_metadata] = fetch_metadata(event_data)
    end
    
    # Add metadata (post-processing zone)
    if middleware_zone == :post_processing
      event_data[:payload][:enrichment_timestamp] = Time.now.utc.iso8601(3)
      
      # ⚠️ Cannot add PII fields here!
      validate_no_pii_fields!(event_data[:payload])
    end
    
    @app.call(event_data)
  end
  
  private
  
  def validate_zone_rules!(event_data)
    # Ensure no PII fields added in post-processing zone
    if middleware_zone == :post_processing
      pii_patterns = Config.pii_filtering.field_patterns
      
      event_data[:payload].keys.each do |key|
        if pii_patterns.any? { |pattern| key.to_s.match?(pattern) }
          raise E11y::ZoneViolationError, 
            "PII field '#{key}' cannot be added in post-processing zone! " \
            "PII filtering already completed."
        end
      end
    end
  end
end
```

### 3.4.5. Zone Validation (Runtime Checks)

```ruby
module E11y
  class Pipeline
    class << self
      # Validate zone constraints at boot time
      def validate_zones!
        current_zone = :pre_processing
        
        @middlewares.each do |middleware_class, args, options|
          declared_zone = middleware_class.middleware_zone
          
          # Check zone progression
          unless valid_zone_transition?(current_zone, declared_zone)
            raise E11y::InvalidPipelineError,
              "Invalid middleware order: #{middleware_class} (zone: #{declared_zone}) " \
              "cannot follow zone #{current_zone}. " \
              "Valid order: pre_processing → security → routing → post_processing → adapters"
          end
          
          current_zone = declared_zone
        end
      end
      
      private
      
      def valid_zone_transition?(from_zone, to_zone)
        zone_order = {
          pre_processing: 1,
          security: 2,
          routing: 3,
          post_processing: 4,
          adapters: 5
        }
        
        zone_order[to_zone] >= zone_order[from_zone]
      end
    end
  end
end

# Run at Rails boot
Rails.application.config.after_initialize do
  E11y::Pipeline.validate_zones!
end
```

### 3.4.6. Warning System for Violations

```ruby
# Development/staging environment warnings
if Rails.env.development? || Rails.env.staging?
  E11y.configure do |config|
    config.pipeline.enable_zone_warnings = true
    
    # Warn if custom middleware added after PII filtering
    config.pipeline.on_zone_violation do |violation|
      Rails.logger.warn <<~WARNING
        [E11y] ⚠️ Pipeline Zone Violation Detected!
        
        Middleware: #{violation.middleware_class}
        Declared Zone: #{violation.declared_zone}
        Current Zone: #{violation.actual_zone}
        
        Problem: This middleware runs after PII filtering but modifies payload fields.
        Risk: PII bypass, security violation, GDPR non-compliance.
        
        Fix: Move middleware to pre_processing zone or ensure it only adds non-PII metadata.
        
        Documentation: See ADR-015 §3.4 Middleware Zones
      WARNING
      
      # In production: Raise error (fail fast!)
      raise violation if Rails.env.production?
    end
  end
end
```

### 3.4.7. Examples: Safe vs Unsafe Middleware

**❌ UNSAFE: PII Bypass**
```ruby
class UnsafeMiddleware < E11y::Middleware
  def call(event_data)
    # ❌ BAD: Adds PII after filtering!
    event_data[:payload][:user_email] = Current.user.email
    
    @app.call(event_data)
  end
end

# If placed after PIIFiltering middleware:
# → PII bypass! Email not filtered!
# → GDPR violation!
```

**✅ SAFE: Pre-Processing Enrichment**
```ruby
class SafeEnrichmentMiddleware < E11y::Middleware
  middleware_zone :pre_processing
  
  def call(event_data)
    # ✅ GOOD: Adds fields BEFORE PII filtering
    event_data[:payload][:request_path] = Current.request.path
    event_data[:payload][:user_agent] = Current.request.user_agent
    
    # These fields will be filtered by PIIFiltering middleware if needed
    @app.call(event_data)
  end
end
```

**✅ SAFE: Post-Processing Metadata**
```ruby
class SafeMetadataMiddleware < E11y::Middleware
  middleware_zone :post_processing
  
  def call(event_data)
    # ✅ GOOD: Adds non-PII metadata AFTER PII filtering
    event_data[:payload][:processing_duration_ms] = calculate_duration(event_data)
    event_data[:payload][:pipeline_version] = E11y::VERSION
    
    # ✅ No PII added - safe!
    @app.call(event_data)
  end
end
```

### 3.4.8. Trade-offs & Guidelines (C19)

**Trade-offs:**

| Aspect | Pro | Con | Mitigation |
|--------|-----|-----|------------|
| **Safety** | ✅ Prevents PII bypass | ⚠️ More restrictive API | Clear documentation |
| **Flexibility** | ⚠️ Less freedom for custom middleware | ✅ Forces correct patterns | Two zones: pre/post processing |
| **Validation** | ✅ Runtime checks catch violations | ⚠️ Adds overhead (~1ms per event) | Only in dev/staging |
| **Complexity** | ⚠️ Zones add conceptual overhead | ✅ Clear boundaries | Visual zone diagrams |

**Guidelines for Custom Middleware:**

1. **Pre-Processing Zone (before PII filtering):**
   - ✅ Add business context fields
   - ✅ Enrich with database lookups
   - ✅ Add user attributes (will be filtered if PII)
   - ❌ Don't assume PII is already filtered

2. **Security Zone (PII filtering):**
   - ❌ DO NOT add custom middleware here
   - ⚠️ Only E11y::Middleware::PIIFiltering should run
   - ⚠️ Treat this zone as read-only (no custom code)

3. **Post-Processing Zone (after PII filtering):**
   - ✅ Add technical metadata (timestamps, versions)
   - ✅ Add tracing context (trace_id, span_id)
   - ✅ Transform structure (abbreviate keys)
   - ❌ DO NOT add PII fields
   - ❌ DO NOT modify filtered fields

**Monitoring (C19):**

```ruby
# Prometheus/Yabeda metrics
Yabeda.configure do
  group :e11y_pipeline do
    counter :zone_violations, comment: 'Pipeline zone violations detected', tags: [:middleware, :zone, :violation_type]
    counter :pii_bypass_prevented, comment: 'PII bypass attempts prevented', tags: [:middleware]
  end
end

# Alert rules (Grafana)
# Alert: zone_violations > 0 in production (critical!)
# Alert: pii_bypass_prevented > 0 (investigate immediately)
```

**Related Conflicts:**
- **C01:** Audit events skip PII filtering via contains_pii false (see §3.3)
- **C08:** Baggage PII protection (see ADR-007)

---

## 7. See Also

- **ADR-001: Architecture** - Pipeline architecture and middleware chain
- **ADR-006: Security & Compliance** - PII filtering, encryption requirements
- **ADR-012: Event Evolution & Versioning** - Full versioning design
- **ADR-013: Reliability & Error Handling** - DLQ replay considerations
- **UC-012: Audit Trail** - Audit event use cases

---

**Status:** ✅ Stable - Do not change order without updating all ADRs!
